const { app, BrowserWindow, clipboard, dialog, ipcMain, Menu, nativeImage, Tray } = require('electron');
const path = require('node:path');

app.setName('Bento');
app.setPath('userData', path.join(app.getPath('appData'), 'Bento Electron Preview'));

let mainWindow = null;
let tray = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1020,
    height: 660,
    minWidth: 860,
    minHeight: 520,
    show: false,
    backgroundColor: '#f1f1f4',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 18, y: 18 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  mainWindow.once('ready-to-show', () => mainWindow?.show());

  const devServer = process.env.BENTO_VITE_DEV_SERVER_URL;
  if (devServer) {
    mainWindow.loadURL(devServer);
  } else {
    mainWindow.loadFile(path.join(__dirname, '..', 'dist', 'index.html'));
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

function showMainWindow() {
  if (!mainWindow) createWindow();
  mainWindow?.show();
  mainWindow?.focus();
}

function createTray() {
  const source = path.join(__dirname, '..', 'icon', 'source-1024.png');
  const image = nativeImage.createFromPath(source).resize({ width: 18, height: 18 });
  image.setTemplateImage(true);
  tray = new Tray(image);
  tray.setToolTip('Bento');
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: '显示 Bento', click: showMainWindow },
    {
      label: '命令面板',
      accelerator: 'CommandOrControl+K',
      click: () => {
        showMainWindow();
        mainWindow?.webContents.send('bento:command', 'open-palette');
      },
    },
    { type: 'separator' },
    { role: 'quit', label: '退出 Bento' },
  ]));
  tray.on('click', showMainWindow);
}

function installApplicationMenu() {
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {
      label: 'Bento',
      submenu: [
        { role: 'about', label: '关于 Bento' },
        { type: 'separator' },
        {
          label: '设置…',
          accelerator: 'CommandOrControl+,',
          click: () => mainWindow?.webContents.send('bento:command', 'open-settings'),
        },
        { type: 'separator' },
        { role: 'hide', label: '隐藏 Bento' },
        { role: 'hideOthers', label: '隐藏其他' },
        { role: 'unhide', label: '全部显示' },
        { type: 'separator' },
        { role: 'quit', label: '退出 Bento' },
      ],
    },
    {
      label: '编辑',
      submenu: [
        { role: 'undo', label: '撤销' },
        { role: 'redo', label: '重做' },
        { type: 'separator' },
        { role: 'cut', label: '剪切' },
        { role: 'copy', label: '复制' },
        { role: 'paste', label: '粘贴' },
        { role: 'selectAll', label: '全选' },
      ],
    },
    {
      label: '显示',
      submenu: [
        {
          label: '命令面板',
          accelerator: 'CommandOrControl+K',
          click: () => mainWindow?.webContents.send('bento:command', 'open-palette'),
        },
        { type: 'separator' },
        { role: 'togglefullscreen', label: '切换全屏' },
      ],
    },
    { role: 'windowMenu', label: '窗口' },
  ]));
}

ipcMain.handle('bento:clipboard-read', () => clipboard.readText());
ipcMain.handle('bento:clipboard-write', (_event, value) => clipboard.writeText(String(value)));
ipcMain.handle('bento:open-file', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile'],
  });
  if (result.canceled || result.filePaths.length === 0) return null;
  const filePath = result.filePaths[0];
  const { readFile } = require('node:fs/promises');
  const data = await readFile(filePath);
  return {
    name: path.basename(filePath),
    base64: data.toString('base64'),
  };
});
ipcMain.handle('bento:save-text', async (_event, value) => {
  const result = await dialog.showSaveDialog(mainWindow, {
    defaultPath: 'output.txt',
    filters: [{ name: '文本文件', extensions: ['txt'] }],
  });
  if (result.canceled || !result.filePath) return false;
  const { writeFile } = require('node:fs/promises');
  await writeFile(result.filePath, String(value), 'utf8');
  return true;
});

app.whenReady().then(() => {
  installApplicationMenu();
  createWindow();
  createTray();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
    else showMainWindow();
  });
});

app.on('window-all-closed', (event) => {
  event.preventDefault();
});
