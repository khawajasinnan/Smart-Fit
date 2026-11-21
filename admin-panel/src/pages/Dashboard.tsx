import { useState } from 'react';

import { DailyBars, LabelledBars } from '../components/BarChart';
import { ModelPerformance } from '../components/ModelPerformance';
import { ErrorBox, UpBadge, useData } from '../components/ui';
import { api } from '../lib/api';
import { compact, formatPkr } from '../lib/format';
import type { Analytics, TopItem } from '../lib/types';

const WINDOWS = [7, 14, 30, 90];
const FEEDBACK_LABELS: Record<string, string> = {
  loved_fit: 'Loved fit', disliked: 'Disliked', rating: 'Rating', correction: 'Correction', comment: 'Comment',
};

function Stat({ label, value, note }: { label: string; value: string | number; note?: string }) {
  return (
    <div className="card stat">
      <span className="label">{label}</span>
      <span className="value">{typeof value === 'number' ? compact(value) : value}</span>
      {note && <span className="note">{note}</span>}
    </div>
  );
}

function TopList({ items, empty }: { items: TopItem[]; empty: string }) {
  if (items.length === 0) return <p className="muted">{empty}</p>;
  return (
    <div>
      {items.map((t, i) => (
        <div className="rank" key={t.id}>
          <span className="n">{i + 1}</span>
          {t.product?.image_url ? <img className="thumb" style={{ width: 36, height: 46 }} src={t.product.image_url} alt="" loading="lazy" /> : null}
          <div style={{ minWidth: 0 }}>
            <div style={{ fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {t.product?.name ?? t.id}
            </div>
            <div className="small muted">{t.product ? `${t.product.retailer} · ${formatPkr(t.product.price)}` : 'Not in the catalog any more'}</div>
          </div>
          <span className="count">{t.count}×</span>
        </div>
      ))}
    </div>
  );
}

export function Dashboard() {
  const [days, setDays] = useState(14);
  const { data, error, loading, reload } = useData(() => api<Analytics>('/admin/analytics', { query: { days } }), [days]);
  const services = data ? Object.entries(data.services) : [];
  const servicesUp = services.filter(([, s]) => s.up).length;

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Dashboard</h1>
          <p>Platform activity, recommendations and feedback.</p>
        </div>
        <div className="tabs" role="tablist" aria-label="Time window">
          {WINDOWS.map((w) => (
            <button key={w} className="tab" role="tab" aria-selected={days === w} onClick={() => setDays(w)}>Last {w} days</button>
          ))}
        </div>
      </div>
      {error && <ErrorBox message={error} onRetry={reload} />}
      {data && (
        <div className={`stack${loading ? ' loading' : ''}`}>
          <div className="grid grid-kpi">
            <Stat label="Users" value={data.users.total} note={`+${data.users.new_7d} this week`} />
            <Stat label="Active (7 days)" value={data.users.active_7d} note="started or continued a chat" />
            <Stat label="Profiles completed" value={data.users.profile_completed}
              note={data.users.total ? `${Math.round((data.users.profile_completed / data.users.total) * 100)}% of users` : undefined} />
            <Stat label="Chat sessions" value={data.sessions.total} note={`${compact(data.sessions.messages_total)} messages`} />
            <Stat label="Recommendations" value={data.recommendations.requests} note={`last ${data.window_days} days`} />
            <Stat label="Feedback" value={data.feedback.total} note={`last ${data.window_days} days`} />
          </div>

          <div className="grid grid-2">
            <section className="card">
              <div className="card-head"><div><h2>Chat sessions per day</h2><p>New AI-stylist sessions</p></div></div>
              <DailyBars data={data.sessions.per_day} label="Sessions" unit="sessions" />
            </section>
            <section className="card">
              <div className="card-head"><div><h2>Recommendation requests per day</h2><p>Times the app asked for outfits</p></div></div>
              <DailyBars data={data.recommendations.per_day} label="Requests" unit="requests" />
            </section>
          </div>

          <div className="grid grid-2">
            <section className="card">
              <div className="card-head"><div><h2>Feedback per day</h2><p>All feedback types</p></div></div>
              <DailyBars data={data.feedback.per_day} label="Feedback" unit="items" />
            </section>
            <section className="card">
              <div className="card-head"><div><h2>Feedback by type</h2><p>Last {data.window_days} days</p></div></div>
              <LabelledBars rows={Object.entries(data.feedback.by_type).map(([k, v]) => ({ label: FEEDBACK_LABELS[k] ?? k, value: v }))} />
            </section>
          </div>

          <div className="grid grid-2">
            <section className="card">
              <div className="card-head"><div><h2>Most recommended</h2><p>Products shown most often</p></div></div>
              <TopList items={data.recommendations.top_products} empty="No recommendations logged in this period yet." />
            </section>
            <section className="card">
              <div className="card-head"><div><h2>Most loved</h2><p>"Love this fit" taps</p></div></div>
              <TopList items={data.feedback.top_loved} empty="No loved fits in this period yet." />
            </section>
          </div>

          <section className="card">
            <div className="card-head"><div><h2>Model performance</h2><p>The live AI models, measured on held-out data</p></div></div>
            <ModelPerformance />
          </section>

          <div className="grid grid-2">
            <section className="card">
              <div className="card-head"><div><h2>Model indicators</h2><p>Recommendation pipeline</p></div></div>
              <dl className="drawer-grid" style={{ marginTop: 0 }}>
                <div><dt>Median response</dt><dd>{data.recommendations.latency_ms_p50 !== null ? `${Math.round(data.recommendations.latency_ms_p50)} ms` : '—'}</dd></div>
                <div><dt>95th percentile</dt><dd>{data.recommendations.latency_ms_p95 !== null ? `${Math.round(data.recommendations.latency_ms_p95)} ms` : '—'}</dd></div>
                <div><dt>Empty results</dt><dd>{data.recommendations.empty_results} of {data.recommendations.requests}</dd></div>
                <div><dt>Catalog size</dt><dd>{data.recommendations.catalog_size} products</dd></div>
                <div><dt>Suspended / banned</dt><dd>{data.users.suspended} / {data.users.banned}</dd></div>
                <div><dt>Deactivated</dt><dd>{data.users.deactivated}</dd></div>
              </dl>
            </section>
            <section className="card">
              <div className="card-head">
                <div><h2>Services</h2><p>{servicesUp} of {services.length} up</p></div>
              </div>
              <div className="stack" style={{ gap: 8 }}>
                {services.map(([name, s]) => (
                  <div className="row" key={name} style={{ justifyContent: 'space-between' }}>
                    <span>{name}</span><UpBadge up={s.up} />
                  </div>
                ))}
              </div>
            </section>
          </div>
        </div>
      )}
      {!data && loading && <p className="muted">Loading analytics…</p>}
    </>
  );
}
