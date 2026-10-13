# SmartFit — Product Requirements Document (PRD)

**Project:** SmartFit — AI-Powered Fit and Hairstyle Recommendation App
**Institution:** COMSATS University Islamabad, Wah Campus — Dept. of Computer Science (Session 2023–2027)
**Track:** Data Science / Computer Vision / Mobile Application Development
**Team:** Jamal Ahmed Khan (SP23-BSE-013) · Khawaja Sinnan Hussain (SP23-BSE-025)
**Supervisor:** Mam Samia Riaz
**Source of truth:** `FINAL_SRDS__SmartFit__.pdf` — this PRD is a build-ready distillation of that document. If anything here and the SRDS ever disagree, the SRDS wins; flag the conflict and update this file.

---

## 1. The Pitch

Online fashion shopping in Pakistan has a trust problem: shoppers can't tell if an item will actually fit their body, suit their skin tone, or work for the occasion until it arrives — so a huge share of orders come back. Product photos are shot on standard models that look nothing like the buyer, and platforms don't account for body size, real stock availability, cultural appropriateness, or budget.

**SmartFit** is a mobile app that lets a user upload one photo, answer a few quick questions, and see AI-generated, size-validated outfit and hairstyle recommendations — visualized on their *own* photo — sourced live from Pakistani retailers like Outfitters and Breakout, filtered by their body measurements, skin tone, occasion, and budget. Nothing else on the market currently solves size feasibility, budget, and cultural/occasion appropriateness together in one pre-purchase visualization flow — that combination is SmartFit's whole reason to exist.

## 2. Objectives

1. Give users an AI-powered 2D virtual try-on that reduces purchase uncertainty.
2. Pull real-time product data from Pakistani fashion e-commerce platforms (Outfitters, Breakout) and surface recommendations matched to the analyzed user.
3. Recommend hairstyles that complement the chosen outfit, so the user sees a complete look, not just clothes.
4. Combine static profile data (photo, gender, measurements, skin tone) with dynamic chatbot input (occasion, style, budget) to sharpen recommendation accuracy.
5. Maintain a personal digital wardrobe — session history plus saved items — linked straight to the retailer's product page.
6. Learn from user feedback to improve future recommendations.
7. Give admins a panel to manage users, the product catalogue, and platform analytics.
8. Ship something performant, secure, and scalable on Flutter, Supabase, FastAPI, and Docker/Kubernetes.

## 3. Who It's For

### 3.1 End User — the Fashion Shopper
Age 15+, smartphone-literate, shops online in Pakistan, wants to *see* how something will look and fit before buying. Uses the app in sessions: open the chatbot, describe an occasion, browse recommendations, try things on, save what they like. Assumed to have a stable connection — there's no offline mode.

### 3.2 Guest / Unregistered User
Downloaded the app, hasn't finished signing up. Can only see registration and login. Nothing else renders until an account exists and the profile is complete — this gate is a hard product rule, not a suggestion (SFR-006, SFR-013).

### 3.3 Administrator
Manages users, the fashion catalogue, scraping config, and reviews analytics/feedback through a **separate, web-based admin panel** — not part of the end-user mobile app (SRDS §2.1, §2.3.9). Assumed technically literate.

## 4. Product Scope

### 4.1 In Scope
- Authentication & account management — email/password + Google/Facebook OAuth, age gate (15+), email verification, JWT sessions
- Mandatory profile setup — photo, gender, body measurements, skin tone
- AI stylist chatbot — collects occasion, style, colour preference, budget per session
- Computer vision analysis — body shape/size estimation from the uploaded photo
- Product scraping & recommendation engine — Outfitters, Breakout; ranked by fit + preferences
- 2D diffusion-based virtual try-on
- AI hairstyle recommendation (2D overlay), default + alternatives
- Overall look scoring with AI styling comments, plus user feedback capture
- Personalized wardrobe & session history (ChatGPT-style history), with retailer redirect
- Admin panel — user management, catalogue management, analytics dashboard, feedback review

### 4.2 Explicitly Out of Scope
- Native in-app payment processing — purchases redirect to the retailer's own site
- Physical tailoring or sizing services
- Full 3D try-on rendering (this is a 2D system, by design — see `design.md` for why "3D" only shows up as a UI motion style, not a rendering pipeline)
- HR management or CRM features

## 5. Feature Map

Every feature below traces back to an SRDS requirement ID so nothing gets built — or skipped — without a paper trail.

| Module | What it does | Requirement IDs |
|---|---|---|
| Auth & Account | Register, verify email, log in, OAuth, password reset, deactivate/delete account | SFR-001–005, SFR-008, SF-UC-01, SF-UC-02 |
| Profile Onboarding | Mandatory redirect + photo, gender, height/weight/chest/waist/hip, skin tone; blocks all other features until complete | SFR-006, SFR-007, SFR-009–013, SF-UC-03 |
| AI Stylist Chatbot | Conversational collection of occasion, style, colour, budget; optional extra photo per session | SFR-014–018, SF-UC-04 |
| Computer Vision Analysis | Body shape/proportion extraction, size estimation (S/M/L/XL) | SFR-019–021 |
| Scraping & Recommendations | Live/scheduled scrape of Outfitters & Breakout; rank + filter by size/budget/style | SFR-022–025, SF-UC-05 |
| Virtual Try-On | Diffusion-based 2D overlay of the chosen item on the user's photo | SFR-026–028, SF-UC-06 |
| Hairstyle Recommendation | Gender + face features + outfit style → default + alternative hairstyles, 2D overlay | SFR-029–031, SF-UC-07 |
| Look Scoring & Feedback | AI score + styling hints for the full look; user rates/corrects | SFR-032–034, SF-UC-08, SF-UC-09 |
| Wardrobe & History | Save outfit + try-on + hairstyle; browse by session date; tap through to retailer | SFR-035–038 |
| Admin Panel | Manage/suspend/delete users, manage catalogue & scraping config, analytics dashboard, feedback review | SFR-039–042, SF-UC-10, SF-UC-11 |

## 6. Non-Functional Bar

The numbers a build is judged against — see `phases.md` Phase 11 for when they get hardened.

| Area | Target |
|---|---|
| App cold start | ≤ 3s on 4G |
| General API response | ≤ 2s |
| CV analysis | ≤ 10s |
| Virtual try-on generation | ≤ 20s |
| Recommendations surfaced | ≤ 15s |
| Concurrent users | 500 minimum, horizontally scaled |
| Uptime | 99.5% monthly (excl. maintenance) |
| Try-on image quality | ≥ 720p-equivalent |
| Onboarding (signup → first session) | ≤ 5 minutes, completable with no prior training |

Security bar (non-negotiable, detailed in `rules.md` §5): bcrypt password hashing, JWT + refresh tokens, TLS 1.2+ everywhere, signed URLs for private photo storage, RBAC on every admin endpoint, rate limiting on auth/AI endpoints, server-side file validation, age gate at registration.

## 7. Timeline & Constraints

This is a 2-person FYP with a fixed external schedule, not an open-ended build:

| # | Semester | Milestone | Deliverable | Due |
|---|---|---|---|---|
| 1 | VII | Proposal | Document | February |
| 2 | VII | SRS & Design Specification | Document | April ✅ done — this is `FINAL_SRDS__SmartFit__.pdf` |
| 3 | VII | 25% of functional requirements | Working software | May |
| 4 | VIII | 90–100% of functional requirements | Working software + FYP report | **October** |
| 5 | VIII | Final presentation | Complete software + final report | December |

As of today, the SRS milestone is behind you and the next hard deadline — 90–100% functional — is roughly three months out. That's tight for a system with a diffusion-based try-on pipeline, custom CV analysis, and a live scraper on top of a full mobile app. `phases.md` is written with that pressure in mind: it front-loads the features that make the app demoable end-to-end, and treats the hardest AI components as things to get *working* first and *good* second.

Per the original proposal deck, module ownership was split: **Jamal** — system architecture, static profile & conversational preference intake, budget/ethnicity/cultural filtering with size validation, integration & deployment. **Sinnan** — recommendation engine, virtual try-on AI logic, feedback learning, pose estimation & processing. Treat this as a starting point, not a fence — `phases.md` tags suggested ownership per phase, but two people building a system this size will inevitably cross lines.

## 8. Open Questions

Things the SRDS doesn't fully resolve — worth a five-minute decision before they become blockers:

1. **Facebook OAuth** — required by SFR-001/SFR-004, but absent from the external interfaces list (§2.5.3, which only names Google). Build both for MVP, or ship Google-only and add Facebook later?
2. **Admin panel scope** — it's explicitly a separate web deliverable (§2.1, §2.3.9), not part of the Flutter app. Worth deciding early whether it's a real second app, a minimal internal tool, or largely covered by Supabase's own dashboard for MVP purposes.
3. **Virtual try-on model** — true diffusion-based garment try-on (the SRDS's spec) is research-grade work (approaches like IDM-VTON or OOTDiffusion exist as reference points). Worth deciding whether to self-host an existing open-source checkpoint, call a hosted API, or start with a simpler image-compositing overlay as a placeholder and upgrade later.
4. **Scraper reliability** — live scraping of retailer sites is fragile by nature (site structure changes, rate limits, possible ToS friction). SFR-022 already allows "real-time or scheduled" — worth deciding whether the demo runs on a cached/seeded product dataset for stability, with live scraping as a stretch goal.

*(These are also logged in `memory.md` so they don't get lost.)*
