import { useMemo, useState } from 'react';
import { CheckControl, OptionLabel, SegmentedControl } from '../components/Controls';
import { ConverterWorkspace, type LoadedFile } from '../components/ConverterWorkspace';
import { convertBase64, encodeBytesAsBase64 } from '../lib/converters';
import { useToolInput } from '../lib/app-store';
import type { ConvertDirection } from '../types';

export function Base64Tool() {
  const [input, setInput] = useToolInput('base64', 'Hello, 世界 🌍');
  const [direction, setDirection] = useState<ConvertDirection>('encode');
  const [urlSafe, setUrlSafe] = useState(false);
  const [wrapLines, setWrapLines] = useState(false);
  const result = useMemo(
    () => convertBase64(input, { direction, urlSafe, wrapLines }),
    [direction, input, urlSafe, wrapLines],
  );

  const swap = () => {
    if (!result.text) return;
    setInput(result.text);
    setDirection((current) => (current === 'encode' ? 'decode' : 'encode'));
  };

  const load = ({ bytes }: LoadedFile) => {
    try {
      setInput(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    } catch {
      setInput(encodeBytesAsBase64(bytes));
      setDirection('decode');
    }
  };

  return (
    <ConverterWorkspace
      error={result.error}
      input={input}
      okText={direction === 'encode' ? '编码成功' : '解码成功'}
      onInput={setInput}
      onLoadFile={load}
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
          <CheckControl checked={urlSafe} label="URL-safe" onChange={setUrlSafe} />
          <CheckControl checked={wrapLines} label="每 76 字符换行" onChange={setWrapLines} />
        </>
      }
      output={result.text}
    />
  );
}
