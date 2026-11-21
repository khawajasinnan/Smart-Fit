import { useEffect, useState } from 'react';
import { NavLink, Outlet } from 'react-router-dom';

import { useAuth } from '../auth/AuthProvider';
import {
  BrandMark, IconDashboard, IconFlag, IconHeart, IconMoon, IconPulse, IconShirt, IconSpider, IconSun, IconUsers,
} from './Icons';

const NAV = [
  { to: '/', label: 'Dashboard', icon: <IconDashboard />, end: true },
  { to: '/users', label: 'Users', icon: <IconUsers /> },
  { to: '/catalog', label: 'Catalog', icon: <IconShirt /> },
  { to: '/scraper', label: 'Scraping', icon: <IconSpider /> },
  { to: '/feedback', label: 'Feedback', icon: <IconHeart /> },
  { to: '/moderation', label: 'Moderation', icon: <IconFlag /> },
  { to: '/services', label: 'Services', icon: <IconPulse /> },
];

type Theme = 'light' | 'dark';

function readTheme(): Theme {
  try {
    const saved = localStorage.getItem('smartfit-admin-theme');
    if (saved === 'light' || saved === 'dark') return saved;
  } catch { /* storage blocked: fall back to the OS setting */ }
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function Layout() {
  const { session, signOut } = useAuth();
  const [theme, setTheme] = useState<Theme>(readTheme);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    try { localStorage.setItem('smartfit-admin-theme', theme); } catch { /* ignore */ }
  }, [theme]);

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark"><BrandMark /></div>
          <div>
            <div className="brand-name">smart<span>fit</span></div>
            <div className="brand-sub">Admin panel</div>
          </div>
        </div>
        <nav aria-label="Admin sections" style={{ display: 'contents' }}>
          {NAV.map((n) => (
            <NavLink key={n.to} to={n.to} end={n.end} className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}>
              {n.icon}{n.label}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-foot">
          <span className="who">{session?.user.email}</span>
          <div className="row">
            <button className="btn btn-sm" onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
              aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}>
              {theme === 'dark' ? <IconSun /> : <IconMoon />}
            </button>
            <button className="btn btn-sm" onClick={signOut}>Sign out</button>
          </div>
        </div>
      </aside>
      <main className="main">
        <Outlet />
      </main>
    </div>
  );
}
