import { useEffect, useMemo, useRef, useState } from 'react';
import bentoIcon from '../../icon/source-1024.png';
import { categoryById, migratedTools, searchTools, tools } from '../data/tools';
import { useAppStore } from '../lib/app-store';
import type { ToolDefinition } from '../types';
import { Icon } from './Icon';
import { Keycap } from './Controls';

function CategoryIcon({ tool, size = 'small' }: { tool: ToolDefinition; size?: 'small' | 'large' }) {
  const category = categoryById(tool.category);
  return (
    <span className={`category-icon category-icon-${size}`} style={{ '--tool-tint': category.tint } as React.CSSProperties}>
      <Icon name={tool.icon} size={size === 'large' ? 16 : 13} strokeWidth={2} />
    </span>
  );
}

interface ToolbarProps {
  selected: ToolDefinition;
  onOpenPalette(): void;
  onOpenSettings(): void;
}

export function Toolbar({ selected, onOpenPalette, onOpenSettings }: ToolbarProps) {
  const { state, toggleFavorite } = useAppStore();
  const favorite = state.favorites.includes(selected.id);
  const navigation = [
    { label: '全部工具', active: true },
    { label: '编码', active: false },
    { label: '格式化', active: false },
    { label: '生成器', active: false },
    { label: '网络', active: false },
    { label: '安全', active: false },
  ];

  return (
    <header className={`titlebar ${window.bentoDesktop ? 'is-electron' : ''}`}>
      <div className="brand-area">
        <img alt="" className="bento-mark" src={bentoIcon} />
        <span className="brand-name">Bento</span>
      </div>
      <div className="toolbar-main">
        <nav aria-label="工具分类" className="web-navigation">
          {navigation.map((item) => (
            <button
              className={item.active ? 'is-active' : undefined}
              key={item.label}
              onClick={onOpenPalette}
              type="button"
            >
              {item.label}
            </button>
          ))}
        </nav>
        <span className="toolbar-spacer" />
        <button
          aria-label={favorite ? '取消收藏' : '收藏'}
          className={`toolbar-button ${favorite ? 'is-favorite' : ''}`}
          onClick={() => toggleFavorite(selected.id)}
          type="button"
        >
          <Icon name="star" size={20} />
        </button>
        <button aria-label="设置" className="toolbar-button theme-button" onClick={onOpenSettings} type="button">
          <Icon name="settings" size={19} />
        </button>
        <button aria-label="个人设置" className="avatar-button" onClick={onOpenSettings} type="button">
          B
        </button>
      </div>
    </header>
  );
}

interface SidebarProps {
  query: string;
  onQuery(value: string): void;
  onOpenSettings(): void;
}

export function Sidebar({ query, onQuery, onOpenSettings }: SidebarProps) {
  const { state, selectTool } = useAppStore();
  const results = useMemo(() => searchTools(query), [query]);
  const shortLabel: Record<string, string> = { base64: 'B64', url: 'URL', unicode: 'U+' };

  const resultRow = (tool: ToolDefinition) => (
    <button
      className={`tool-row ${state.selectedToolId === tool.id ? 'is-selected' : ''} ${tool.implemented ? '' : 'is-planned'}`}
      disabled={!tool.implemented}
      key={tool.id}
      onClick={() => {
        selectTool(tool.id);
        onQuery('');
      }}
      title={tool.implemented ? tool.name : `${tool.name} · 后续迁移阶段`}
      type="button"
    >
      <span>{tool.name}</span>
      {!tool.implemented ? <span className="planned-dot" /> : null}
    </button>
  );

  return (
    <aside className="sidebar">
      <div className="sidebar-search">
        <Icon name="search" size={18} />
        <input
          aria-label="搜索工具"
          id="tool-search"
          onChange={(event) => onQuery(event.target.value)}
          placeholder={`搜索 ${tools.length} 个开发工具`}
          value={query}
        />
        {query ? (
          <button aria-label="清空搜索" onClick={() => onQuery('')} type="button"><Icon name="x-circle" size={16} /></button>
        ) : <Keycap>⌘K</Keycap>}
      </div>

      <div className="recent-label"><Icon name="circle" size={16} /><strong>最近使用</strong></div>
      <nav aria-label="最近使用的工具" className="recent-tools">
        {migratedTools.map((tool) => (
          <button
            className={state.selectedToolId === tool.id ? 'is-selected' : undefined}
            key={tool.id}
            onClick={() => selectTool(tool.id)}
            type="button"
          >
            <span className={`recent-tool-badge recent-tool-${tool.id}`}>{shortLabel[tool.id]}</span>
            <strong>{tool.name}</strong>
          </button>
        ))}
      </nav>
      <button aria-label="设置" className="recent-settings" onClick={onOpenSettings} type="button">
        <Icon name="settings" size={17} />
      </button>

      {query ? (
        <section className="search-popover">
          <div className="sidebar-caption">搜索结果 <span>{results.length}</span></div>
          {results.length ? results.slice(0, 12).map((tool) => (
            <div className="search-result-row" key={tool.id}>
              <CategoryIcon tool={tool} />
              {resultRow(tool)}
            </div>
          )) : <p className="empty-results">没有匹配的工具</p>}
        </section>
      ) : null}
    </aside>
  );
}

interface CommandPaletteProps {
  open: boolean;
  onClose(): void;
}

export function CommandPalette({ open, onClose }: CommandPaletteProps) {
  const { selectTool } = useAppStore();
  const [query, setQuery] = useState('');
  const input = useRef<HTMLInputElement>(null);
  const results = searchTools(query);

  useEffect(() => {
    if (!open) return;
    setQuery('');
    window.setTimeout(() => input.current?.focus(), 20);
  }, [open]);

  if (!open) return null;

  const choose = (tool: ToolDefinition) => {
    if (!tool.implemented) return;
    selectTool(tool.id);
    onClose();
  };

  return (
    <div className="overlay" onMouseDown={onClose} role="presentation">
      <section aria-label="命令面板" aria-modal="true" className="command-palette" onMouseDown={(event) => event.stopPropagation()} role="dialog">
        <div className="palette-input">
          <Icon name="search" size={18} />
          <input
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter') {
                const first = results.find((tool) => tool.implemented);
                if (first) choose(first);
              }
              if (event.key === 'Escape') onClose();
            }}
            placeholder="搜索工具、命令或拼音首字母…"
            ref={input}
            value={query}
          />
          <Keycap>ESC</Keycap>
        </div>
        <div className="palette-results">
          <div className="palette-caption">{query ? '搜索结果' : '已迁移工具'}</div>
          {results.slice(0, 12).map((tool) => (
            <button disabled={!tool.implemented} key={tool.id} onClick={() => choose(tool)} type="button">
              <CategoryIcon tool={tool} />
              <span><strong>{tool.name}</strong><small>{categoryById(tool.category).title}</small></span>
              {!tool.implemented ? <em>待迁移</em> : <Keycap>↩</Keycap>}
            </button>
          ))}
        </div>
        <footer><span><Keycap>↑↓</Keycap> 选择</span><span><Keycap>↩</Keycap> 打开</span><span><Keycap>ESC</Keycap> 关闭</span></footer>
      </section>
    </div>
  );
}

interface SettingsDialogProps {
  open: boolean;
  onClose(): void;
}

export function SettingsDialog({ open, onClose }: SettingsDialogProps) {
  const { state, setMemoryEnabled } = useAppStore();
  if (!open) return null;

  return (
    <div className="overlay" onMouseDown={onClose} role="presentation">
      <section aria-label="设置" aria-modal="true" className="settings-dialog" onMouseDown={(event) => event.stopPropagation()} role="dialog">
        <header><span><Icon name="settings" size={17} />设置</span><button aria-label="关闭" onClick={onClose} type="button"><Icon name="x" size={16} /></button></header>
        <div className="settings-body">
          <h3>迁移预览</h3>
          <div className="settings-row">
            <span><strong>工具输入记忆</strong><small>保存在独立的 Electron Preview 数据目录</small></span>
            <label className="switch"><input checked={state.memoryEnabled} onChange={(event) => setMemoryEnabled(event.target.checked)} type="checkbox" /><i /></label>
          </div>
          <div className="settings-row">
            <span><strong>外观</strong><small>跟随 macOS 系统设置</small></span>
            <span className="settings-value">自动</span>
          </div>
          <div className="migration-card">
            <div><strong>{migratedTools.length}</strong><span>已迁移</span></div>
            <div><strong>{tools.length - migratedTools.length}</strong><span>后续阶段</span></div>
            <p>当前预览不会读取或覆盖 Swift 版 Bento 的用户数据。</p>
          </div>
        </div>
      </section>
    </div>
  );
}
