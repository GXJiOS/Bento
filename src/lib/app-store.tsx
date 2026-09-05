import {
  createContext,
  type PropsWithChildren,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { loadPreviewState, savePreviewState, type PreviewState } from './persistence';
import type { ToolCategory } from '../types';

interface AppStoreValue {
  state: PreviewState;
  selectTool(id: string): void;
  toggleFavorite(id: string): void;
  toggleCategory(category: ToolCategory): void;
  setMemoryEnabled(enabled: boolean): void;
  rememberInput(id: string, value: string): void;
}

const AppStore = createContext<AppStoreValue | null>(null);

export function AppStoreProvider({ children }: PropsWithChildren) {
  const [state, setState] = useState(loadPreviewState);

  useEffect(() => savePreviewState(state), [state]);

  const selectTool = useCallback((id: string) => {
    setState((current) => ({ ...current, selectedToolId: id }));
  }, []);

  const toggleFavorite = useCallback((id: string) => {
    setState((current) => ({
      ...current,
      favorites: current.favorites.includes(id)
        ? current.favorites.filter((favorite) => favorite !== id)
        : [...current.favorites, id],
    }));
  }, []);

  const toggleCategory = useCallback((category: ToolCategory) => {
    setState((current) => ({
      ...current,
      expanded: current.expanded.includes(category)
        ? current.expanded.filter((item) => item !== category)
        : [...current.expanded, category],
    }));
  }, []);

  const setMemoryEnabled = useCallback((enabled: boolean) => {
    setState((current) => ({
      ...current,
      memoryEnabled: enabled,
      memory: enabled ? current.memory : {},
    }));
  }, []);

  const rememberInput = useCallback((id: string, value: string) => {
    setState((current) => {
      if (!current.memoryEnabled) return current;
      const memory = { ...current.memory };
      if (!value || value.length > 32_768) delete memory[id];
      else memory[id] = value;
      return { ...current, memory };
    });
  }, []);

  const value = useMemo<AppStoreValue>(
    () => ({
      state,
      selectTool,
      toggleFavorite,
      toggleCategory,
      setMemoryEnabled,
      rememberInput,
    }),
    [rememberInput, selectTool, setMemoryEnabled, state, toggleCategory, toggleFavorite],
  );

  return <AppStore.Provider value={value}>{children}</AppStore.Provider>;
}

export function useAppStore(): AppStoreValue {
  const store = useContext(AppStore);
  if (!store) throw new Error('useAppStore must be used inside AppStoreProvider');
  return store;
}

export function useToolInput(id: string, defaultValue: string) {
  const { state, rememberInput } = useAppStore();
  const [value, setValue] = useState(() =>
    state.memoryEnabled && state.memory[id] ? state.memory[id] : defaultValue,
  );
  const firstRender = useRef(true);

  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    rememberInput(id, value);
  }, [id, rememberInput, value]);

  return [value, setValue] as const;
}

