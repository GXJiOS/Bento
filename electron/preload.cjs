const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('bentoDesktop', {
  platform: process.platform,
  readClipboard: () => ipcRenderer.invoke('bento:clipboard-read'),
  writeClipboard: (value) => ipcRenderer.invoke('bento:clipboard-write', value),
  openFile: () => ipcRenderer.invoke('bento:open-file'),
  saveText: (value) => ipcRenderer.invoke('bento:save-text', value),
  onCommand: (callback) => {
    const listener = (_event, command) => callback(command);
    ipcRenderer.on('bento:command', listener);
    return () => ipcRenderer.removeListener('bento:command', listener);
  },
});

