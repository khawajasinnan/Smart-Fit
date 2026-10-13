# SmartFit — Design System ("Luminous Vibe")

The visual identity SmartFit ships with: glassmorphic surfaces floating over slow-drifting gradient orbs, bold geometric display type against clean body text, and a violet-to-magenta palette that reads as confident, current, and a little playful — built for a GenZ shopper who screenshots things. Every token below is meant to be dropped straight into `core/theme/` (see `architecture.md` §4.1).

> **One clarification up front:** "3D" in this document means UI motion — depth, parallax, tilt on cards — not 3D garment or body rendering. Full 3D try-on rendering is explicitly out of scope per `prd.md` §4.2; SmartFit's try-on output stays 2D. The "3D" is in how the interface *moves*, not in what it renders.

## 1. Signature Element

The thing this app is remembered by: **ambient orbs** — two or three large, softly-blurred gradient blobs drifting slowly behind every glass surface. They're present on nearly every screen (welcome, auth, profile setup, home) at low opacity, giving the whole app a sense of quiet motion even when nothing else on screen is animating. Everything else in this system stays disciplined around that one signature.

## 2. Color

### 2.1 Core Palette

| Token | Hex | Use |
|---|---|---|
| `primary600` | `#6C4CE0` | Primary brand violet — default fills, links, active states |
| `primary700` | `#5638C4` | Pressed/hover state for primary |
| `primary400` | `#9B85F0` | Light violet — secondary accents, unselected active icons |
| `primary100` | `#EDE7FE` | Violet tint — subtle backgrounds, selected chip fill |
| `accent600` | `#FF2E93` | Signature hot pink — primary CTAs ("Start", "Sign Up", "Finish Setup") |
| `accent700` | `#D4157A` | Darker magenta — used where a CTA needs more contrast (e.g. "Log In") |
| `accent100` | `#FFE1F0` | Pink tint — badges, soft highlights |

### 2.2 Neutrals

| Token | Hex | Use |
|---|---|---|
| `ink900` | `#14121F` | Headings, primary text |
| `ink700` | `#443F54` | Body text |
| `ink400` | `#8B85A0` | Secondary text, placeholders, inactive nav icons |
| `surface0` | `#FCF4FB` | Page background — soft lavender-pink tint, never flat white |
| `surface1` | `#FFFFFF` | Card/sheet background |
| `border` | `#ECE6F7` | Hairlines, input borders at rest |

### 2.3 Semantic

| Token | Hex | Use |
|---|---|---|
| `success` | `#2FD98A` | Confirmations, positive match scores |
| `warning` | `#F5A524` | Non-blocking alerts |
| `error` | `#F5304F` | Errors, destructive actions |
| `info` | `#4C9BE0` | Neutral informational states |

### 2.4 Signature Gradient

`linear-gradient(135deg, #6C4CE0 0%, #FF2E93 100%)` — reserved for: primary CTA buttons, the avatar upload ring, ambient orbs, and the "% Match" badge at ≥90%. Don't apply it to body text or large flat backgrounds — it's an accent, not a fill.

### 2.5 Match Badge Tiers

| Match % | Style |
|---|---|
| ≥ 90% | Filled `accent600` → `primary600` gradient pill, white text |
| 80–89% | Filled `primary600` pill, white text |
| < 80% | Outline `ink400` pill, `ink700` text |

### 2.6 Glassmorphic Surface

```
background: rgba(255, 255, 255, 0.55)     /* rgba(30, 20, 45, 0.45) in dark mode */
backdrop-filter: blur(20px)
border: 1px solid rgba(255, 255, 255, 0.6)
box-shadow: 0 8px 32px rgba(108, 76, 224, 0.15)
```

Used on: chat bubbles (AI side), the "Scan" home card, product cards over orb backgrounds, the bottom nav bar. Not used on plain content lists — reserve it for surfaces that sit over an orb or image so the blur has something to show through.

## 3. Typography

**Space Grotesk** for anything that needs presence (headlines, screen titles, the wordmark) — its geometric, slightly squared character is what gives the app its GenZ-but-not-generic look. **Inter** for everything read at length (body copy, inputs, buttons, nav labels) — quiet and legible so Space Grotesk doesn't have to compete with itself.

| Style | Font / Weight | Size / Line height | Tracking | Example use |
|---|---|---|---|---|
| Display XL | Space Grotesk Bold | 40 / 48 | −1% | Welcome screen wordmark |
| Display L | Space Grotesk Bold | 32 / 40 | −0.5% | Screen headlines ("About You", "Create Your Style") |
| H1 | Space Grotesk SemiBold | 26 / 32 | 0 | Section headers |
| H2 | Space Grotesk SemiBold | 22 / 28 | 0 | Card titles, "Hi Alex!" |
| H3 | Space Grotesk Medium | 18 / 24 | 0 | Subsection headers |
| Body L | Inter Regular | 16 / 24 | 0 | Primary body copy, chat text |
| Body M | Inter Regular | 14 / 20 | 0 | Secondary copy, card descriptions |
| Body S | Inter Regular | 12 / 16 | 0 | Captions, timestamps |
| Label | Inter SemiBold | 13 / 16 | +4% uppercase | Field labels ("BODY TYPE", "HEIGHT") |
| Button | Inter SemiBold | 16 / 20 | 0 | All button text |

## 4. Spacing, Radius, Elevation

**Spacing** (4px base grid): `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`

**Radius** — generous and pill-leaning, matching the prototype:

| Token | Value | Use |
|---|---|---|
| `radiusSm` | 12 | Small chips, badges |
| `radiusMd` | 16 | Input fields, small cards |
| `radiusLg` | 24 | Product cards, sheets |
| `radiusXl` | 32 | Large hero cards |
| `radiusPill` | 999 | Buttons, chips, nav pill highlight |

**Elevation** — shadows are tinted violet, not pure black, so depth reads as part of the brand rather than generic Material default:
- `shadowSm`: `0 2px 8px rgba(108, 76, 224, 0.08)`
- `shadowMd`: `0 8px 24px rgba(108, 76, 224, 0.12)`
- `shadowLg`: `0 16px 40px rgba(108, 76, 224, 0.18)`

## 5. Motion

### 5.1 Tokens

| Token | Duration | Use |
|---|---|---|
| `instant` | 100ms | Button press feedback |
| `fast` | 150ms | Toggle/chip selection |
| `base` | 250ms | Standard transitions |
| `slow` | 400ms | Page transitions, sheet entrances |
| `ambient` | 8000ms+ | Orb drift loops |

Easing: `easeOutCubic` for entrances, `easeInOutCubic` for shared page transitions, a light spring/overshoot for playful confirmations (save/heart icon).

### 5.2 Patterns

- **Ambient orbs** — 2–3 large blurred gradient circles behind glass content, each on its own slow independent drift + gentle scale pulse (`AnimationController`, repeating, offset timing per orb so they never sync up). Always respects the OS reduce-motion setting — freeze in place, don't just slow down.
- **3D card tilt** — product cards and the body-type avatar cards (Slim/Athletic/Broad) respond to drag with a subtle perspective rotation (`Transform` + `Matrix4`, rotateX/rotateY up to ~8°), springing back to flat on release. This is the "3D" in "animations of 3D" — depth-of-field on interaction, not a 3D model.
- **Page transitions** — shared-axis horizontal for forward navigation (signup → onboarding → home), fade-through for bottom-nav tab switches.
- **Hero transitions** — product image in a recommendation card flies into the try-on screen via `Hero`, so the item never feels like it "reloads."
- **Skeleton loading** — `shimmer` package for CV analysis wait, recommendation loading, try-on generation — never a bare spinner when the eventual content shape is known (ties to SFR-021).
- **Celebration** — a small confetti/sparkle burst when the Look Score reveals, reserved for that one moment so it stays special.
- **Button feedback** — scale to 0.96 on press + `HapticFeedback.lightImpact()`.

## 6. Component Specs

| Component | Spec |
|---|---|
| Primary button | Pill (`radiusPill`), signature gradient fill, white Inter SemiBold label, 56px height, full-width by default |
| Secondary button | Pill, 1.5px `primary600` border, transparent fill, `primary600` label |
| Text field | `radiusMd`, `surface1` background, leading icon in `ink400`, focus state = `primary600` border + soft glow (`shadowSm` in primary tint) |
| Vibe/style chip | Pill; unselected = `border` outline + `ink700` text; selected = `accent600` fill + white text + check icon |
| Match badge | Small pill, tiered per §2.5 |
| Chat bubble (user) | `primary600`→`accent600` gradient fill, white text, right-aligned, all corners rounded except bottom-right |
| Chat bubble (AI) | Glass surface (§2.6), `ink700` text, left-aligned, small gradient-filled sparkle avatar |
| Bottom nav | Glass bar (§2.6); active item = `accent600` icon/label on a soft pill highlight; inactive = `ink400` |
| Measurement slider | Track in `border`, filled portion in signature gradient, white thumb with `primary600` ring, live value bubble above thumb (matches the 182cm / 78kg prototype behavior) |

## 7. Dark Mode

Not required for MVP, but tokens are structured to support it later: swap `surface0`/`surface1` for dark violet-black equivalents (`#14121F`/`#1E1530`), keep the accent/primary hues as-is (they hold contrast well on dark), and switch glass surfaces to the dark variant already defined in §2.6.

## 8. Accessibility

- `ink900` on `surface0`/`surface1` passes WCAG AA for body text.
- Never set `accent600` text directly on white below 16px — use `accent700` for text-on-light; reserve `accent600` for fills.
- Minimum touch target 44×44.
- All ambient/looping motion must respect `MediaQuery.disableAnimations` — this isn't optional polish, it's a real accessibility requirement.
