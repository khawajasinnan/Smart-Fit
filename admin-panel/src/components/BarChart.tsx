import { useState } from 'react';

import type { DayCount } from '../lib/types';

const H = 180;
const PAD = { top: 12, right: 8, bottom: 26, left: 32 };

function niceMax(v: number): number {
  if (v <= 4) return 4;
  const pow = 10 ** Math.floor(Math.log10(v));
  const n = v / pow;
  const step = n <= 2 ? 2 : n <= 5 ? 5 : 10;
  return step * pow;
}

function dayLabel(iso: string): string {
  const d = new Date(`${iso}T00:00:00Z`);
  return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', timeZone: 'UTC' });
}

/** One series of daily counts: thin bars rounded at the top, anchored at the
 * baseline, a hover/focus tooltip per bar, and a table view. */
export function DailyBars({ data, label, unit }: { data: DayCount[]; label: string; unit: string }) {
  const [hover, setHover] = useState<number | null>(null);
  const [table, setTable] = useState(false);
  const W = 640;
  const innerW = W - PAD.left - PAD.right;
  const innerH = H - PAD.top - PAD.bottom;
  const max = niceMax(Math.max(0, ...data.map((d) => d.count)));
  const slot = innerW / Math.max(1, data.length);
  const barW = Math.max(4, Math.min(28, slot - 2));
  const y = (v: number) => PAD.top + innerH - (v / max) * innerH;
  const ticks = [0, max / 2, max];
  const labelEvery = Math.ceil(data.length / 7);
  const total = data.reduce((s, d) => s + d.count, 0);

  return (
    <div className="chart">
      <div className="row" style={{ justifyContent: 'space-between', marginBottom: 6 }}>
        <span className="small muted">{total.toLocaleString()} {unit} in {data.length} days</span>
        <button className="btn btn-ghost btn-sm" onClick={() => setTable((t) => !t)} aria-pressed={table}>
          {table ? 'Show chart' : 'Show table'}
        </button>
      </div>
      {table ? (
        <div className="table-wrap" style={{ maxHeight: H + 20, overflowY: 'auto' }}>
          <table>
            <thead><tr><th>Day</th><th>{label}</th></tr></thead>
            <tbody>{data.map((d) => <tr key={d.date}><td>{dayLabel(d.date)}</td><td>{d.count}</td></tr>)}</tbody>
          </table>
        </div>
      ) : (
        <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`${label} per day`} onMouseLeave={() => setHover(null)}>
          {ticks.map((t) => (
            <g key={t}>
              <line className="gridline" x1={PAD.left} x2={W - PAD.right} y1={y(t)} y2={y(t)} />
              <text className="axis-label" x={PAD.left - 6} y={y(t) + 4} textAnchor="end">{Math.round(t)}</text>
            </g>
          ))}
          {data.map((d, i) => {
            const x = PAD.left + i * slot + (slot - barW) / 2;
            const top = y(d.count);
            const h = PAD.top + innerH - top;
            const r = Math.min(4, barW / 2, h);
            const path = h <= 0 ? '' :
              `M${x},${PAD.top + innerH} V${top + r} Q${x},${top} ${x + r},${top} H${x + barW - r} Q${x + barW},${top} ${x + barW},${top + r} V${PAD.top + innerH} Z`;
            return (
              <g key={d.date}>
                {path && <path className={`bar${hover !== null && hover !== i ? ' dim' : ''}`} d={path} />}
                <rect x={PAD.left + i * slot} y={PAD.top} width={slot} height={innerH} fill="transparent"
                  tabIndex={0} aria-label={`${dayLabel(d.date)}: ${d.count} ${unit}`}
                  onMouseEnter={() => setHover(i)} onFocus={() => setHover(i)} onBlur={() => setHover(null)} />
                {i % labelEvery === 0 && (
                  <text className="axis-label" x={PAD.left + i * slot + slot / 2} y={H - 8} textAnchor="middle">{dayLabel(d.date)}</text>
                )}
              </g>
            );
          })}
        </svg>
      )}
      {!table && hover !== null && data[hover] && (
        <div className="tooltip" style={{
          left: `${((PAD.left + hover * slot + slot / 2) / W) * 100}%`,
          top: `${(y(data[hover].count) / H) * 100}%`,
        }}>
          <strong>{data[hover].count.toLocaleString()}</strong>{unit} · {dayLabel(data[hover].date)}
        </div>
      )}
    </div>
  );
}

/** Horizontal bars for a few labelled values (feedback by type). Value labels
 * are always visible, so color is never the only carrier. */
export function LabelledBars({ rows }: { rows: { label: string; value: number }[] }) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  if (rows.length === 0) return <p className="muted">No data in this period.</p>;
  return (
    <div className="stack" style={{ gap: 10 }}>
      {rows.map((r) => (
        <div className="hbar" key={r.label}>
          <span>{r.label}</span>
          <div className="hbar-track"><div className="hbar-fill" style={{ width: `${(r.value / max) * 100}%` }} /></div>
          <strong>{r.value}</strong>
        </div>
      ))}
    </div>
  );
}
