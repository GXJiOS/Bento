import { describe, expect, it } from 'vitest';
import {
  convertBase64,
  countUrlParameters,
  decodeUnicode,
  decodeUrl,
  encodeUnicode,
  encodeUrl,
  unicodeStats,
} from './converters';

describe('Base64', () => {
  it('matches the Swift default example', () => {
    const encoded = convertBase64('Hello, 世界 🌍', {
      direction: 'encode',
      urlSafe: false,
      wrapLines: false,
    });
    expect(encoded).toEqual({ text: 'SGVsbG8sIOS4lueVjCDwn4yN' });
    expect(
      convertBase64(encoded.text, {
        direction: 'decode',
        urlSafe: false,
        wrapLines: false,
      }),
    ).toEqual({ text: 'Hello, 世界 🌍' });
  });

  it('supports URL-safe output without padding', () => {
    expect(
      convertBase64('??>>', { direction: 'encode', urlSafe: true, wrapLines: false }).text,
    ).toBe('Pz8-Pg');
  });
});

describe('URL percent encoding', () => {
  it('preserves URL structure for whole URLs', () => {
    const value = 'https://example.com/搜索?q=Swift 并发&page=1';
    const result = encodeUrl(value, 'whole');
    expect(result.text).toBe(
      'https://example.com/%E6%90%9C%E7%B4%A2?q=Swift%20%E5%B9%B6%E5%8F%91&page=1',
    );
    expect(countUrlParameters(value)).toBe(2);
  });

  it('decodes plus signs as spaces when requested', () => {
    expect(decodeUrl('Swift+Concurrency%21', true)).toEqual({ text: 'Swift Concurrency!' });
  });
});

describe('Unicode escaping', () => {
  it('uses UTF-16 surrogate pairs for backslash-u output', () => {
    const encoded = encodeUnicode('Hello, 世界 🌍', {
      style: 'backslash-u',
      onlyNonAscii: true,
      lowercase: false,
    });
    expect(encoded).toBe('Hello, \\u4E16\\u754C \\uD83C\\uDF0D');
    expect(decodeUnicode(encoded)).toEqual({ text: 'Hello, 世界 🌍' });
  });

  it('supports scalar braces and HTML entities', () => {
    expect(
      encodeUnicode('🌍', { style: 'braces', onlyNonAscii: true, lowercase: false }),
    ).toBe('\\u{1F30D}');
    expect(decodeUnicode('&#x4E16;&#30028; \\u{1F30D}').text).toBe('世界 🌍');
    expect(unicodeStats('世界 🌍')).toEqual({ scalars: 4, utf16: 5 });
  });
});

