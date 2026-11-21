import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react';

import { ApiError } from '../lib/api';
import type { UserStatus } from '../lib/types';
import { IconAlert, IconBan, IconCheck, IconClock, IconPause } from './Icons';

// ── data loading ────────────────────────────────────────────────────────────

/** Loads with `load`, reloads when `deps` change; keeps the previous data while
 * reloading (no layout jump). */
export function useData<T>(load: () => Promise<T>, deps: unknown[]) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [tick, setTick] = useState(0);
  const loadRef = useRef(load);
  loadRef.current = load;

  useEffect(() => {
    let alive = true;
    setLoading(true);
    loadRef.current()
      .then((d) => { if (alive) { setData(d); setError(null); } })
      .catch((e) => { if (alive) setError(e instanceof ApiError ? e.message : 'Something went wrong.'); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [...deps, tick]); // `load` is read through a ref so callers may pass an inline function

  const reload = useCallback(() => setTick((t) => t + 1), []);
  return { data, error, loading, reload, setData };
}

export function useDebounced<T>(value: T, ms = 300): T {
  const [v, setV] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setV(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return v;
}

// ── toasts ──────────────────────────────────────────────────────────────────

type Toast = { text: string; error?: boolean } | null;
const ToastContext = createContext<(text: string, error?: boolean) => void>(() => undefined);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<Toast>(null);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3500);
    return () => clearTimeout(t);
  }, [toast]);
  const show = useCallback((text: string, error = false) => setToast({ text, error }), []);
  return (
    <ToastContext.Provider value={show}>
      {children}
      {toast && <div className={`toast${toast.error ? ' error' : ''}`} role="status">{toast.text}</div>}
    </ToastContext.Provider>
  );
}

export const useToast = () => useContext(ToastContext);

/** Runs an action, toasts success or the API's error message. */
export function useAction() {
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const run = useCallback(async (fn: () => Promise<unknown>, success: string) => {
    setBusy(true);
    try {
      await fn();
      toast(success);
      return true;
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Something went wrong.', true);
      return false;
    } finally {
      setBusy(false);
    }
  }, [toast]);
  return { busy, run };
}

// ── modal ───────────────────────────────────────────────────────────────────

export function Modal({ title, onClose, children, footer, wide }: {
  title: string; onClose: () => void; children: ReactNode; footer?: ReactNode; wide?: boolean;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div className="overlay" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className={`modal${wide ? ' wide' : ''}`} role="dialog" aria-modal="true" aria-label={title}>
        <div className="card-head" style={{ marginBottom: 8 }}>
          <h2>{title}</h2>
          <button className="btn btn-ghost btn-sm" onClick={onClose} aria-label="Close">✕</button>
        </div>
        {children}
        {footer && <div className="modal-foot">{footer}</div>}
      </div>
    </div>
  );
}

// ── small pieces ────────────────────────────────────────────────────────────

const STATUS: Record<UserStatus, { cls: string; label: string; icon: ReactNode }> = {
  active: { cls: 'badge-good', label: 'Active', icon: <IconCheck /> },
  suspended: { cls: 'badge-warn', label: 'Suspended', icon: <IconClock /> },
  banned: { cls: 'badge-critical', label: 'Banned', icon: <IconBan /> },
  deactivated: { cls: 'badge-neutral', label: 'Deactivated', icon: <IconPause /> },
  incomplete: { cls: 'badge-neutral', label: 'Profile incomplete', icon: <IconAlert /> },
};

export function StatusBadge({ status }: { status: UserStatus }) {
  const s = STATUS[status];
  return <span className={`badge ${s.cls}`}>{s.icon}{s.label}</span>;
}

export function UpBadge({ up }: { up: boolean }) {
  return up
    ? <span className="badge badge-good"><IconCheck />Up</span>
    : <span className="badge badge-critical"><IconAlert />Down</span>;
}

export function Pager({ page, pageSize, total, onPage }: { page: number; pageSize: number; total: number; onPage: (p: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const from = total === 0 ? 0 : (page - 1) * pageSize + 1;
  const to = Math.min(total, page * pageSize);
  return (
    <div className="pager">
      <span className="muted">{total === 0 ? 'Nothing to show' : `${from}–${to} of ${total}`}</span>
      <div className="row">
        <button className="btn btn-sm" disabled={page <= 1} onClick={() => onPage(page - 1)}>Previous</button>
        <span className="small muted">Page {page} of {pages}</span>
        <button className="btn btn-sm" disabled={page >= pages} onClick={() => onPage(page + 1)}>Next</button>
      </div>
    </div>
  );
}

export function ErrorBox({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="alert row" role="alert">
      <span>{message}</span>
      {onRetry && <button className="btn btn-sm" onClick={onRetry}>Try again</button>}
    </div>
  );
}

export function Switch({ checked, onChange, label, disabled }: { checked: boolean; onChange: (v: boolean) => void; label: string; disabled?: boolean }) {
  return (
    <button type="button" role="switch" aria-checked={checked} aria-label={label} className="switch"
      disabled={disabled} onClick={() => onChange(!checked)} />
  );
}
