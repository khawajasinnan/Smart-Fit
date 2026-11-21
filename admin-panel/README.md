# admin-panel/

The separate web admin panel required by SRDS §2.3.9 (SFR-039 – SFR-042). It is built with React 18, Vite 5 and TypeScript, with exact version pins in `package.json`.

| Page | Requirement | What it does |
|---|---|---|
| Dashboard | SFR-041 | Users, activity, recommendation and feedback trends, most recommended/loved products, model indicators, service health |
| Users | SFR-039 | Search, filter by status, view details, suspend/lift, ban/unban, permanently delete (typed confirmation) |
| Catalog | SFR-040 | Browse/search products, add, edit, remove, import the Breakout CSV |
| Scraping | SFR-040 | Enable/disable retailers, product limits, run the Outfitters feed refresh, last-run status |
| Feedback | SFR-042 | All user feedback with product and user |
| Moderation | (SF-UC-10) | Chat messages flagged by the app's safety filter; mark reviewed |
| Services | SF-UC-11 | Health of every backend service |

## How it is secured

- The browser holds only the admin's normal Supabase session and the **public** anon key. The service key never leaves the backend.
- Every call goes to the gateway's `/api/v1/admin/*` routes. The gateway checks the admin role (the `ADMIN_EMAILS` list or the `app_metadata.role` claim) on each request.
- A non-admin account is signed out straight after sign-in.

## Run it locally

1. **Apply the migration.** Apply `supabase/migrations/20261024000100_account_admin.sql` once. It adds the account-deactivation column, scraper settings and recommendation analytics.
2. **Start the backend.** Run at least the gateway and the scraper service; the dashboard also probes the other services.
3. **Start the panel:**
   ```
   cd admin-panel
   cp .env.example .env.local   # already created on this PC
   npm install
   npm run dev                  # http://localhost:5173
   ```
4. **Sign in** with the admin account (the email in `ADMIN_EMAILS` in `.env`).

Checks: `npm run typecheck`, `npm test`, `npm run build`.
