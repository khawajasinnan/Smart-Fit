export type UserStatus = 'active' | 'suspended' | 'banned' | 'deactivated' | 'incomplete';

export interface AdminUser {
  id: string;
  email: string | null;
  full_name: string | null;
  username: string | null;
  gender: string | null;
  avatar_url: string | null;
  photo_url: string | null;
  profile_completed: boolean | null;
  is_banned: boolean | null;
  ban_reason: string | null;
  suspended_until: string | null;
  suspension_reason: string | null;
  deactivated_at: string | null;
  created_at: string;
  status: UserStatus;
}

export interface Page<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
}

export interface UserDetail {
  profile: AdminUser & Record<string, unknown>;
  counts: { chat_sessions: number; saved_items: number; feedback: number };
}

export interface Product {
  product_id: string;
  retailer: 'outfitters' | 'breakout';
  name: string;
  product_url: string;
  image_url: string;
  price: number;
  sizes: string[];
  all_sizes: string[];
  category: string;
  tryon_category: 'upper' | 'lower' | 'dress';
  gender: 'men' | 'women' | 'unisex';
  colors: string[];
  has_size_chart: boolean;
  source: string;
  scraped_at: string;
}

export interface ProductPage extends Page<Product> {
  by_retailer: Record<string, number>;
}

export interface ScraperRetailer {
  retailer: string;
  mode: 'feed' | 'manual_csv';
  enabled: boolean;
  max_products: number;
  last_run_at: string | null;
  last_run_status: string | null;
  last_run_summary: Record<string, unknown> | null;
  running: boolean;
}

export interface DayCount {
  date: string;
  count: number;
}

export interface ProductRef {
  product_id: string;
  name: string;
  image_url: string;
  retailer: string;
  price: number;
}

export interface TopItem {
  id: string;
  count: number;
  product: ProductRef | null;
}

export interface ServiceHealth {
  up: boolean;
  [key: string]: unknown;
}

export interface Analytics {
  window_days: number;
  users: {
    total: number; new_7d: number; new_30d: number; profile_completed: number; active_7d: number;
    banned: number; suspended: number; deactivated: number;
  };
  sessions: { total: number; messages_total: number; per_day: DayCount[] };
  recommendations: {
    requests: number; per_day: DayCount[]; empty_results: number; latency_ms_p50: number | null;
    latency_ms_p95: number | null; top_products: TopItem[]; catalog_size: number;
  };
  feedback: { total: number; by_type: Record<string, number>; top_loved: TopItem[]; per_day: DayCount[] };
  services: Record<string, ServiceHealth>;
}

export interface FeedbackRow {
  id: string;
  product_id: string;
  feedback_type: string;
  feedback_data: Record<string, unknown> | null;
  created_at: string;
  profiles: { email: string | null; full_name: string | null } | null;
  product: ProductRef | null;
}

export interface FlaggedMessage {
  id: string;
  content: string;
  metadata: { moderation?: { flagged?: boolean; reason?: string; categories?: string[]; review_status?: string } } | null;
  reviewed_at: string | null;
  created_at: string;
  chat_sessions: { title: string; user_id: string; profiles: { email: string | null; full_name: string | null } | null } | null;
}
