# SmartFit — Development Rules & Guardrails

What to use, what to avoid, and how errors get handled — for human contributors and for whichever AI coding tool (e.g. Antigravity) is generating code against these docs.

## 1. Purpose

Every rule below exists to prevent a rebuild later. If a rule seems to be slowing something down, that's usually the point — check `memory.md`'s decision log before overriding one.

## 2. Approved Stack & Libraries

### 2.1 Flutter / Dart

| Package | Purpose | Status |
|---|---|---|
| `flutter_riverpod` | State management | Required — the only state management approach in this codebase |
| `go_router` | Navigation | Required |
| `dio` | HTTP client | Required — the only HTTP client |
| `supabase_flutter` | Auth, DB, storage, realtime | Required |
| `freezed` + `json_serializable` | Immutable models, JSON mapping | Recommended for all domain entities and DTOs |
| `flutter_secure_storage` | Token/secret storage | Required for anything sensitive |
| `image_picker` | Camera/gallery access | SFR-009, SFR-016 |
| `permission_handler` | Runtime permissions | Camera, gallery, notifications |
| `cached_network_image` | Remote image caching | Product photos, avatars |
| `flutter_svg` | Vector icon rendering | |
| `shimmer` | Skeleton loading states | Ties to SFR-021's "processing indicator" requirement |
| `flutter_animate` | Entrance/micro-interaction animations | See `design.md` §5 |
| `lottie` or `rive` | Richer vector animation (celebration moments) | Pick one, don't import both |
| `confetti` | Look-score celebration micro-animation | Optional, small footprint |
| `google_sign_in`, `flutter_facebook_auth` | OAuth, paired with Supabase Auth | Only if Facebook OAuth is confirmed in scope |
| `firebase_messaging` | Push notifications | Per SRDS §3.3.3 |

Resolve versions with `flutter pub add <package>` rather than hand-pinning numbers in this file — pinned versions here would just go stale.

### 2.2 Explicitly Avoid

- **Provider, GetX, Bloc** — don't mix state management paradigms. Riverpod only.
- **`http` package directly** — Dio is the only HTTP client; a second one means two error-handling paths to maintain.
- **`SharedPreferences` for tokens or secrets** — insecure. Use `flutter_secure_storage`.
- **Business logic inside `setState`/widgets** — widgets stay declarative; logic lives in providers/notifiers.
- **Hardcoded API keys or Supabase keys in source** — always `--dart-define` or `.env`, never committed.
- **Any package requiring native (Android/iOS) code changes** without flagging it first — added build complexity a 2-person team should sign off on deliberately, not inherit by accident.
- **Abandoned packages** (no update in 18+ months) without a documented reason in `memory.md`.

### 2.3 Backend (Python)

Approved: FastAPI, Pydantic v2, Uvicorn, MediaPipe, OpenCV, scikit-learn, BeautifulSoup + `httpx`/`requests`, `supabase-py`.

Avoid:
- Mixing an ORM (SQLAlchemy) with the raw `supabase-py` client in the same service — pick one per service and stay consistent.
- Running CV/diffusion inference inline in the request-handling thread — use background tasks or a queue so a slow inference call doesn't hold an HTTP connection open (this is also how the 20s try-on / 10s CV targets in `prd.md` §6 stay honest under load).
- Scraper logic embedded directly in `recommendation_service` — keep it in `scraper_service` so a retailer site change doesn't require redeploying the whole recommendation pipeline (also what SRDS §4.3.7 calls for).

## 3. Error Handling

### 3.1 Frontend

- Every async provider returns `AsyncValue<T>`; every screen consuming it handles all three states — loading, error, data — no silent fallthrough.
- Domain-level failures use a small sealed `Failure` hierarchy (`NetworkFailure`, `ValidationFailure`, `SizeUnavailableFailure`, `TryOnGenerationFailure`, etc.) rather than raw exceptions leaking into the UI.
- Error states get real copy, not raw exceptions or status codes — see `design.md` for tone (SRDS §4.3.2 requires "plain, human-readable language with actionable guidance").
- Four required UI states everywhere data loads: loading (skeleton, not spinner-only where content shape is known), empty, error-with-retry, success.

### 3.2 Backend

- Every error response follows one envelope: `{"error": {"code": "...", "message": "...", "details": {...}}}`.
- Never return a raw stack trace or DB error string to the client.
- Structured logs only — no PII (photos, emails, measurements) in log output.

### 3.3 SRDS-Specific Handling

- **SFR-021** — CV analysis must show a processing indicator; treat >10s as a timeout with a retry path, not an infinite spinner.
- **SFR-025 / SFR-027** — size-unavailable and try-on-failure are first-class UI states with their own copy and next action, not a generic error screen.
- **NFR §4.3.1 (graceful degradation)** — if the hairstyle service is down, outfit recommendations and try-on must still work; don't let one AI service become a single point of failure for the whole session.

## 4. AI Coding Agent Boundaries

Rules for whichever tool is generating code from these six files:

- Every feature built must trace to an SFR or SF-UC ID in `prd.md`. If asked for something that isn't in the SRDS, flag it back rather than quietly building it — scope creep on an academic deadline is expensive.
- Don't invent screens or flows not described in `design.md`'s component specs — ask, or build the closest documented pattern and flag the gap.
- Follow the folder structure in `architecture.md` §4.1 — restructuring it mid-project isn't a unilateral call.
- Use the exact tokens in `design.md` (colors, type scale, radii, spacing) — no ad hoc hex codes inside widgets.
- Don't fabricate API response data that isn't clearly labeled as a mock/fixture during early development.
- Keep the `domain/` layer free of Flutter, Supabase, and Dio imports — that boundary is what makes the clean-architecture split real rather than nominal.
- Update `memory.md` at the end of each work session: what got finished, what's mid-flight, what broke.

## 5. Security Rules (non-negotiable — SRDS §4.2)

- Passwords: bcrypt (or equivalent modern salted hash) — never plain text, never logged.
- Sessions: JWT with refresh tokens, sensible expiry.
- Transport: TLS 1.2+ everywhere — no unencrypted HTTP endpoint, ever.
- Storage: user photos and generated images live in **private** buckets, accessed only via signed, time-limited URLs.
- OAuth: standard OAuth 2.0 flow with state-parameter CSRF protection.
- Access control: RBAC enforced at the API layer — a normal user token must not reach `/admin/*`, full stop.
- Injection/XSS/CSRF: parameterized queries only, sanitized inputs, standard FastAPI/Supabase protections enabled.
- Rate limiting: required on `/auth/*` and every AI inference endpoint.
- Age gate: DOB collected and validated (15+) at registration — reject, don't silently allow, underage signups.
- File uploads: type and size validated server-side before processing, regardless of what client-side validation already did.
- Supabase RLS: **on by default for every table.** No table ships without a policy — "add RLS later" is how photo buckets end up public.

## 6. Testing Minimums (SRDS §4.3.6)

- Unit tests for domain logic (use cases, validators, scoring/ranking logic).
- Widget tests for the screens with real business logic on them (onboarding gate, size-compatibility check, feedback form) — not required for pure layout screens.
- Integration tests for backend endpoints, especially auth and the size-compatibility check.
- No AI model change ships to a demo build without a quick benchmark check against known-good inputs first.

## 7. Known Risks & Mitigations

| Risk | Why it matters | Mitigation |
|---|---|---|
| Diffusion try-on is research-grade work | Could eat the entire October timeline on its own | Start with a simpler compositing overlay as a working fallback; upgrade to full diffusion once the rest of the flow is solid (see `prd.md` open question #3) |
| Live scraping is fragile | A retailer site redesign breaks recommendations with no warning | Keep a cached/seeded product dataset as a fallback source; scraper failures should degrade to cached data, not a broken recommendation screen |
| Facebook OAuth scope is ambiguous | Building it unnecessarily costs time; skipping it if required costs a requirement | Decide before Phase 1 — see `prd.md` open question #1 |
| Admin panel is a second app | Easy to underestimate as "just a dashboard" | Scope it explicitly and late — see `phases.md` Phase 10 |
