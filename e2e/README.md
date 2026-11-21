# SmartFit end-to-end tests (Playwright)

These tests drive the real app the way a shopper does: the Flutter **web build**, the local
backend, the hosted Supabase, Gemini and the Modal GPU. They cover the SRDS functional
requirements from sign-up to the admin panel (SRDS 4.3.6). The per-SFR results are in
`docs/srds-traceability.md`.

## What runs

| File | What it checks |
|---|---|
| `00-session.setup.ts` | Saves a signed-in session per test shopper (skipped until onboarding ran) |
| `01-landing-auth` | Landing page; sign-up checks (SFR-001/003); wrong password (004); reset code (005) |
| `02-onboarding` | The mandatory profile and its gate (SFR-006, 009–013) |
| `03-navigation` | Every bottom tab opens |
| `04-chat` | Zayn: app help, products, photo analysis, history (SFR-014–018, 019–023, 038) |
| `05-tryon-score-hair` | A product from her recommendations (Home) → GPU try-on → save → look score + feedback → matching hairstyle → saved with it (SFR-023–035) |
| `06-wardrobe` | The saved outfit with its try-on and hairstyle; sort; store link; remove + undo (SFR-035–037) |
| `07-settings-account` | Profile view/edit, notifications, privacy screens, log out (SFR-004, 007) |
| `08-account-man` | A man's onboarding, deactivate → reactivate, then **real deletion** (SFR-006, 008) |
| `09-colours-culture` | Home's "Your <culture> style" looks + store search; the skin tone analyzer saving shade and undertone |
| `10-admin` | Admin panel: dashboard, users (search, view, suspend + lift, delete guard), feedback, catalog, scraping (SFR-039–042) |

The tests serve the web build themselves on **port 5055** (not 5000, which `flutter run` uses for Google
sign-in; a debug app running there must not be picked up).

The files run in order, one at a time: later files use the woman's session and the outfit she
saved in `05`. Each full run uses **one GPU try-on and one GPU hairstyle run**.

Screenshots of the AI results (try-on, look score, hairstyle, wardrobe card) are saved in
`e2e/screens/` (kept between runs, gitignored) and attached to the HTML report, so a person can judge the quality,
not just that the screens appeared.

**Gemini limit:** on the free tier the project gets **20 Gemini requests a day** for
`gemini-2.5-flash` (it resets at midnight Pacific time, 13:00 in Pakistan). `04-chat` uses about
6-10 of them; when they run out Zayn answers "a bit busy" and `04-chat` fails. Only `04-chat`
talks to Zayn; the other files don't need Gemini.

## Before a run

1. Backend running: `backend\run_local.bat` (all 8 services).
2. Web build with the test switch on (it turns on Flutter's accessibility tree, which the tests
   read). In `frontend/`:

   ```
   flutter clean
   flutter pub get
   flutter build web --release --dart-define-from-file=env/dev.json --dart-define=E2E=true
   ```

   Always `flutter clean` first if `flutter test` ran since the last build: mixing the two left
   the build without its fonts and asset list once (the global setup now stops with this message).
3. Test shoppers, made on the hosted Supabase (pre-verified; their logins go only to the
   gitignored `e2e/.env.local`). In `backend/`:

   ```
   .venv-cpu\Scripts\python.exe scripts\e2e_users.py create
   ```

   `02-onboarding` needs a **new** woman each run (it completes her profile), so run `delete`
   then `create` between full runs.
4. Optional, for `10-admin`: add an admin login to `e2e/.env.local` yourself:

   ```
   E2E_ADMIN_EMAIL=...
   E2E_ADMIN_PASSWORD=...
   ```

   Without it those tests are skipped. With it, the admin panel's dev server is started too.
5. Test photos: `datasets/tryon-test-kit/` (not in git). `people/women-face.jpg` must pass the
   hairstyle face check (sharp, straight on, big enough); `people/women-front/00006_00.jpg` and
   `people/men-front/IMG_1956.jpg` are the body photos.

## Run

```
cd e2e
npm install
npx playwright install chromium
npx playwright test
npx playwright show-report
```

One file: `npx playwright test tests/06-wardrobe.spec.ts`.

## After testing

Delete the test shoppers and everything they made (photos, try-ons, chats, wardrobe, feedback):

```
cd backend
.venv-cpu\Scripts\python.exe scripts\e2e_users.py delete
```

## How the tests find things

Flutter web draws on a canvas; with `E2E=true` it also builds an accessibility tree. Buttons
are found by role and name, text fields by their label (a field's error message is part of its
label), plain text with `seen()` (text or label). Photo pickers open a file chooser, which the
tests answer with a file from the test kit.
