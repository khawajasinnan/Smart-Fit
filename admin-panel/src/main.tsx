import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';

import { AuthProvider, useAuth } from './auth/AuthProvider';
import { Layout } from './components/Layout';
import { ToastProvider } from './components/ui';
import { Catalog } from './pages/Catalog';
import { Dashboard } from './pages/Dashboard';
import { Feedback } from './pages/Feedback';
import { Login } from './pages/Login';
import { Moderation } from './pages/Moderation';
import { Scraper } from './pages/Scraper';
import { Services } from './pages/Services';
import { Users } from './pages/Users';
import './styles.css';

function Gate() {
  const { session, checking } = useAuth();
  if (checking && !session) return <div className="login"><p className="muted">Loading…</p></div>;
  if (!session) return <Login />;
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Dashboard />} />
        <Route path="users" element={<Users />} />
        <Route path="catalog" element={<Catalog />} />
        <Route path="scraper" element={<Scraper />} />
        <Route path="feedback" element={<Feedback />} />
        <Route path="moderation" element={<Moderation />} />
        <Route path="services" element={<Services />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <ToastProvider>
          <Gate />
        </ToastProvider>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
);
