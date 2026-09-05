import { useEffect, useState } from 'react';
import { toolById } from './data/tools';
import { useAppStore } from './lib/app-store';
import { CommandPalette, SettingsDialog, Sidebar, Toolbar } from './components/AppChrome';

export default function App() {
  const { state, selectTool } = useAppStore();
  const [sidebarQuery, setSidebarQuery] = useState('');
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const selected = toolById(state.selectedToolId) ?? toolById('base64');

  useEffect(() => {
    if (!selected?.implemented) selectTool('base64');
  }, [selectTool, selected]);

  useEffect(() => {
    const handleKey = (event: KeyboardEvent) => {
      const command = event.metaKey || event.ctrlKey;
      if (command && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setPaletteOpen(true);
      }
      if (command && event.key.toLowerCase() === 'f') {
        event.preventDefault();
        document.querySelector<HTMLInputElement>('#tool-search')?.focus();
      }
      if (command && event.key === ',') {
        event.preventDefault();
        setSettingsOpen(true);
      }
      if (event.key === 'Escape') {
        setPaletteOpen(false);
        setSettingsOpen(false);
      }
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, []);

  useEffect(() => window.bentoDesktop?.onCommand((command) => {
    if (command === 'open-palette') setPaletteOpen(true);
    if (command === 'open-settings') setSettingsOpen(true);
  }), []);

  if (!selected?.component) return null;
  const Tool = selected.component;

  return (
    <div className="window-shell">
      <Toolbar
        onOpenPalette={() => setPaletteOpen(true)}
        onOpenSettings={() => setSettingsOpen(true)}
        selected={selected}
      />
      <Sidebar
        onOpenSettings={() => setSettingsOpen(true)}
        onQuery={setSidebarQuery}
        query={sidebarQuery}
      />
      <main className="content-area" key={selected.id}><Tool /></main>
      <CommandPalette onClose={() => setPaletteOpen(false)} open={paletteOpen} />
      <SettingsDialog onClose={() => setSettingsOpen(false)} open={settingsOpen} />
    </div>
  );
}

