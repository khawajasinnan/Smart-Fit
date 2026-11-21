import { describe, expect, it } from 'vitest';

import { modelLines } from './ModelPerformance';

describe('model performance (SFR-041)', () => {
  it('shows the live models measured quality', () => {
    const lines = modelLines({
      recommendation: { live_model: { metrics: { ndcg10_lightgbm: 0.9931, ndcg10_rules_only: 0.945, validator_accuracy: 0.9664 } } },
      scoring: { live_model: { metrics: { valid_mae: 2.72, valid_r2: 0.9114 } }, weights: { style: 0.25, fit: 0.25 } },
    });
    expect(lines.recommendation[0][1]).toBe('0.993 vs 0.945 rules only');
    expect(lines.recommendation[1][1]).toBe('96.6%');
    expect(lines.look[0][1]).toBe('2.72');
    expect(lines.look[2][1]).toBe('style 0.25 · fit 0.25');
  });

  it('shows dashes when a number is missing', () => {
    const lines = modelLines({});
    expect(lines.recommendation.every(([, v]) => v.includes('—'))).toBe(true);
    expect(lines.look[2][1]).toBe('—');
  });
});
