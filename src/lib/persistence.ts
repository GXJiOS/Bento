import type { ToolCategory } from '../types';

export interface PreviewState {
  selectedToolId: string;
  favorites: string[];
  expanded: ToolCategory[];
  memoryEnabled: boolean;
  memory: Record<string, string>;
}

const storageKey = 'bento.electron.preview.state.v1';

export const defaultPreviewState: PreviewState = {
  selectedToolId: 'base64',
  favorites: ['base64', 'url', 'unicode'],
  expanded: ['encoding', 'formatting', 'style', 'image', 'system', 'network'],
  memoryEnabled: true,
  memory: {},
};

export function loadPreviewState(): PreviewState {
  try {
    const raw = window.localStorage.getItem(storageKey);
    if (!raw) return defaultPreviewState;
    const parsed = JSON.parse(raw) as Partial<PreviewState>;
    return {
      ...defaultPreviewState,
      ...parsed,
      favorites: Array.isArray(parsed.favorites) ? parsed.favorites : defaultPreviewState.favorites,
      expanded: Array.isArray(parsed.expanded) ? parsed.expanded : defaultPreviewState.expanded,
      memory: parsed.memory && typeof parsed.memory === 'object' ? parsed.memory : {},
    };
  } catch {
    return defaultPreviewState;
  }
}

export function savePreviewState(state: PreviewState): void {
  try {
    window.localStorage.setItem(storageKey, JSON.stringify(state));
  } catch {
    // 预览状态写入失败时保持当前会话可用。
  }
}

