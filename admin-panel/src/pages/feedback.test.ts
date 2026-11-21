import { describe, expect, it } from 'vitest';

import { details } from './Feedback';

describe('feedback details (SFR-034, SFR-042)', () => {
  it('shows the stars, the corrected parts and the comment together', () => {
    expect(details({ kind: 'look', rating: 2, corrections: ['fit', 'occasion'], comment: 'too formal' }))
      .toBe('★★☆☆☆ · off: size & fit, occasion · “too formal”');
  });

  it('works with only some of them', () => {
    expect(details({ rating: 5 })).toBe('★★★★★');
    expect(details({ comment: '  nice  ' })).toBe('“nice”');
    expect(details({ corrections: ['colour'] })).toBe('off: colours');
  });

  it('falls back to the keys, or a dash', () => {
    expect(details(null)).toBe('—');
    expect(details({ quiz: 'q1', choice: 'a' })).toBe('quiz, choice');
  });
});
