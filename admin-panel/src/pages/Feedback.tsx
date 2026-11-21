import { useState } from 'react';

import { ErrorBox, Pager, useData } from '../components/ui';
import { api } from '../lib/api';
import { formatDateTime } from '../lib/format';
import type { FeedbackRow, Page } from '../lib/types';

const TYPES = [
  ['', 'All types'], ['loved_fit', 'Loved fit'], ['disliked', 'Disliked'], ['rating', 'Rating'],
  ['correction', 'Correction'], ['comment', 'Comment'],
] as const;
const PAGE_SIZE = 25;

const PARTS: Record<string, string> = {
  style: 'style', colour: 'colours', fit: 'size & fit', occasion: 'occasion', hairstyle: 'hairstyle',
};

/** One line per feedback: stars, the score parts the user says are off (SFR-034 corrections), their words. */
export function details(data: Record<string, unknown> | null): string {
  if (!data) return '—';
  const parts: string[] = [];
  if (typeof data.rating === 'number') parts.push(`${'★'.repeat(data.rating)}${'☆'.repeat(Math.max(0, 5 - data.rating))}`);
  if (Array.isArray(data.corrections) && data.corrections.length) {
    parts.push(`off: ${data.corrections.map((c) => PARTS[String(c)] ?? String(c)).join(', ')}`);
  }
  const text = data.comment ?? data.text ?? data.correction;
  if (text !== undefined && text !== null && String(text).trim()) parts.push(`“${String(text).trim()}”`);
  if (parts.length) return parts.join(' · ');
  const keys = Object.keys(data);
  return keys.length ? keys.slice(0, 4).join(', ') : '—';
}

export function Feedback() {
  const [type, setType] = useState('');
  const [page, setPage] = useState(1);
  const { data, error, loading, reload } = useData(
    () => api<Page<FeedbackRow>>('/admin/feedback', { query: { feedback_type: type, page, page_size: PAGE_SIZE } }),
    [type, page],
  );

  return (
    <>
      <div className="page-head"><div><h1>Feedback</h1><p>What users tell the AI about its recommendations.</p></div></div>
      <div className="row" style={{ marginBottom: 14 }}>
        <select className="select" value={type} onChange={(e) => { setType(e.target.value); setPage(1); }} aria-label="Feedback type">
          {TYPES.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
      </div>
      {error && <ErrorBox message={error} onRetry={reload} />}
      <div className={`table-wrap${loading && data ? ' loading' : ''}`}>
        <table>
          <thead><tr><th>When</th><th>User</th><th>Product</th><th>Type</th><th>Details</th></tr></thead>
          <tbody>
            {data?.items.map((f) => (
              <tr key={f.id}>
                <td style={{ whiteSpace: 'nowrap' }}>{formatDateTime(f.created_at)}</td>
                <td>{f.profiles?.full_name || f.profiles?.email || 'Deleted user'}<div className="small muted">{f.profiles?.email}</div></td>
                <td>
                  <div className="cell-user" style={{ minWidth: 180 }}>
                    {f.product?.image_url && <img className="thumb" style={{ width: 36, height: 46 }} src={f.product.image_url} alt="" loading="lazy" />}
                    <span>{f.product?.name ?? f.product_id}</span>
                  </div>
                </td>
                <td><span className="badge badge-primary">{TYPES.find(([v]) => v === f.feedback_type)?.[1] ?? f.feedback_type}</span></td>
                <td>{details(f.feedback_data)}</td>
              </tr>
            ))}
            {data && data.items.length === 0 && <tr><td colSpan={5} className="empty">No feedback yet.</td></tr>}
            {!data && loading && <tr><td colSpan={5} className="empty">Loading…</td></tr>}
          </tbody>
        </table>
      </div>
      {data && <Pager page={page} pageSize={PAGE_SIZE} total={data.total} onPage={setPage} />}
    </>
  );
}
