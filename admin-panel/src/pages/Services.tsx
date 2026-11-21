import { ErrorBox, UpBadge, useData } from '../components/ui';
import { api } from '../lib/api';
import type { ServiceHealth } from '../lib/types';

const ABOUT: Record<string, string> = {
  gateway: 'Public API, authentication and admin checks',
  'cv-analysis': 'Body shape, size and skin tone from photos',
  recommendation: 'FashionCLIP outfit ranking',
  scraper: 'Retailer catalog collection',
  'chat-orchestrator': 'AI stylist chat (Gemini)',
  tryon: 'IDM-VTON virtual try-on (GPU)',
  hairstyle: 'Hairstyle suggestions',
  scoring: 'Look score and styling hints',
};

export function Services() {
  const { data, error, loading, reload } = useData(() => api<Record<string, ServiceHealth>>('/admin/services'), []);
  return (
    <>
      <div className="page-head">
        <div><h1>Services</h1><p>Health of every backend service and the AI pipeline.</p></div>
        <button className="btn" onClick={reload} disabled={loading}>{loading ? 'Checking…' : 'Check again'}</button>
      </div>
      {error && <ErrorBox message={error} onRetry={reload} />}
      <div className={`grid grid-2${loading && data ? ' loading' : ''}`}>
        {data && Object.entries(data).map(([name, s]) => (
          <section className="card" key={name}>
            <div className="card-head" style={{ marginBottom: 4 }}>
              <h2>{name}</h2><UpBadge up={s.up} />
            </div>
            <p className="muted" style={{ margin: 0 }}>{ABOUT[name] ?? ''}</p>
            {typeof s.implemented === 'boolean' && !s.implemented && <p className="small muted">Not built yet (returns "coming soon").</p>}
          </section>
        ))}
      </div>
    </>
  );
}
