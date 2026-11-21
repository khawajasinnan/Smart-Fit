# SmartFit

SmartFit is an AI fashion assistant for the Pakistani market: a Flutter app with a FastAPI
backend and Supabase. Shoppers set up a profile (body shape, measurements, usual size, skin tone
and undertone, culture), chat with the AI stylist Zayn, get products from Pakistani stores in
their size, try clothes on virtually, preview hairstyles, score a look and keep a wardrobe.
Admins manage users, feedback and the product catalog in a web panel.

**Install and run it: see [INSTALL.md](INSTALL.md).**

## What is where

```text
frontend/      Flutter app (Android, iOS, web)
backend/       FastAPI: gateway (port 8000) + 7 services
  gateway/       the only address the app and the admin panel talk to
  services/      cv_analysis, recommendation, scraper, chat_orchestrator,
                 tryon, hairstyle, scoring
  shared/        code used by several services (sizes, colours, cultures ...)
  scripts/       model downloads, catalog and training tools
  tests/         pytest suite
admin-panel/   React + Vite admin panel
e2e/           Playwright end-to-end tests of the whole app
k8s/, docker-compose.yml   deployment manifests
supabase/      Supabase CLI config
```

## Stack

- Flutter + Dart, Riverpod, go_router
- FastAPI + Python 3.11, MediaPipe, FashionCLIP, LightGBM
- Supabase (Auth, PostgreSQL, Storage)
- Gemini for the stylist chat
- Modal GPUs for the virtual try-on (IDM-VTON) and hairstyle previews

## Checks

```bash
cd frontend && flutter analyze && flutter test
cd backend && .venv-cpu\Scripts\python.exe -m ruff check . && .venv-cpu\Scripts\python.exe -m pytest -q
cd admin-panel && npm test
```

GitHub Actions runs the Flutter and backend checks on every push.

## Notes

- Never put the Supabase service key in the app or the admin panel; it belongs in the backend `.env` only.
- The datasets used for training and evaluation (VITON-HD, DressCode, CelebAMask-HQ) are for
  non-commercial research only and are not in this repository.
