import { useState, type FormEvent } from 'react';

import { useAuth } from '../auth/AuthProvider';
import { BrandMark } from '../components/Icons';
import { configMissing } from '../lib/supabase';

export function Login() {
  const { signIn, checking, error } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const submit = (e: FormEvent) => {
    e.preventDefault();
    signIn(email.trim(), password);
  };

  return (
    <div className="login">
      <form className="card stack" onSubmit={submit}>
        <div className="brand" style={{ padding: 0 }}>
          <div className="brand-mark"><BrandMark /></div>
          <div>
            <div className="brand-name">smart<span>fit</span></div>
            <div className="brand-sub">Admin panel</div>
          </div>
        </div>
        <div>
          <h1>Sign in</h1>
          <p className="muted" style={{ margin: '4px 0 0' }}>Admin accounts only.</p>
        </div>
        {configMissing && (
          <div className="alert">Missing VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY. Copy .env.example to .env.local.</div>
        )}
        {error && <div className="alert" role="alert">{error}</div>}
        <div className="field">
          <label htmlFor="email">Email</label>
          <input id="email" className="input" type="email" autoComplete="username" required value={email}
            onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="password">Password</label>
          <input id="password" className="input" type="password" autoComplete="current-password" required value={password}
            onChange={(e) => setPassword(e.target.value)} />
        </div>
        <button className="btn btn-primary" type="submit" disabled={checking || configMissing}>
          {checking ? 'Checking…' : 'Sign in'}
        </button>
      </form>
    </div>
  );
}
