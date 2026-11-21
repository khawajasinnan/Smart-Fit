import { useEffect, useState } from 'react';

import { ImportCsvDialog } from '../components/CatalogDialogs';
import { IconAlert, IconCheck, IconClock } from '../components/Icons';
import { ErrorBox, Switch, useAction, useData } from '../components/ui';
import { api } from '../lib/api';
import { formatDateTime } from '../lib/format';
import type { ScraperRetailer } from '../lib/types';

function RunStatus({ r }: { r: ScraperRetailer }) {
  if (r.running || r.last_run_status === 'running') return <span className="badge badge-primary"><IconClock />Running…</span>;
  if (r.last_run_status === 'ok') return <span className="badge badge-good"><IconCheck />Last run OK</span>;
  if (r.last_run_status === 'failed') return <span className="badge badge-critical"><IconAlert />Last run failed</span>;
  return <span className="badge badge-neutral">Never run</span>;
}

function summaryText(s: Record<string, unknown> | null): string | null {
  if (!s) return null;
  const kept = s.kept as Record<string, number> | undefined;
  const errors = s.errors as Record<string, string> | undefined;
  const parts: string[] = [];
  if (kept) parts.push(Object.entries(kept).map(([k, v]) => `${v} products kept (${k})`).join(', '));
  if (errors && Object.keys(errors).length) parts.push(Object.values(errors).join('; '));
  if (typeof s.error === 'string') parts.push(s.error);
  return parts.filter(Boolean).join(' · ') || null;
}

function RetailerCard({ r, onChanged }: { r: ScraperRetailer; onChanged: () => void }) {
  const [max, setMax] = useState(String(r.max_products));
  const [importing, setImporting] = useState(false);
  const { busy, run } = useAction();
  useEffect(() => setMax(String(r.max_products)), [r.max_products]);
  const patch = (body: object, msg: string) => run(() => api(`/admin/scraper/${r.retailer}`, { method: 'PATCH', body }), msg).then(onChanged);
  const summary = summaryText(r.last_run_summary);

  return (
    <section className="card stack">
      <div className="card-head" style={{ marginBottom: 0 }}>
        <div>
          <h2 style={{ textTransform: 'capitalize' }}>{r.retailer}</h2>
          <p>{r.mode === 'feed' ? 'Official product feed (robots.txt respected, 2 s between requests)' : 'Hand-collected CSV import'}</p>
        </div>
        <div className="row">
          <span className="small muted">{r.enabled ? 'Enabled' : 'Disabled'}</span>
          <Switch checked={r.enabled} label={`Enable ${r.retailer}`} disabled={busy}
            onChange={(v) => patch({ enabled: v }, v ? 'Retailer enabled.' : 'Retailer disabled.')} />
        </div>
      </div>
      <div className="row"><RunStatus r={r} /><span className="small muted">{r.last_run_at ? formatDateTime(r.last_run_at) : ''}</span></div>
      {summary && <p className="small muted" style={{ margin: 0 }}>{summary}</p>}
      {r.mode === 'feed' ? (
        <div className="row" style={{ alignItems: 'flex-end' }}>
          <div className="field">
            <label htmlFor={`max-${r.retailer}`}>Products to keep</label>
            <input id={`max-${r.retailer}`} className="input" type="number" min={1} max={2000} value={max} style={{ width: 140 }}
              onChange={(e) => setMax(e.target.value)} />
          </div>
          <button className="btn" disabled={busy || Number(max) === r.max_products || !(Number(max) >= 1)}
            onClick={() => patch({ max_products: Number(max) }, 'Limit saved.')}>Save</button>
          <span className="spacer" />
          <button className="btn btn-primary" disabled={busy || !r.enabled || r.running}
            onClick={() => run(() => api(`/admin/scraper/${r.retailer}/run`, { method: 'POST' }), 'Refresh started. It takes a few minutes.').then(onChanged)}>
            Run now
          </button>
        </div>
      ) : (
        <div className="row">
          <button className="btn btn-primary" onClick={() => setImporting(true)}>Import CSV</button>
        </div>
      )}
      {importing && <ImportCsvDialog onClose={() => setImporting(false)} onDone={onChanged} />}
    </section>
  );
}

export function Scraper() {
  const { data, error, reload } = useData(() => api<{ retailers: ScraperRetailer[] }>('/admin/scraper'), []);
  const anyRunning = data?.retailers.some((r) => r.running || r.last_run_status === 'running');

  useEffect(() => { // poll while a refresh runs
    if (!anyRunning) return;
    const t = setInterval(reload, 5000);
    return () => clearInterval(t);
  }, [anyRunning, reload]);

  return (
    <>
      <div className="page-head"><div><h1>Scraping</h1><p>Supported retailers and how their catalog is collected.</p></div></div>
      {error && <ErrorBox message={error} onRetry={reload} />}
      <div className="grid grid-2">
        {data?.retailers.map((r) => <RetailerCard key={r.retailer} r={r} onChanged={reload} />)}
      </div>
    </>
  );
}
