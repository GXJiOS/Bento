import { type ReactNode, useRef, useState } from 'react';
import { Icon } from './Icon';

export interface LoadedFile {
  name: string;
  bytes: Uint8Array;
}

interface ConverterWorkspaceProps {
  input: string;
  output: string;
  error?: string;
  placeholder?: string;
  okText: string;
  trailing?: string;
  options: ReactNode;
  onInput(value: string): void;
  onSwap?: () => void;
  onLoadFile?: (file: LoadedFile) => void;
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function readClipboard(): Promise<string> {
  if (window.bentoDesktop) return window.bentoDesktop.readClipboard();
  return navigator.clipboard.readText();
}

async function writeClipboard(value: string): Promise<void> {
  if (window.bentoDesktop) return window.bentoDesktop.writeClipboard(value);
  return navigator.clipboard.writeText(value);
}

function lineCount(value: string): number {
  return value.split(/\r?\n/u).length;
}

export function ConverterWorkspace({
  input,
  output,
  error,
  placeholder = '在此输入或粘贴…',
  okText,
  trailing = 'UTF-8',
  options,
  onInput,
  onSwap,
  onLoadFile,
}: ConverterWorkspaceProps) {
  const fileInput = useRef<HTMLInputElement>(null);
  const [copied, setCopied] = useState(false);
  const [statusVisible, setStatusVisible] = useState(true);

  const paste = async () => {
    try {
      const value = await readClipboard();
      if (value) onInput(value);
    } catch {
      // 浏览器未授权剪贴板时保持原输入。
    }
  };

  const copy = async () => {
    if (!output) return;
    try {
      await writeClipboard(output);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1200);
    } catch {
      setCopied(false);
    }
  };

  const save = async () => {
    if (!output) return;
    if (window.bentoDesktop) {
      await window.bentoDesktop.saveText(output);
      return;
    }
    const url = URL.createObjectURL(new Blob([output], { type: 'text/plain;charset=utf-8' }));
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = 'output.txt';
    anchor.click();
    URL.revokeObjectURL(url);
  };

  const openFile = async () => {
    if (!onLoadFile) return;
    if (window.bentoDesktop) {
      const file = await window.bentoDesktop.openFile();
      if (file) onLoadFile({ name: file.name, bytes: base64ToBytes(file.base64) });
      return;
    }
    fileInput.current?.click();
  };

  const importBrowserFile = async (file: File | undefined) => {
    if (!file || !onLoadFile) return;
    onLoadFile({ name: file.name, bytes: new Uint8Array(await file.arrayBuffer()) });
  };

  const visibleOutput = error ? '' : output;
  const statusLevel = !input ? 'idle' : error ? 'error' : 'ok';
  const statusText = !input ? '等待输入' : error ?? okText;

  return (
    <section className="tool-workspace">
      <div className="option-bar">
        {options}
        <span className="option-bar-spacer" />
        <div className="encoding-control">
          <span>字符编码</span>
          <button type="button">{trailing}<Icon className="encoding-chevron" name="chevron" size={14} /></button>
        </div>
      </div>
      <div className="converter-grid">
        <article className="tool-card tool-card-input">
          <header className="card-header">
            <div className="card-title card-title-input">
              <span className="editor-title-icon"><Icon name="file-up" size={17} /></span>
              输入内容
            </div>
          </header>
          <textarea
            aria-label="输入"
            className="code-area"
            onChange={(event) => {
              setStatusVisible(true);
              onInput(event.target.value);
            }}
            placeholder={placeholder}
            spellCheck={false}
            value={input}
          />
          <footer className="card-footer">
            <button className="plain-button" onClick={paste} type="button">
              <Icon name="clipboard-paste" size={16} />粘贴
            </button>
            {onLoadFile ? (
              <button className="plain-button" onClick={openFile} type="button">
                <Icon name="file-up" size={16} />载入文件
              </button>
            ) : null}
            <button className="plain-button" disabled={!input} onClick={() => onInput('')} type="button">
              <Icon name="trash" size={16} />清空
            </button>
            <span className="footer-spacer" />
            <span className="editor-count">{lineCount(input)} 行 · {Array.from(input).length} 字符</span>
            <input
              hidden
              onChange={(event) => importBrowserFile(event.target.files?.[0])}
              ref={fileInput}
              type="file"
            />
          </footer>
        </article>

        {onSwap ? (
          <button aria-label="交换输入与输出" className="swap-button" onClick={onSwap} type="button">
            <Icon name="arrow-left-right" size={23} />
            <span>转换</span>
          </button>
        ) : null}

        <article className="tool-card tool-card-output">
          <header className="card-header">
            <div className="card-title card-title-output">
              <span className="editor-title-icon"><Icon name="download" size={17} /></span>
              输出结果
            </div>
            <div className="output-actions">
              <button className="plain-button copy-result" disabled={!visibleOutput} onClick={copy} type="button">
                <Icon name={copied ? 'check' : 'copy'} size={16} />{copied ? '已复制' : '复制结果'}
              </button>
              <button className="plain-button" disabled={!visibleOutput} onClick={save} type="button">
                <Icon name="download" size={16} />下载文件
              </button>
            </div>
          </header>
          <textarea
            aria-label="输出"
            className="code-area code-area-output"
            readOnly
            spellCheck={false}
            value={visibleOutput}
          />
          <footer className="card-footer">
            <span className="footer-spacer" />
            <span className="editor-count">{error ? '—' : `${Array.from(output).length} 字符`}</span>
          </footer>
        </article>
      </div>
      {statusVisible ? (
        <div className={`status-line status-${statusLevel}`}>
          <span className="status-indicator">
            <Icon name={statusLevel === 'error' ? 'x-circle' : statusLevel === 'ok' ? 'check-circle' : 'circle'} size={20} />
            {statusText}
          </span>
          <button aria-label="关闭状态提示" onClick={() => setStatusVisible(false)} type="button"><Icon name="x" size={17} /></button>
        </div>
      ) : <div className="status-line-placeholder" />}
    </section>
  );
}
