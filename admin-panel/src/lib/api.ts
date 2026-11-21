import { supabase } from './supabase';

export const API_BASE = ((import.meta.env.VITE_API_URL as string | undefined) || 'http://localhost:8000/api/v1').replace(/\/$/, '');

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

/** The backend's error envelope {"error": {code, message}} -> ApiError. */
export function toApiError(status: number, body: unknown): ApiError {
  const err = (body as { error?: { code?: string; message?: string } } | null)?.error;
  if (err?.message) return new ApiError(status, err.code ?? `HTTP_${status}`, err.message);
  if (status === 401) return new ApiError(status, 'UNAUTHORIZED', 'Your session has expired. Please sign in again.');
  if (status === 403) return new ApiError(status, 'FORBIDDEN', 'This area is for SmartFit admins only.');
  return new ApiError(status, `HTTP_${status}`, `Request failed (${status}).`);
}

type Query = Record<string, string | number | boolean | undefined | null>;

export function buildUrl(path: string, query: Query = {}): string {
  const url = new URL(`${API_BASE}${path}`);
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined && value !== null && value !== '') url.searchParams.set(key, String(value));
  }
  return url.toString();
}

export async function api<T>(path: string, opts: { method?: string; body?: unknown; query?: Query } = {}): Promise<T> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (opts.body !== undefined) headers['Content-Type'] = 'application/json';
  let res: Response;
  try {
    res = await fetch(buildUrl(path, opts.query), {
      method: opts.method ?? 'GET',
      headers,
      body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    });
  } catch {
    throw new ApiError(0, 'NETWORK', 'Cannot reach the SmartFit API. Is the backend gateway running?');
  }
  const text = await res.text();
  let body: unknown = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = null;
  }
  if (!res.ok) throw toApiError(res.status, body);
  return body as T;
}
