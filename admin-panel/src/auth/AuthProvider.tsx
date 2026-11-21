import type { Session } from '@supabase/supabase-js';
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';

import { api, ApiError } from '../lib/api';
import { supabase } from '../lib/supabase';

interface AuthState {
  session: Session | null;
  checking: boolean;
  error: string | null;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [checking, setChecking] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // A session only counts once the gateway confirms the admin role.
  const verify = useCallback(async (s: Session | null) => {
    if (!s) {
      setSession(null);
      setChecking(false);
      return;
    }
    try {
      const me = await api<{ is_admin: boolean }>('/auth/me');
      if (!me.is_admin) {
        await supabase.auth.signOut();
        setSession(null);
        setError('This account is not a SmartFit admin.');
      } else {
        setSession(s);
        setError(null);
      }
    } catch (e) {
      setSession(null);
      setError(e instanceof ApiError ? e.message : 'Could not verify your account.');
    } finally {
      setChecking(false);
    }
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => verify(data.session));
    const { data } = supabase.auth.onAuthStateChange((event, s) => {
      if (event === 'SIGNED_OUT') setSession(null);
      if (event === 'TOKEN_REFRESHED' && s) setSession(s);
    });
    return () => data.subscription.unsubscribe();
  }, [verify]);

  const signIn = useCallback(async (email: string, password: string) => {
    setError(null);
    setChecking(true);
    const { data, error: authError } = await supabase.auth.signInWithPassword({ email, password });
    if (authError) {
      setChecking(false);
      setError(authError.message === 'Invalid login credentials' ? 'Wrong email or password.' : authError.message);
      return;
    }
    await verify(data.session);
  }, [verify]);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
    setSession(null);
  }, []);

  return <AuthContext.Provider value={{ session, checking, error, signIn, signOut }}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth outside AuthProvider');
  return ctx;
}
