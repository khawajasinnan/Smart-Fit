# SmartFit — Development Phases

Legend: ⬜ Not started 🔷 In progress ✅ Complete — update this and `memory.md` together as work happens.

## Timeline Reality Check

| Milestone | Due | Status |
|---|---|---|
| Proposal | February | ✅ done |
| SRS & Design Specification | April | ✅ done — `FINAL_SRDS__SmartFit__.pdf` |
| 25% of functional requirements, working software | May | ✅ done — auth, profile, home, chat, wardrobe all working |
| **90–100% of functional requirements + FYP report** | **October** | 🔷 ~55% complete — Phases 0–4, 9 done; 5–8 in progress |
| Final presentation + final report | December | ⬜ |

October is roughly three months out from today. That's not enough time to build every AI component to research quality *and* the full mobile app *and* an admin panel. The ordering below is deliberately end-to-end-first: get a thin, working version of the *entire* user journey (auth → wardrobe) demoable before polishing any single piece — a complete-but-simple app beats one perfect module and eight empty ones at a progress checkpoint. Phases 5, 6, and 7 (CV analysis, try-on, hairstyle) are flagged with a fallback option for exactly this reason.

Suggested ownership below follows the original proposal split (`prd.md` §7) — Jamal on architecture/profile/budget-cultural filtering/deployment, Sinnan on recommendation/try-on/feedback-learning/pose estimation — but treat it as a starting point, not a hard boundary.

---

## Phase 0 — Foundation & Setup
**Goal:** a repo that builds, themed, routable, and connected to Supabase — before any feature work starts.
**Includes:** clean-architecture folder scaffold (`architecture.md` §4.1), design tokens implemented (`design.md`), GoRouter skeleton with auth/profile guards, Supabase project created with tables + RLS policies (`architecture.md` §6.1), CI skeleton (lint + test on push).
**SRDS refs:** NFR §4.3.3 (maintainability), §4.3.4 (portability)
**Suggested owner:** Jamal (system architecture)
**Definition of done:** app launches to a themed splash screen, hits Supabase, and passes CI on an empty test suite.
**Status:** ✅

## Phase 1 — Authentication
**Goal:** a user can register, verify, log in, and reset a password.
**Screens:** Welcome, Sign Up, Log In, Forgot Password.
**SRDS refs:** SF-UC-01, SF-UC-02, SFR-001–005, SFR-008
**Definition of done:** email/password flow works end-to-end including verification email; at least Google OAuth works (resolve `prd.md` open question #1 before deciding on Facebook).
**Status:** ✅ — Google OAuth only for MVP; Facebook deferred

## Phase 2 — Profile Onboarding
**Goal:** the mandatory profile gate — nothing past this screen without it.
**Screens:** 4-step Profile Setup (photo → gender → body measurements → skin tone), completion enforcement.
**SRDS refs:** SF-UC-03, SFR-006, SFR-007, SFR-009–013
**Suggested owner:** Jamal (static profile intake)
**Definition of done:** an incomplete profile blocks every other route via the GoRouter guard; profile is editable later from Settings.
**Status:** ✅ — 3-step setup with ethnicity field + ft/in toggle added

## Phase 3 — Home Shell & Navigation
**Goal:** the hub everything else hangs off.
**Screens:** Home (Scan / Try On / Hair quick actions, Trending, For You), bottom navigation shell.
**Definition of done:** bottom nav wires up to all five sections even before their content is real (stubs are fine here).
**Status:** ✅ — glass nav bar + Spline-style glass cards + fashion backgrounds

## Phase 4 — AI Stylist Chatbot
**Goal:** dynamic per-session input collection.
**SRDS refs:** SF-UC-04, SFR-014–018
**Suggested owner:** Jamal (conversational preference intake)
**Definition of done:** a session captures occasion/style/colour/budget, optionally a new photo, and persists as chat history.
**Status:** ✅ — Gemini-powered with cultural outfit guidance + product search trigger

## Phase 5 — Computer Vision Analysis + Recommendations
**Goal:** turn a photo + preferences into a ranked, size-filtered product list.
**SRDS refs:** SFR-019–025, SF-UC-05
**Suggested owner:** Sinnan (pose estimation, recommendation engine)
**Fallback if time-constrained:** ship size estimation from profile measurements alone first (skip live pose estimation), backfill CV-based refinement once the rest of the pipeline works.
**Definition of done:** recommendations list renders, ranked, with size compatibility already checked before a user can tap into try-on.
**Status:** 🔷 — Scraping + ranking done (38 brands). CV pose analysis not yet built (using profile measurements fallback).

## Phase 6 — Virtual Try-On
**Goal:** the app's signature feature — visibly working, even if simplified.
**SRDS refs:** SF-UC-06, SFR-026–028
**Suggested owner:** Sinnan (try-on AI logic)
**Fallback if time-constrained:** start with a straightforward image-compositing overlay instead of full diffusion inference; swap in the diffusion model once it's validated separately (see `prd.md` open question #3 and `rules.md` §7).
**Definition of done:** selecting an in-size item produces a viewable, zoomable try-on image; an out-of-size item shows the unavailable state instead of erroring.
**Status:** 🔷 — Stub screen created + routed. AI model integration pending.

## Phase 7 — Hairstyle Recommendation
**Goal:** complete the "full look" promise.
**SRDS refs:** SF-UC-07, SFR-029–031
**Definition of done:** a default hairstyle renders automatically after try-on, with at least 2–3 browsable alternatives.
**Status:** 🔷 — Stub screen created + routed. AI model integration pending.

## Phase 8 — Look Scoring & Feedback
**Goal:** close the loop — score the look, capture feedback.
**SRDS refs:** SF-UC-08, SF-UC-09, SFR-032–034
**Suggested owner:** Sinnan (feedback learning)
**Definition of done:** a numeric/visual score with styling hints displays after hairstyle selection; feedback (rating + optional comment) persists and is visibly stored, even if the "learning" side is a stub for now.
**Status:** 🔷 — Stub screen created + routed. Scoring logic pending.

## Phase 9 — Wardrobe & History
**Goal:** persistence users actually come back for.
**SRDS refs:** SFR-035–038
**Definition of done:** completed sessions and saved items appear in Wardrobe, organized by date, each tappable through to the retailer's product page.
**Status:** ✅

## Phase 10 — Admin Panel *(separate web deliverable)*
**Goal:** the platform-management surface — lowest priority against the October deadline since it's a small slice of total functional requirements.
**SRDS refs:** SF-UC-10, SF-UC-11, SFR-039–042
**Note:** confirm scope/stack before starting — see `prd.md` open question #2. A minimal version might lean on Supabase's own dashboard rather than a hand-built web app.
**Status:** 🔷 — Basic admin screen exists in Flutter app. Separate web panel not yet built.

## Phase 11 — Hardening, Testing, Deployment
**Goal:** turn "working" into "meets the NFRs."
**Covers:** performance targets (`prd.md` §6), full security checklist (`rules.md` §5), reliability/graceful-degradation pass, test coverage per `rules.md` §6, staging environment, deployment docs.
**Status:** ⬜
