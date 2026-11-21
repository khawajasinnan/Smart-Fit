import { ErrorBox, useData } from './ui';
import { api } from '../lib/api';
import { formatDateTime } from '../lib/format';

/** One model's card from GET /admin/ml (recommendation or scoring service /ml/status). */
export interface LiveModel {
  version?: string;
  trained_at?: string;
  label_source?: string;
  rows?: number;
  real_training_rows?: number | null;
  real_rows?: number | null;
  metrics?: Record<string, number>;
  real_holdout?: Record<string, number> | null;
}

export interface MlService {
  up?: boolean;
  live_model?: LiveModel | null;
  learned_ranking_enabled?: boolean;
  weights?: Record<string, number>;
  auto_retrain_every_hours?: number;
  history?: { at: string; version?: string; status: string; reason?: string }[];
}

export interface MlStatus {
  recommendation?: MlService;
  scoring?: MlService;
}

const pct = (v: number | undefined) => (typeof v === 'number' ? `${(v * 100).toFixed(1)}%` : '—');
const num = (v: number | undefined, digits = 3) => (typeof v === 'number' ? v.toFixed(digits) : '—');

/** The model lines to show for a status (pure: tested in modelPerformance.test.ts). */
export function modelLines(ml: MlStatus): { recommendation: [string, string][]; look: [string, string][] } {
  const r = ml.recommendation?.live_model?.metrics ?? {};
  const s = ml.scoring?.live_model?.metrics ?? {};
  return {
    recommendation: [
      ['Ranking quality (NDCG@10)', `${num(r.ndcg10_lightgbm)} vs ${num(r.ndcg10_rules_only)} rules only`],
      ['Second-opinion accuracy', pct(r.validator_accuracy)],
      ['Second-opinion AUC', num(r.validator_auc)],
      ['Ranker / validator agree', pct(r.ranker_validator_agreement)],
      ['Good-match rate', pct(r.good_match_rate)],
    ],
    look: [
      ['Error (MAE, points)', num(s.valid_mae, 2)],
      ['Fit (R²)', num(s.valid_r2, 3)],
      ['Formula weights', Object.entries(ml.scoring?.weights ?? {}).map(([k, v]) => `${k} ${v.toFixed(2)}`).join(' · ') || '—'],
    ],
  };
}

function ModelBlock({ title, service, lines }: { title: string; service?: MlService; lines: [string, string][] }) {
  const m = service?.live_model;
  const last = service?.history?.[service.history.length - 1];
  if (!service || service.up === false) return <p className="muted">{title}: service not reachable.</p>;
  if (!m) return <p className="muted">{title}: no trained model loaded.</p>;
  const real = m.real_training_rows ?? m.real_rows;
  return (
    <div>
      <h3 style={{ margin: '0 0 6px' }}>{title}</h3>
      <p className="small muted" style={{ margin: '0 0 8px' }}>
        Version {m.version ?? '—'}{m.trained_at ? `, trained ${formatDateTime(m.trained_at)}` : ''} ·{' '}
        {real ? `${real} real user examples` : `trained on ${m.label_source ?? 'generated labels'} (no real feedback yet)`}
      </p>
      <dl className="drawer-grid" style={{ marginTop: 0 }}>
        {lines.map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}
        {last && <div><dt>Last retraining</dt><dd>{last.status}{last.reason ? ` (${last.reason})` : ''}</dd></div>}
      </dl>
    </div>
  );
}

/** SFR-041 "model performance indicators": the live AI models and how well they do on held-out data. */
export function ModelPerformance() {
  const { data, error, reload } = useData(() => api<MlStatus>('/admin/ml'), []);
  if (error) return <ErrorBox message={error} onRetry={reload} />;
  if (!data) return <p className="muted">Loading model status…</p>;
  const lines = modelLines(data);
  return (
    <div className="stack" style={{ gap: 14 }}>
      <ModelBlock title="Outfit ranking (LightGBM + Random Forest)" service={data.recommendation} lines={lines.recommendation} />
      <ModelBlock title="Look score (Random Forest)" service={data.scoring} lines={lines.look} />
    </div>
  );
}
