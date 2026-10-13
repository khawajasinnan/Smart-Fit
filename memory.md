# SmartFit — Project Memory / Progress Log

**Last updated:** 2026-09-03
**Purpose:** the living record of what's actually been done, what's mid-flight, and what's still open. Update this at the end of every work session — see `rules.md` §4.

## Current Status

Phases 0–5 and 9 are fully implemented. Recent updates delivered the comprehensive Gen-Z UI/UX elevation, including an iridescent glassmorphic bottom navigation bar with breathing AI pulse button, dynamic Gen-Z trends powered by Unsplash API, redesigned luxury-editorial daily quotes with shuffle & copy, interactive mood & notification top bar synced with Settings, a sassy emoji-rich AI stylist chat persona with quick starters and action pills, a brand-elevated splash screen, animated login/register screens, optimized profile setup imagery, and a signature pink clothing icon pattern background (`ClothingPatternBackground`) deployed across all 15 screens in the application.

## ✅ Completed

- Full SRS/Design Specification finalized (`FINAL_SRDS__SmartFit__.pdf`)
- "Luminous Vibe" design system established and implemented in code
- Six-file planning set created
- **Phase 0 — Foundation & Setup**: Clean architecture scaffold, GoRouter + auth/profile guards, Supabase connected, CI-ready
- **Phase 1 — Authentication**: Email/password registration, email verification, login, Google OAuth, forgot password (SFR-001–005, SFR-008)
- **Phase 2 — Profile Onboarding**: 3-step mandatory profile setup (gender+ethnicity+photo → body measurements with ft/in toggle → style preferences), profile gate blocks all features until complete (SFR-006–013)
- **Phase 3 — Home Shell & Navigation**: Home dashboard with ambient orbs, Spline-style glass feature cards with fashion photography, fashion silhouette background, dynamic per-user daily quotes, fully transparent glass bottom nav (5 tabs)
- **Phase 4 — AI Stylist Chatbot**: Gemini-powered conversational stylist, session history, occasion/style/budget collection, `[SMARTFIT_SEARCH]` product trigger, cultural/ethnic outfit guidance (SFR-014–018)
- **Phase 5 — Recommendations** (partial): Live scraping from 38 Pakistani brands (Khaadi, Gul Ahmed, Sapphire, Outfitters, Breakout, etc.), ethnicity-aware scoring (+8 for cultural keyword matches), query builder with category maps, recommendation engine with scoring algorithm (SFR-022–025)
- **Phase 9 — Wardrobe & History**: Wardrobe screen with saved items, session history, retailer redirect (SFR-035–038)
- **Gen-Z Youngster Trends with API**: Integrated `TrendService` querying Unsplash fashion search API (`trendApiKey`) with category filtering chips (Y2K, Baggy Core, Desi Fusion, Coquette, Blokecore), match scores, and interactive refresh
- **Interactive Top Bar & Mood Selector**: Avatar rank badge ("⚡ Trendsetter"), daily mood picker sheet, reactive notification bell with unread badge synced with Settings
- **Notification System**: `NotificationNotifier` synced with `SharedPreferences` (`outfit_notifications_enabled`), reactive notifications bottom sheet
- **Quotes Widget Redesign**: Compact luxury editorial card with `#FF2E93` watermark, interactive shuffle button and clipboard copy
- **Sassy AI Stylist Persona**: High-energy Gen-Z styling advice, emoji-infused greetings, starter prompt chips, and message reaction pills (Copy & Love Fit)
- **Signature Pink Clothing Icon Background**: Custom vector painter `ClothingPatternBackground` (pink `#FF2E93`, low opacity) integrated across all 15 app screens
- **Splash Screen Redesign**: Glowing brand icon, iridescent gradient typography, pink clothing pattern, and zero-flicker routing
- **Login & Register Polish**: Tactile button bounce animations (`flutter_animate`), glass card entrance animations, and clothing background
- **Profile Setup Optimization**: Compressed body-type imagery (`w=280&q=75`), reliable fallbacks, and clothing background
- **100% Test Suite Pass**: Fixed ethnicity field fixture in `test/profile_model_parsing_test.dart` and verified all tests pass
- Ethnicity/culture field added to profile model + DB + scraping pipeline (Punjabi, Sindhi, Balochi, Pathan, Saraiki)
- Feet/inches ↔ cm measurement toggle (ft/in default)
- Design system enhancements: shimmer package, button press scale (0.96) + haptic feedback, match badge widget (3-tier per design.md §2.5)

## 🔷 In Progress

- **Phase 6 — Virtual Try-On**: Stub screen created with coming-soon UI, wired into router. AI model integration pending.
- **Phase 7 — Hairstyle**: Stub screen created with coming-soon UI, wired into router. AI model integration pending.
- **Phase 8 — Look Scoring & Feedback**: Stub screen created with coming-soon UI, wired into router. Scoring logic pending.
- **Phase 5 — CV Analysis**: Body shape/proportion extraction from photo not yet implemented. Currently uses profile measurements for size estimation.

## ⬜ Up Next

- Phase 5 CV — implement body shape analysis from photo using MediaPipe/OpenCV
- Phase 6 — integrate 2D virtual try-on (diffusion or compositing overlay)
- Phase 7 — integrate hairstyle recommendation AI
- Phase 8 — implement look scoring algorithm + feedback collection
- Phase 10 — Admin Panel (separate web deliverable)
- Phase 11 — Hardening, testing, deployment

## Key Facts Worth Not Losing

- **Real deadlines:** 90–100% functional requirements due **October 2026**; final presentation **December 2026**.
- **Team split (per original proposal):** Jamal — system architecture, static profile/conversational intake, budget/ethnicity/cultural + size validation, integration & deployment. Sinnan — recommendation engine, virtual try-on AI logic, feedback learning, pose estimation & processing.
- **Frontend is mobile-only.** The Flutter app targets Android + iOS; there is no web build of the end-user app.
- **Try-on is 2D.** Full 3D rendering is explicitly out of scope.
- **38 Pakistani brands** integrated in the scraper (including 8 new: Bareeze, Agha Noor, Hussain Rehar, Amir Adnan, Deepak Perwani, Penny, Stone Harbor, Motifz).
- **Backend uses `http` package**, not Dio as `rules.md` specifies. Migration to Dio is a future refactor.

## Decision Log

| Date | Decision |
|---|---|
| — | Stack: Flutter (mobile only) + Riverpod + GoRouter + Dio + Supabase + FastAPI + Docker/Kubernetes |
| — | Design direction: "Luminous Vibe" glassmorphism, violet/magenta palette, Space Grotesk + Inter |
| 2026-07-26 | Six planning docs (this set) created from `FINAL_SRDS__SmartFit__.pdf` + original proposal deck |
| 2026-07-27 | Ethnicity field added (Punjabi/Sindhi/Balochi/Pathan/Saraiki) — moved from style prefs to dedicated field |
| 2026-07-27 | Measurement toggle: ft/in ↔ cm with ft/in as default display |
| 2026-07-27 | Try-on/Hairstyle/Look Score: stub screens first, AI model integration later (per phases.md fallback strategy) |
| 2026-07-27 | Google OAuth only for MVP; Facebook OAuth deferred |
| 2026-07-27 | Scraper: live scraping from day one with 38 brands; cached fallback via seeded data |

## Open Questions

1. ~~Facebook OAuth~~ — **Deferred.** Google-only for MVP.
2. Admin panel — real second web app, minimal internal tool, or lean on Supabase's dashboard for MVP?
3. Virtual try-on model — self-hosted open-source diffusion checkpoint, hosted API, or simplified compositing overlay first?
4. ~~Scraper~~ — **Resolved.** Live scraping from day one with 38 brands.

## How to Update This File

At the end of a session: move finished items from "In Progress" to "Completed," add anything newly started to "In Progress," update `phases.md` statuses to match, log any real decision in the table above, and update the "Last updated" date at the top. Keep entries terse — this file is a log, not a report.
