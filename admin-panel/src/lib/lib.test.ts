import { describe, expect, it } from 'vitest';

import { ApiError, buildUrl, toApiError } from './api';
import { compact, initials, splitList, timeAgo } from './format';

describe('api helpers', () => {
  it('maps the backend error envelope', () => {
    const e = toApiError(400, { error: { code: 'NOT_ALLOWED', message: "You can't ban your own admin account." } });
    expect(e).toBeInstanceOf(ApiError);
    expect(e.code).toBe('NOT_ALLOWED');
    expect(e.message).toContain('own admin');
  });

  it('gives plain messages without an envelope', () => {
    expect(toApiError(403, null).message).toContain('admins only');
    expect(toApiError(500, 'oops').code).toBe('HTTP_500');
  });

  it('drops empty query values', () => {
    const url = new URL(buildUrl('/admin/users', { search: '', status: 'banned', page: 2, x: undefined }));
    expect(url.searchParams.get('status')).toBe('banned');
    expect(url.searchParams.get('page')).toBe('2');
    expect(url.searchParams.has('search')).toBe(false);
  });
});

describe('format helpers', () => {
  const now = new Date('2026-10-24T12:00:00Z');
  it('timeAgo', () => {
    expect(timeAgo('2026-10-24T11:59:30Z', now)).toBe('just now');
    expect(timeAgo('2026-10-24T11:00:00Z', now)).toBe('1 h ago');
    expect(timeAgo('2026-10-21T12:00:00Z', now)).toBe('3 days ago');
    expect(timeAgo(null, now)).toBe('—');
  });

  it('compact numbers', () => {
    expect(compact(950)).toBe('950');
    expect(compact(1500)).toBe('1.5k');
    expect(compact(12_000)).toBe('12k');
  });

  it('splitList and initials', () => {
    expect(splitList('S, M ,|L,, ')).toEqual(['S', 'M', 'L']);
    expect(initials('Sara Khan', null)).toBe('SK');
    expect(initials(null, 'ali.raza@x.com')).toBe('AR');
  });
});
