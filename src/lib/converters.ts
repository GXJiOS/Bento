import type { ConversionResult } from '../types';

export interface Base64Options {
  direction: 'encode' | 'decode';
  urlSafe: boolean;
  wrapLines: boolean;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

export function encodeBytesAsBase64(bytes: Uint8Array): string {
  return bytesToBase64(bytes);
}

export function convertBase64(input: string, options: Base64Options): ConversionResult {
  if (!input) return { text: '' };

  if (options.direction === 'encode') {
    let text = bytesToBase64(new TextEncoder().encode(input));
    if (options.urlSafe) {
      text = text.replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '');
    }
    if (options.wrapLines) text = text.match(/.{1,76}/gu)?.join('\n') ?? text;
    return { text };
  }

  let source = input.replace(/\s/gu, '');
  if (options.urlSafe) source = source.replaceAll('-', '+').replaceAll('_', '/');
  source += '='.repeat((4 - (source.length % 4)) % 4);

  try {
    const binary = atob(source);
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    try {
      return { text: new TextDecoder('utf-8', { fatal: true }).decode(bytes) };
    } catch {
      return {
        text: '',
        error: `解码成功但不是 UTF-8 文本 · ${bytes.length} 字节二进制`,
      };
    }
  } catch {
    return { text: '', error: '无效的 Base64 · 出现字符集外的字符' };
  }
}

export type UrlScope = 'component' | 'query' | 'whole';

const unreserved = new Set(
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~',
);
const queryExtra = new Set('&=');
const wholeExtra = new Set(':/?#[]@!$&\'()*+,;=%');

function hasUnpairedSurrogate(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const unit = value.charCodeAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) return true;
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return true;
    }
  }
  return false;
}

export function encodeUrl(input: string, scope: UrlScope): ConversionResult {
  if (!input) return { text: '' };
  if (hasUnpairedSurrogate(input)) {
    return { text: '', error: '无法编码（输入包含无效的 Unicode 标量）' };
  }

  const allowed = new Set(unreserved);
  if (scope === 'query') queryExtra.forEach((character) => allowed.add(character));
  if (scope === 'whole') wholeExtra.forEach((character) => allowed.add(character));

  let output = '';
  for (const character of input) {
    if (character.length === 1 && allowed.has(character)) {
      output += character;
      continue;
    }
    const bytes = new TextEncoder().encode(character);
    output += [...bytes]
      .map((byte) => `%${byte.toString(16).toUpperCase().padStart(2, '0')}`)
      .join('');
  }
  return { text: output };
}

export function decodeUrl(input: string, plusAsSpace: boolean): ConversionResult {
  if (!input) return { text: '' };
  const source = plusAsSpace ? input.replaceAll('+', ' ') : input;
  try {
    return { text: decodeURIComponent(source) };
  } catch {
    return { text: '', error: '无效的百分号编码 · 出现不完整的 %XX 序列' };
  }
}

export function countUrlParameters(input: string): number | null {
  const queryStart = input.indexOf('?');
  if (queryStart < 0) return null;
  const query = input.slice(queryStart + 1);
  if (!query) return 0;
  return query.split('&').filter(Boolean).length;
}

export type UnicodeStyle = 'backslash-u' | 'braces' | 'html-decimal' | 'html-hex';

export interface UnicodeEncodeOptions {
  style: UnicodeStyle;
  onlyNonAscii: boolean;
  lowercase: boolean;
}

function hex(value: number, lowercase: boolean, width = 0): string {
  const output = value.toString(16).padStart(width, '0');
  return lowercase ? output : output.toUpperCase();
}

export function encodeUnicode(input: string, options: UnicodeEncodeOptions): string {
  if (!input) return '';
  let output = '';

  if (options.style === 'braces') {
    for (const character of input) {
      const scalar = character.codePointAt(0) ?? 0;
      if (options.onlyNonAscii && scalar < 0x80) output += character;
      else output += `\\u{${hex(scalar, options.lowercase)}}`;
    }
    return output;
  }

  for (let index = 0; index < input.length; index += 1) {
    const unit = input.charCodeAt(index);
    if (options.onlyNonAscii && unit < 0x80) {
      output += String.fromCharCode(unit);
      continue;
    }
    if (options.style === 'backslash-u') output += `\\u${hex(unit, options.lowercase, 4)}`;
    if (options.style === 'html-decimal') output += `&#${unit};`;
    if (options.style === 'html-hex') output += `&#x${hex(unit, options.lowercase)};`;
  }
  return output;
}

function isHex(value: string): boolean {
  return /^[0-9a-f]+$/iu.test(value);
}

export function decodeUnicode(input: string): ConversionResult {
  if (!input) return { text: '' };
  const characters = Array.from(input);
  const output: string[] = [];
  const units: number[] = [];
  let sawEscape = false;

  const flushUnits = () => {
    if (units.length === 0) return;
    const chunkSize = 0x8000;
    for (let index = 0; index < units.length; index += chunkSize) {
      output.push(String.fromCharCode(...units.slice(index, index + chunkSize)));
    }
    units.length = 0;
  };

  for (let index = 0; index < characters.length; ) {
    if (characters[index] === '\\' && index + 1 < characters.length) {
      const marker = characters[index + 1];
      if ((marker === 'u' || marker === 'U') && characters[index + 2] === '{') {
        const close = characters.indexOf('}', index + 3);
        if (close >= 0) {
          const digits = characters.slice(index + 3, close).join('');
          const value = Number.parseInt(digits, 16);
          if (digits && isHex(digits) && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff)) {
            flushUnits();
            output.push(String.fromCodePoint(value));
            index = close + 1;
            sawEscape = true;
            continue;
          }
        }
      }
      if ((marker === 'u' || marker === 'U') && index + 5 < characters.length) {
        const digits = characters.slice(index + 2, index + 6).join('');
        if (isHex(digits)) {
          units.push(Number.parseInt(digits, 16));
          index += 6;
          sawEscape = true;
          continue;
        }
      }
      if (marker === 'x' && index + 3 < characters.length) {
        const digits = characters.slice(index + 2, index + 4).join('');
        if (isHex(digits)) {
          units.push(Number.parseInt(digits, 16));
          index += 4;
          sawEscape = true;
          continue;
        }
      }
    }

    if (characters[index] === '&' && characters[index + 1] === '#') {
      const close = characters.indexOf(';', index + 2);
      if (close >= 0) {
        const body = characters.slice(index + 2, close).join('');
        const hexValue = body.toLowerCase().startsWith('x');
        const digits = hexValue ? body.slice(1) : body;
        const valid = hexValue ? isHex(digits) : /^\d+$/u.test(digits);
        const value = Number.parseInt(digits, hexValue ? 16 : 10);
        if (valid && value <= 0x10ffff) {
          if (value <= 0xffff) units.push(value);
          else {
            flushUnits();
            output.push(String.fromCodePoint(value));
          }
          index = close + 1;
          sawEscape = true;
          continue;
        }
      }
    }

    const character = characters[index];
    const scalar = character.codePointAt(0) ?? 0;
    if (scalar <= 0xffff) units.push(scalar);
    else {
      flushUnits();
      output.push(character);
    }
    index += 1;
  }

  flushUnits();
  const text = output.join('');
  return sawEscape ? { text } : { text, error: '没有发现转义序列 · 输入原样返回' };
}

export function unicodeStats(value: string): { scalars: number; utf16: number } {
  return { scalars: Array.from(value).length, utf16: value.length };
}

