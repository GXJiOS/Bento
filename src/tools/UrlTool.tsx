import { useMemo, useState } from 'react';
import { CheckControl, OptionLabel, SegmentedControl } from '../components/Controls';
import { ConverterWorkspace } from '../components/ConverterWorkspace';
import { countUrlParameters, decodeUrl, encodeUrl, type UrlScope } from '../lib/converters';
import { useToolInput } from '../lib/app-store';
import type { ConvertDirection } from '../types';

export function UrlTool() {
  const [input, setInput] = useToolInput(
    'url',
    'https://example.com/搜索?q=Swift 并发&page=1',
  );
  const [direction, setDirection] = useState<ConvertDirection>('encode');
  const [scope, setScope] = useState<UrlScope>('whole');
  const [plusAsSpace, setPlusAsSpace] = useState(true);
  const result = useMemo(
    () => direction === 'encode' ? encodeUrl(input, scope) : decodeUrl(input, plusAsSpace),
    [direction, input, plusAsSpace, scope],
  );
  const parameterSource = direction === 'encode' ? input : result.text || input;
  const parameterCount = countUrlParameters(parameterSource);

  return (
    <ConverterWorkspace
      error={result.error}
      input={input}
      okText={direction === 'encode' ? '编码成功' : '解码成功'}
      onInput={setInput}
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
              <OptionLabel>范围</OptionLabel>
              <SegmentedControl<UrlScope>
                ariaLabel="编码范围"
                onChange={setScope}
                options={[
                  { value: 'component', label: '参数值' },
                  { value: 'query', label: '查询串' },
                  { value: 'whole', label: '整条 URL' },
                ]}
                value={scope}
              />
            </>
          ) : (
            <CheckControl checked={plusAsSpace} label="+ 视为空格" onChange={setPlusAsSpace} />
          )}
        </>
      }
      output={result.text}
      placeholder="粘贴一条 URL 或参数值…"
      trailing={parameterCount === null ? '无查询串' : `${parameterCount} 个参数`}
    />
  );
}
