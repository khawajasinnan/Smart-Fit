import { useState } from 'react';

import { IconCheck, IconFlag } from '../components/Icons';
import { ErrorBox, Pager, useAction, useData } from '../components/ui';
import { api } from '../lib/api';
import { formatDateTime } from '../lib/format';
import type { FlaggedMessage, Page } from '../lib/types';

const PAGE_SIZE = 25;

export function Moderation() {
  const [status, setStatus] = useState<'pending' | 'reviewed' | 'all'>('pending');
  const [page, setPage] = useState(1);
  const { data, error, loading, reload } = useData(
    () => api<Page<FlaggedMessage>>('/admin/moderation', { query: { status, page, page_size: PAGE_SIZE } }),
    [status, page],
  );
  const { busy, run } = useAction();

  return (
    <>
      <div className="page-head">
        <div><h1>Moderation</h1><p>Chat messages flagged by the app's safety filter.</p></div>
        <div className="tabs" role="tablist" aria-label="Review status">
          {(['pending', 'reviewed', 'all'] as const).map((s) => (
            <button key={s} className="tab" role="tab" aria-selected={status === s} onClick={() => { setStatus(s); setPage(1); }}>
              {s === 'pending' ? 'To review' : s === 'reviewed' ? 'Reviewed' : 'All'}
            </button>
          ))}
        </div>
      </div>
      {error && <ErrorBox message={error} onRetry={reload} />}
      <div className={`stack${loading && data ? ' loading' : ''}`}>
        {data?.items.map((m) => {
          const mod = m.metadata?.moderation;
          const who = m.chat_sessions?.profiles;
          return (
            <section className="card" key={m.id}>
              <div className="card-head">
                <div>
                  <div style={{ fontWeight: 600 }}>{who?.full_name || who?.email || 'Deleted user'}</div>
                  <p>{who?.email} · {m.chat_sessions?.title ?? 'Chat'} · {formatDateTime(m.created_at)}</p>
                </div>
                {m.reviewed_at
                  ? <span className="badge badge-good"><IconCheck />Reviewed</span>
                  : <button className="btn btn-sm btn-primary" disabled={busy}
                      onClick={() => run(() => api(`/admin/moderation/${m.id}/reviewed`, { method: 'POST' }), 'Marked as reviewed.').then(reload)}>
                      Mark reviewed
                    </button>}
              </div>
              <p style={{ margin: 0, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{m.content}</p>
              {(mod?.reason || mod?.categories?.length) && (
                <p className="small" style={{ margin: '10px 0 0' }}>
                  <span className="badge badge-warn"><IconFlag />{mod?.reason ?? mod?.categories?.join(', ')}</span>
                </p>
              )}
            </section>
          );
        })}
        {data && data.items.length === 0 && (
          <div className="card empty">{status === 'pending' ? 'Nothing waiting for review.' : 'No flagged messages.'}</div>
        )}
      </div>
      {data && data.total > 0 && <Pager page={page} pageSize={PAGE_SIZE} total={data.total} onPage={setPage} />}
    </>
  );
}
