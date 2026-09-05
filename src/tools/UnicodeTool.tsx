import { useMemo, useState } from 'react';
import { CheckControl, OptionLabel, SegmentedControl } from '../components/Controls';
import { ConverterWorkspace } from '../components/ConverterWorkspace';
import {
  decodeUnicode,
  encodeUnicode,
  unicodeStats,
  type UnicodeStyle,
} from '../lib/converters';
import { useToolInput } from '../lib/app-store';
import type { ConvertDirection } from '../types';

export function UnicodeTool() {
  const [input, setInput] = useToolInput('unicode', 'Hello, 世界 🌍');
  const [direction, setDirection] = useState<ConvertDirection>('encode');
  const [style, setStyle] = useState<UnicodeStyle>('backslash-u');
  const [onlyNonAscii, setOnlyNonAscii] = useState(true);
  const [lowercase, setLowercase] = useState(false);
  const result = useMemo(
    () => direction === 'encode'
      ? { text: encodeUnicode(input, { style, onlyNonAscii, lowercase }) }
      : decodeUnicode(input),
    [direction, input, lowercase, onlyNonAscii, style],
  );
  const stats = unicodeStats(direction === 'encode' ? input : result.text);

  const swap = () => {
    if (!result.text) return;
    setInput(result.text);
    setDirection((current) => (current === 'encode' ? 'decode' : 'encode'));
  };

  return (
    <ConverterWorkspace
      error={result.error}
      input={input}
      okText={direction === 'encode' ? '编码成功' : '解码成功'}
      onInput={setInput}
      onSwap={swap}
      options={
        <>
          <OptionLabel>方向</OptionLabel>
          <SegmentedControl<ConvertDirection>
            accent
            ariaLabel="转换方向"
            onChange={setDirection}
            options={[{ value: 'encode', label: '编码' }, { value: 'decode', label: '解码' }]}
            value={direction}
          />
          <span className="option-divider" />
          {direction === 'encode' ? (
            <>
              <SegmentedControl<UnicodeStyle>
                ariaLabel="Unicode 输出格式"
                onChange={setStyle}
                options={[
                  { value: 'backslash-u', label: '\\uXXXX' },
                  { value: 'braces', label: '\\u{...}' },
                  { value: 'html-decimal', label: '&#123;' },
                  { value: 'html-hex', label: '&#x7B;' },
                ]}
                value={style}
              />
              <CheckControl checked={onlyNonAscii} label="只转非 ASCII" onChange={setOnlyNonAscii} />
              <CheckControl checked={lowercase} label="小写十六进制" onChange={setLowercase} />
            </>
          ) : (
            <span className="option-hint">自动识别 \\uXXXX · \\u&#123;...&#125; · &amp;#123; · &amp;#x7B; · \\xFF</span>
          )}
        </>
      }
      output={result.text}
      trailing={`${stats.scalars} 标量 · ${stats.utf16} UTF-16`}
    />
  );
}
