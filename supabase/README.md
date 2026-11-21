# supabase/

Database schema for SmartFit, as ordered migrations.

| File | What it does |
|---|---|
| `migrations/20261018000100_baseline.sql` | Original `supabase_setup.sql` — all tables, RLS, buckets, triggers. Now re-runnable. |
| `migrations/20261018000200_user_feedback.sql` | Creates the `user_feedback` table the app's **Love Fit** feature writes to (it was missing). |
| `migrations/20261018000300_security_hardening.sql` | Stops users lifting their own ban, pins `search_path` on functions, stops users editing their own chat messages. |
| `seed.sql` | Local-only seed (empty by default). |
| `config.toml` | Local Supabase CLI stack config. |

## Applying to the hosted project (do this once, one teammate only)

The hosted database is shared, so only **one person** applies these.

**Option A — SQL editor (simplest):** Dashboard → SQL Editor → New query → paste and run each file **in order** (0100, then 0200, then 0300). The baseline is safe to re-run on the existing database.

**Option B — Supabase CLI:**

```bash
npx supabase link --project-ref <your-project-ref>
# Tell the CLI the baseline is already applied (the tables exist):
npx supabase migration repair --status applied 20261018000100
npx supabase db push
```

## Local stack (optional, needs Docker)

```bash
npx supabase start      # boots Postgres/Auth/Storage locally
npx supabase db reset   # applies all migrations + seed.sql
```

## Rules

- Every schema change is a **new** timestamped file in `migrations/` — never edit an applied migration.
- Every table ships with RLS enabled and explicit policies.
