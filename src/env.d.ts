/// <reference types="vite/client" />

type BentoCommand = 'open-palette' | 'open-settings';

interface BentoDesktopBridge {
  platform: string;
  readClipboard(): Promise<string>;
  writeClipboard(value: string): Promise<void>;
  openFile(): Promise<{ name: string; base64: string } | null>;
  saveText(value: string): Promise<boolean>;
  onCommand(callback: (command: BentoCommand) => void): () => void;
}

interface Window {
  bentoDesktop?: BentoDesktopBridge;
}
