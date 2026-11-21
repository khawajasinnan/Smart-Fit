# Installing SmartFit after cloning from GitHub

This guide takes you from an empty Windows PC to the app running on your phone or in Chrome.
Go step by step; each part says how to check that it worked.

> **Not in this repo on purpose** (kept on the owner's PC): the database migrations
> (`supabase/migrations/`), the docs, the datasets, and every file with keys (`.env`,
> `frontend/env/dev.json`, `admin-panel/.env.local`). Ask the project owner for them; part 3
> says exactly which ones you need.

---

## 1. Install the tools (once per PC)

| Tool | Version | Where |
|---|---|---|
| Git | any | https://git-scm.com/download/win |
| Python | **3.11** (not 3.12+: MediaPipe and the models need 3.11) | https://www.python.org/downloads/release/python-3119/ (tick "Add to PATH") |
| Flutter | **3.41.1** (stable) | https://docs.flutter.dev/install/archive |
| Node.js | 20 or newer (only for the admin panel) | https://nodejs.org |
| Android Studio | latest, plus **JDK 17** (only for building the Android app) | https://developer.android.com/studio |

Check in a new terminal:

```
git --version
py -3.11 --version
flutter --version
node --version
```

For Android: `flutter doctor` must show a green tick for "Android toolchain". If Gradle fails
with a newer Java, point Flutter at JDK 17: `flutter config --jdk-dir "C:\path\to\jdk-17"`.

## 2. Get the code

```
git clone https://github.com/khawajasinnan/Smart-Fit.git
cd Smart-Fit
```

## 3. The private settings files (from the project owner)

Copy these from the owner's PC into the same places in your clone. Without them the app cannot
reach Supabase or Gemini.

| File | What it holds | Start from |
|---|---|---|
| `.env` (repo root) | Backend keys: Supabase URL + anon key + service key, Gemini key, try-on settings | `.env.example` |
| `frontend/env/dev.json` | App settings: Supabase URL + anon key, backend address | `frontend/env/env.example.json` |
| `admin-panel/.env.local` | Admin panel: Supabase URL + anon key, backend address | `admin-panel/.env.example` |

Setting up your own Supabase project instead? Then you also need the migration files
(`supabase/migrations/`, from the owner): run them in order in Supabase → SQL Editor, oldest
first. Never put the service key in `dev.json` or the admin panel: it belongs in `.env` only.

## 4. The backend (8 small Python services)

In a terminal, from the repo folder:

```
cd backend
py -3.11 -m venv .venv-cpu
.venv-cpu\Scripts\python.exe -m pip install --upgrade pip
.venv-cpu\Scripts\python.exe -m pip install -r requirements-dev.txt
```

This takes 10-20 minutes (it downloads PyTorch for CPU, about 1 GB).

Model files that are too big or not ours to put in git:

```
.venv-cpu\Scripts\python.exe scripts\download_cv_models.py
.venv-cpu\Scripts\python.exe scripts\download_hairstyle_models.py
```

Optional, copy from the owner's PC if you want everything exactly the same (all gitignored):

- `backend/services/hairstyle/catalog/`: the hairstyle reference pictures (made from the
  non-commercial CelebAMask-HQ dataset, so they can't be on GitHub).
- `backend/services/recommendation/models/gender/`: the men's/women's product check models.
- `backend/data/`: the saved product catalog (otherwise it is fetched again from the stores).

Start everything:

```
run_local.bat
```

Eight minimized windows open (ports 8000-8007). Check: open http://localhost:8000/docs in a
browser. The first start takes about a minute while the recommendation model loads.
Stop everything with `run_local.bat -Stop`.

Run the tests if you like: `.venv-cpu\Scripts\python.exe -m pytest -q` (about 5 minutes).

### Try-on and hairstyles on the GPU (optional)

In `.env`, `TRYON_BACKEND=mock` gives clearly labelled test pictures without a GPU. For real
try-ons the GPU apps run on Modal (paid per use):

```
.venv-cpu\Scripts\python.exe -m pip install modal
.venv-cpu\Scripts\modal.exe token new
.venv-cpu\Scripts\modal.exe deploy services/tryon/modal_app.py
.venv-cpu\Scripts\modal.exe deploy services/hairstyle/modal_app.py
```

Then set `TRYON_BACKEND=modal` and `HAIRSTYLE_BACKEND=modal` in `.env` and restart the backend.

## 5. The app (Flutter)

```
cd frontend
flutter pub get
```

**Phone and PC on the same Wi-Fi:** the phone reaches the backend through the PC's network
address. Write it into `env/dev.json` automatically:

```
set_api_ip.bat
```

Run it again whenever requests start failing with "connection timeout" (Wi-Fi gives the PC a
new address now and then), then restart the app.

Run in Chrome (port 5000 is the one set up for Google sign-in):

```
flutter run -d chrome --web-port 5000 --dart-define-from-file=env/dev.json
```

Build for an Android phone (stop the backend first on a 16 GB PC; both at once run out of memory):

```
flutter build apk --debug --dart-define-from-file=env/dev.json
```

The file is `build\app\outputs\flutter-apk\app-debug.apk`; copy it to the phone and install.
Use debug, not release: release builds block the plain `http://` address of your PC.

Checks: `flutter analyze` (no issues) and `flutter test` (all pass).

## 6. The admin panel (optional)

```
cd admin-panel
npm install
npm run dev
```

Open the address it prints (http://localhost:5173). Only accounts listed as admins can log in.

## 7. End-to-end tests (optional)

See `e2e/README.md`. They create test shoppers on the hosted Supabase and delete them afterwards.

## Common problems

| You see | Fix |
|---|---|
| `running scripts is disabled on this system` | Use `run_local.bat`, not the `.ps1` |
| App: "connection timeout" | Backend not running, or the Wi-Fi address changed: `set_api_ip.bat`, restart the app |
| `The paging file is too small` | Out of memory: stop the backend while building the APK |
| Android build fails in `camera_android_camerax` | Gradle is using a Java newer than 17: `flutter config --jdk-dir` to JDK 17 |
| Zayn says it is "a bit busy" | The free Gemini key allows 20 requests a day; wait until 13:00 Pakistan time |
| Web build without fonts/icons | `flutter clean`, then build again |
