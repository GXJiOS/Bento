import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { AppStoreProvider } from './lib/app-store';
import './styles.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <AppStoreProvider>
      <App />
    </AppStoreProvider>
  </React.StrictMode>,
);

