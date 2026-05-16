# DESIGN.md — SmartFit Design System

## Design Language: "Luminous Vibe"

SmartFit uses a premium, light-mode aesthetic built on **glassmorphism**, **luminous ambient glows**, and **editorial fashion photography**. The overall feel is airy, ethereal, Gen-Z forward, and premium — think a high-end digital fashion magazine rendered as a mobile app.

---

## 1. Color System

All colors are defined as Tailwind CSS tokens. Use **only these** exact hex values throughout the app.

### Core Brand Colors

| Token | Hex | Usage |
|---|---|---|
| `primary` | `#6b38d4` | Main brand color — buttons, active states, headlines |
| `on-primary` | `#ffffff` | Text/icons on primary-filled surfaces |
| `primary-container` | `#8455ef` | Primary icon containers, elevated primary surfaces |
| `on-primary-container` | `#fffbff` | Text/icons on primary-container surfaces |
| `primary-fixed` | `#e9ddff` | Soft primary tint backgrounds |
| `primary-fixed-dim` | `#d0bcff` | Ambient glow orbs, secondary tint backgrounds |
| `on-primary-fixed` | `#23005c` | Dark text on primary-fixed surfaces |
| `on-primary-fixed-variant` | `#5516be` | Variant text on primary-fixed |
| `inverse-primary` | `#d0bcff` | Inverse primary for dark surfaces |

### Secondary (Pink / Hot Pink)

| Token | Hex | Usage |
|---|---|---|
| `secondary` | `#b4136d` | Accent text links, secondary actions, active chips |
| `on-secondary` | `#ffffff` | Text/icons on secondary-filled surfaces |
| `secondary-container` | `#fd56a7` | Hot pink — Join button, vibrant accent fills |
| `on-secondary-container` | `#600037` | Text on secondary-container surfaces |
| `secondary-fixed` | `#ffd9e4` | Soft pink ambient glow, text selection background |
| `secondary-fixed-dim` | `#ffb0cd` | Ambient orbs (pink side), lighter pink tint |
| `on-secondary-fixed` | `#3e0022` | Text on secondary-fixed |
| `on-secondary-fixed-variant` | `#8c0053` | Variant text on secondary-fixed |

### Tertiary (Amber / Warm Orange)

| Token | Hex | Usage |
|---|---|---|
| `tertiary` | `#855000` | Rare warm accent (not commonly used in current screens) |
| `on-tertiary` | `#ffffff` | Text on tertiary surfaces |
| `tertiary-container` | `#a76500` | Warm container accent |
| `on-tertiary-container` | `#fffbff` | Text on tertiary-container |
| `tertiary-fixed` | `#ffdcbb` | Warm tint fixed |
| `tertiary-fixed-dim` | `#ffb869` | Warm tint dim |
| `on-tertiary-fixed` | `#2c1700` | Dark text on tertiary-fixed |
| `on-tertiary-fixed-variant` | `#673d00` | Variant text on tertiary-fixed |

### Surface & Background

| Token | Hex | Usage |
|---|---|---|
| `background` | `#fef7ff` | App background — very pale lavender-white |
| `on-background` | `#1d1a23` | Primary body text on background |
| `surface` | `#fef7ff` | Card/panel base surface (same as background) |
| `on-surface` | `#1d1a23` | Primary text on surface |
| `surface-dim` | `#ded7e4` | Dimmed overlay on surface |
| `surface-bright` | `#fef7ff` | Brightest surface variant (same as surface) |
| `surface-variant` | `#e7e0ed` | Input backgrounds, toggle tracks, inactive surfaces |
| `on-surface-variant` | `#494454` | Secondary body text, labels, placeholder-adjacent |
| `surface-tint` | `#6d3bd7` | Tinted surface (elevated) |

### Surface Containers (Elevation Layers)

| Token | Hex | Usage |
|---|---|---|
| `surface-container-lowest` | `#ffffff` | Pure white — glass card overlays |
| `surface-container-low` | `#f8f1fe` | Very light input fill backgrounds |
| `surface-container` | `#f3ebf8` | Standard input field backgrounds |
| `surface-container-high` | `#ede5f3` | Slightly elevated containers (OTP box bg) |
| `surface-container-highest` | `#e7e0ed` | Most elevated container, inactive filter chips |

### Inverse & Special

| Token | Hex | Usage |
|---|---|---|
| `inverse-surface` | `#322f39` | Dark inverse surface (tooltips, dark overlays) |
| `inverse-on-surface` | `#f5eefb` | Text on inverse surface |

### Outline

| Token | Hex | Usage |
|---|---|---|
| `outline` | `#7b7486` | Standard border, icon default color in forms |
| `outline-variant` | `#cbc3d7` | Subtle dividers, inactive input borders |

### Error

| Token | Hex | Usage |
|---|---|---|
| `error` | `#ba1a1a` | Error states, destructive actions (Log Out text) |
| `on-error` | `#ffffff` | Text on error fills |
| `error-container` | `#ffdad6` | Error background fill |
| `on-error-container` | `#93000a` | Text on error-container |

---

## 2. Typography

### Font Families

| Role | Font | Weight | Usage |
|---|---|---|---|
| `font-display-lg` | Space Grotesk | 700 | App logo "SmartFit", hero headlines, screen titles |
| `font-headline-lg` | Space Grotesk | 600 | Section headings, card titles (32px) |
| `font-headline-md` | Space Grotesk | 600 | Button labels, form section headers (24px) |
| `font-quote-vibrant` | Space Grotesk | 700 | Inspirational quote text (28px) |
| `font-body-lg` | Inter | 400 | Subtitles, form labels, description text (18px) |
| `font-body-md` | Inter | 400 | Body copy, chat bubbles, small descriptions (16px) |
| `font-label-caps` | Inter | 700 | ALL-CAPS chip labels, nav bar labels, field labels (12px, 0.1em letter-spacing) |

### Font Size Scale

| Token | Size | Line Height | Letter Spacing | Weight |
|---|---|---|---|---|
| `text-display-lg` | 48px | 1.1 | -0.02em | 700 |
| `text-headline-lg` | 32px | 1.2 | — | 600 |
| `text-headline-md` | 24px | 1.2 | — | 600 |
| `text-quote-vibrant` | 28px | 1.1 | — | 700 |
| `text-body-lg` | 18px | 1.6 | — | 400 |
| `text-body-md` | 16px | 1.5 | — | 400 |
| `text-label-caps` | 12px | 1 | 0.1em | 700 |

### Typography Rules
- Logo **"SmartFit"** always uses `font-display-lg` with `tracking-tighter` and `text-primary`
- Screen titles use `text-display-lg` (48px) for major onboarding/hero screens
- Section headers use `text-headline-lg` (32px)
- Card and component headers use `text-headline-md` (24px)
- Quote blocks always use `font-quote-vibrant text-quote-vibrant` with gradient or primary color
- Navigation labels always use `font-label-caps text-label-caps` in UPPERCASE
- Form field labels always use `font-label-caps text-label-caps text-on-surface-variant ml-2`

---

## 3. Spacing & Layout

### Core Spacing Tokens

| Token | Value | Usage |
|---|---|---|
| `gutter` | 16px | Grid column gap, small internal spacing |
| `margin-mobile` | 24px | Left/right page margins, standard horizontal padding |
| `container-padding` | 24px | Internal card/panel padding |
| `unit` | 8px | Base unit for micro-spacing (mb-unit, gap-unit) |

### Layout Principles
- Max content width: `max-w-md` (448px) for auth/forms, `max-w-lg` (512px) for onboarding, `max-w-2xl` for chat, `max-w-7xl` for home dashboard
- Content is always horizontally centered: `mx-auto`
- Page horizontal padding: `px-margin-mobile` (24px)
- Standard card internal padding: `p-container-padding` (24px) or `p-8` (32px)

---

## 4. Border Radius

| Token | Value | Usage |
|---|---|---|
| `rounded-DEFAULT` | 1rem (16px) | Standard cards, input fields |
| `rounded-lg` | 2rem (32px) | Large cards, modals, glassmorphic panels |
| `rounded-xl` | 3rem (48px) | Splash screen bottom sheet |
| `rounded-full` | 9999px | Buttons (pill shape), avatar circles, chips |
| `rounded-[24px]` | 24px | Input fields (inline custom) |
| `rounded-[1.5rem]` | 24px | Chat bubbles |
| `rounded-[2rem]` | 32px | Floating bottom sheet, vault items |
| `rounded-[32px]` | 32px | Registration card |
| `rounded-[24px]` | 24px | Vault bento grid items |

---

## 5. Glassmorphism System

All major containers use a consistent glassmorphism pattern. There are three levels:

### Level 1 — Subtle Glass (Section Cards)
```css
background: rgba(255, 255, 255, 0.60);
backdrop-filter: blur(24px);
-webkit-backdrop-filter: blur(24px);
border: 1px solid rgba(255, 255, 255, 0.50);
box-shadow: 0 10px 30px rgba(107, 56, 212, 0.05), inset 0 1px 0 rgba(255, 255, 255, 0.80);
```
Tailwind: `bg-surface/60 backdrop-blur-2xl border border-white/50`

### Level 2 — Standard Glass (Main Content Cards)
```css
background: rgba(255, 255, 255, 0.70);
backdrop-filter: blur(24px);
-webkit-backdrop-filter: blur(24px);
border: 1px solid rgba(255, 255, 255, 0.40);
box-shadow: 0 20px 40px rgba(139, 92, 246, 0.10);
```
Tailwind: `bg-surface/70 backdrop-blur-2xl border border-white/40 shadow-[0_20px_40px_rgba(139,92,246,0.10)]`

### Level 3 — Heavy Glass (Auth Modals / OTP)
```css
background: rgba(255, 255, 255, 0.70) or rgba(255,255,255,0.75);
backdrop-filter: blur(48px);
-webkit-backdrop-filter: blur(48px);
border: 1px solid rgba(255, 255, 255, 0.60);
box-shadow: 0 30px 60px rgba(139, 92, 246, 0.15);
```
Tailwind: `bg-surface-container-lowest/70 backdrop-blur-3xl border border-white/60 shadow-[0_30px_60px_rgba(139,92,246,0.15)]`

### Inner Glow (applied inside glass cards)
Add as an absolutely-positioned overlay inside the card:
```html
<div class="absolute inset-0 bg-gradient-to-b from-white/40 to-transparent pointer-events-none rounded-xl"></div>
```

---

## 6. Ambient Glow System

Every screen has ambient glow orbs in the background to create the "luminous" atmosphere.

### Standard Two-Orb Pattern
```html
<!-- Primary orb (top-left) -->
<div class="absolute top-[-10%] left-[-10%] w-[50vw] h-[50vw] rounded-full bg-primary-fixed opacity-40 blur-[100px] pointer-events-none"></div>
<!-- Secondary orb (bottom-right) -->
<div class="absolute bottom-[-10%] right-[-10%] w-[60vw] h-[60vw] rounded-full bg-secondary-fixed opacity-30 blur-[120px] pointer-events-none"></div>
```

### Splash Screen Overlay Pattern (for hero photo screens)
```html
<div class="absolute inset-0 bg-gradient-to-b from-surface/10 via-surface/30 to-surface/90"></div>
```

### Body Gradient Backgrounds
Used on auth screens and registration:
```css
/* Radial gradient body */
background-image: radial-gradient(circle at top left, #f3ebf8 0%, #fef7ff 50%, #ede5f3 100%);

/* Linear gradient body (registration) */
background: linear-gradient(135deg, #fef7ff 0%, #f5eefb 50%, #ffd9e4 100%);

/* Directional radial mix */
background-image: radial-gradient(circle at top right, rgba(253,86,167,0.05) 0%, transparent 40%),
                  radial-gradient(circle at bottom left, rgba(107,56,212,0.05) 0%, transparent 40%);
```

### TopAppBar Background Blur
```html
<header class="bg-surface/70 backdrop-blur-xl border-b border-white/40 shadow-[0_20px_40px_rgba(139,92,246,0.05)]">
```

---

## 7. Button System

### Primary Action Button (Pill / Full-width)
Used as the main CTA on every screen.

```html
<button class="w-full bg-primary text-on-primary font-headline-md text-headline-md py-4 rounded-full shadow-[0_10px_30px_rgba(107,56,212,0.3)] hover:shadow-[0_15px_35px_rgba(107,56,212,0.4)] hover:opacity-90 active:scale-[0.98] transition-all duration-200">
  Button Label
</button>
```

**Exact shadow:** `0 10px 30px rgba(107,56,212,0.3)` — hover: `0 15px 35px rgba(107,56,212,0.4)`

**With arrow icon:**
```html
<button class="w-full bg-primary text-on-primary font-headline-md text-headline-md py-4 px-6 rounded-full flex items-center justify-center gap-3 shadow-[0_8px_30px_rgba(107,56,212,0.4)] hover:opacity-90 active:scale-[0.98] transition-all duration-200 group">
  <span>Get Started</span>
  <span class="material-symbols-outlined text-[28px] group-hover:translate-x-1 transition-transform duration-200">arrow_forward</span>
</button>
```

### Secondary / Hot Pink Button (Join / Registration)
```html
<button class="w-full bg-secondary-container text-on-secondary-container font-headline-md text-headline-md py-4 rounded-full shadow-[0_10px_30px_rgba(253,86,167,0.3)] hover:shadow-[0_15px_40px_rgba(253,86,167,0.4)] hover:bg-secondary transition-all hover:scale-[1.02] active:scale-95 flex items-center justify-center gap-2">
  Join
  <span class="material-symbols-outlined text-[24px]">arrow_forward</span>
</button>
```

### Gradient Button (Login screen variant)
```css
/* btn-gradient class */
background: linear-gradient(90deg, #8455ef 0%, #fd56a7 100%);
```
```html
<button class="w-full btn-gradient text-on-primary font-body-lg text-body-lg font-bold py-4 rounded-full shadow-[0_10px_20px_rgba(132,85,239,0.3)] hover:opacity-90 transition-opacity flex items-center justify-center gap-2 group">
  Log In
  <span class="material-symbols-outlined group-hover:translate-x-1 transition-transform">arrow_forward</span>
</button>
```

### Glow CTA (Onboarding Bottom Sheet / Secondary pink)
Outer glow effect wrapping button:
```html
<button class="w-full relative group">
  <div class="absolute -inset-1 bg-gradient-to-r from-secondary to-secondary-container rounded-full blur opacity-40 group-hover:opacity-70 transition duration-300"></div>
  <div class="relative w-full bg-secondary text-on-secondary py-5 px-8 rounded-full flex items-center justify-center gap-3 active:scale-[0.98] transition-transform duration-200">
    <span class="font-label-caps text-label-caps uppercase tracking-widest">Next</span>
    <span class="material-symbols-outlined text-[20px]">arrow_forward</span>
  </div>
</button>
```

### Back / Navigation Button
```html
<button class="w-12 h-12 flex items-center justify-center rounded-full bg-surface/50 backdrop-blur-md border border-white/40 shadow-sm text-on-surface hover:bg-white/80 transition-colors">
  <span class="material-symbols-outlined">arrow_back</span>
</button>
```
Variant (solid): `bg-surface-container-high text-on-surface-variant hover:bg-surface-variant`

### Social Auth Buttons (Google / Apple / Facebook)
```html
<button class="flex-1 bg-surface-container-lowest border border-outline-variant/30 rounded-full py-3 flex items-center justify-center gap-2 hover:bg-surface-container-low transition-colors shadow-sm">
  <img class="w-5 h-5" src="google-logo.png" alt="Google Logo"/>
  <span class="font-body-md text-body-md font-medium text-on-surface">Google</span>
</button>
```

### Log Out Button (Destructive)
```html
<button class="w-full py-4 rounded-full bg-surface-variant text-error font-headline-md text-headline-md shadow-sm hover:bg-error-container hover:text-on-error-container transition-all duration-300 flex items-center justify-center gap-2 group border border-white/30 backdrop-blur-md">
  <span class="material-symbols-outlined group-hover:-translate-x-1 transition-transform">logout</span>
  Log Out
</button>
```

### Icon-Only Circle Button
```html
<button class="w-12 h-12 flex items-center justify-center rounded-full bg-primary/10 hover:bg-primary/20 transition-colors text-primary">
  <span class="material-symbols-outlined">add_photo_alternate</span>
</button>
```

### Send/Submit Icon Button (Chat Input)
```html
<button class="w-12 h-12 shrink-0 rounded-full flex items-center justify-center text-on-primary bg-primary shadow-[0_0_15px_rgba(107,56,212,0.4)] hover:bg-surface-tint transition-colors active:scale-90">
  <span class="material-symbols-outlined" style="font-variation-settings: 'FILL' 1;">arrow_upward</span>
</button>
```

---

## 8. Form Input System

### Standard Text/Email/Password Input
```html
<div class="flex flex-col gap-2">
  <label class="font-label-caps text-label-caps text-on-surface-variant ml-2" for="email">EMAIL ADDRESS</label>
  <div class="relative flex items-center bg-surface-container rounded-[24px] overflow-hidden border border-outline-variant/30 transition-all duration-300 input-focus-glow">
    <div class="pl-4 pr-2 flex items-center pointer-events-none">
      <span class="material-symbols-outlined text-outline">mail</span>
    </div>
    <input
      class="w-full py-4 pr-4 bg-transparent border-none outline-none font-body-lg text-body-lg text-on-background placeholder:text-outline/60 focus:ring-0"
      id="email"
      placeholder="hello@example.com"
      type="email"
    />
  </div>
</div>
```

**Input focus glow CSS:**
```css
.input-focus-glow:focus-within {
  box-shadow: 0 0 0 2px #6b38d4, 0 0 15px rgba(107, 56, 212, 0.3);
  border-color: transparent;
}
```

**Alternative input style (Registration screen):**
```html
<input class="w-full bg-surface-container-low text-on-background border border-outline-variant/30 rounded-[24px] px-6 py-4 font-body-lg text-body-lg placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-secondary-container focus:border-secondary-container transition-all shadow-inner" />
```

### Password Input with Visibility Toggle
```html
<div class="relative group input-glow rounded-lg transition-shadow duration-300">
  <span class="material-symbols-outlined absolute left-5 top-1/2 -translate-y-1/2 text-outline-variant">lock</span>
  <input
    class="w-full bg-surface-container border border-transparent text-on-surface font-body-md text-body-md rounded-lg py-4 pl-14 pr-12 focus:outline-none focus:bg-surface-bright transition-colors"
    type="password"
    placeholder="Enter new password"
  />
  <button class="absolute right-5 top-1/2 -translate-y-1/2 text-outline-variant hover:text-primary transition-colors focus:outline-none" type="button">
    <span class="material-symbols-outlined">visibility_off</span>
  </button>
</div>
```

**Input glow on focus-within:**
```css
.input-glow:focus-within {
  box-shadow: 0 0 0 2px rgba(107, 56, 212, 0.4);
  border-color: #6b38d4;
}
```

### OTP / Verification Code Input (4-digit, phone variant)
```html
<div class="flex justify-between w-full gap-3 mb-10">
  <input
    class="w-14 h-16 text-center font-display-lg text-headline-lg bg-white/50 border border-outline-variant/40 rounded-DEFAULT text-on-surface shadow-sm focus:bg-white focus:border-secondary-container focus:ring-2 focus:ring-secondary-container/50 focus:shadow-[0_0_25px_rgba(253,86,167,0.35)] transition-all duration-300"
    inputmode="numeric" maxlength="1" pattern="[0-9]*" type="number"
  />
  <!-- Repeat x4 -->
</div>
```

### OTP Input (6-digit, email variant)
```html
<div class="flex gap-2 justify-center w-full mb-[48px]">
  <input
    class="w-12 h-14 rounded-DEFAULT bg-surface-container-high border border-outline-variant/50 text-center font-headline-md text-headline-md text-on-surface focus:outline-none input-glow transition-all"
    maxlength="1" type="text"
  />
  <!-- Repeat x6 -->
</div>
```

**OTP focus glow:**
```css
.input-glow:focus {
  box-shadow: 0 0 0 2px rgba(107, 56, 212, 0.3), 0 0 15px rgba(107, 56, 212, 0.2);
  border-color: #6b38d4;
}
```

### Toggle Switch (Settings)
```html
<div class="relative inline-block w-12 mr-2 align-middle select-none">
  <input class="toggle-checkbox absolute block w-6 h-6 rounded-full bg-white border-4 appearance-none cursor-pointer z-10 opacity-0" type="checkbox" />
  <label class="toggle-label block overflow-hidden h-6 rounded-full cursor-pointer transition-colors duration-300 relative
    after:content-[''] after:absolute after:top-0.5 after:left-0.5 after:bg-white after:w-5 after:h-5 after:rounded-full after:shadow-md after:transition-transform after:duration-300">
  </label>
</div>
```

```css
.toggle-label { background-color: #e7e0ed; } /* surface-variant */
.toggle-checkbox:checked + .toggle-label { background-color: #fd56a7; } /* secondary-container */
.toggle-checkbox:checked + .toggle-label:after { transform: translateX(100%); }
```

---

## 9. Chip System

### Filter Chip (Active)
```html
<button class="px-6 py-3 rounded-full font-label-caps text-label-caps bg-primary text-on-primary shadow-[0_0_20px_rgba(107,56,212,0.4)] hover:opacity-90 transition-opacity whitespace-nowrap">
  All
</button>
```

### Filter Chip (Inactive)
```html
<button class="px-6 py-3 rounded-full font-label-caps text-label-caps bg-surface-container-highest text-on-surface-variant hover:bg-surface-variant transition-colors border border-white/50 shadow-sm whitespace-nowrap">
  Hair
</button>
```

### Style Preference Chip (Active)
```html
<button class="px-6 py-3 rounded-full bg-primary text-on-primary font-body-lg text-body-lg shadow-[0_10px_25px_rgba(107,56,212,0.35)] relative overflow-hidden group">
  <div class="absolute inset-0 bg-white/20 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none"></div>
  <span class="relative z-10 flex items-center gap-2">
    Luxury
    <span class="material-symbols-outlined text-[18px]">diamond</span>
  </span>
</button>
```

### Style Preference Chip (Inactive)
```html
<button class="px-6 py-3 rounded-full bg-surface-container border border-outline-variant/30 font-body-lg text-body-lg text-on-surface hover:bg-surface-container-high transition-colors shadow-sm">
  Streetwear
</button>
```

### Edit Profile Pill Chip
```html
<button class="font-label-caps text-label-caps bg-primary-container text-on-primary-container px-4 py-2 rounded-full shadow-[0_4px_12px_rgba(132,85,239,0.2)] hover:bg-primary hover:text-white transition-colors">
  EDIT PROFILE
</button>
```

---

## 10. Navigation

### TopAppBar (Persistent — Home/Chat/Vault/Settings)
```html
<header class="fixed top-0 w-full z-50 bg-surface/70 backdrop-blur-xl border-b border-white/40 shadow-[0_20px_40px_rgba(139,92,246,0.05)] flex justify-between items-center px-margin-mobile py-4">
  <!-- Hamburger Menu -->
  <button class="w-10 h-10 flex items-center justify-center rounded-full hover:bg-surface-variant/50 transition-colors text-primary hover:opacity-80 active:scale-95">
    <span class="material-symbols-outlined" style="font-variation-settings: 'FILL' 0;">menu</span>
  </button>
  <!-- Logo (absolute center) -->
  <h1 class="font-display-lg text-headline-md tracking-tighter text-primary absolute left-1/2 transform -translate-x-1/2">SmartFit</h1>
  <!-- Avatar -->
  <button class="w-10 h-10 rounded-full overflow-hidden border-2 border-white/80 shadow-sm hover:opacity-80 active:scale-95">
    <img class="w-full h-full object-cover" src="avatar.jpg" alt="User profile" />
  </button>
</header>
```

**TopAppBar for Transactional Screens** (Auth, OTP, Password Reset — back button only, no logo/nav):
```html
<header class="w-full h-16 flex items-center px-margin-mobile z-50">
  <button class="w-10 h-10 flex items-center justify-center rounded-full bg-surface-container/50 hover:bg-surface-container transition-colors" type="button">
    <span class="material-symbols-outlined text-on-surface">arrow_back</span>
  </button>
</header>
```

### BottomNavBar (5-Tab)
```html
<nav class="fixed bottom-0 left-0 w-full flex justify-around items-center px-4 py-3 pb-8 bg-surface/80 backdrop-blur-2xl border-t border-white/40 shadow-[0_-10px_30px_rgba(139,92,246,0.1)] z-50 rounded-t-lg">
  <!-- Inactive Tab -->
  <button class="flex flex-col items-center justify-center text-on-surface-variant/60 hover:text-secondary transition-colors group w-16">
    <span class="material-symbols-outlined mb-1 group-hover:scale-110 transition-transform" style="font-variation-settings: 'FILL' 0;">home</span>
    <span class="font-label-caps text-[10px]">Home</span>
  </button>
  <!-- Active Tab -->
  <button class="flex flex-col items-center justify-center text-primary bg-primary-container/20 rounded-full px-4 py-2 shadow-[0_0_15px_rgba(132,85,239,0.3)] scale-110 duration-300 ease-out min-w-[72px]">
    <span class="material-symbols-outlined mb-1" style="font-variation-settings: 'FILL' 1;">auto_awesome</span>
    <span class="font-label-caps text-[10px] font-bold">AI Styles</span>
  </button>
</nav>
```

**Active tab rules:**
- Background: `bg-primary-container/20`
- Text: `text-primary`
- Icon: `font-variation-settings: 'FILL' 1` (filled)
- Scale: `scale-110`
- Shadow: `shadow-[0_0_15px_rgba(132,85,239,0.3)]`
- Label: `font-bold`

**Inactive tab rules:**
- Text: `text-on-surface-variant/60`
- Icon: `font-variation-settings: 'FILL' 0` (outlined)
- Hover: `hover:text-secondary`

**Tab Labels & Icons:**

| Tab | Icon (Material) | Label |
|---|---|---|
| Home | `home` | Home |
| Try-On | `checkroom` | Try-On |
| AI Styles | `auto_awesome` | AI Styles |
| Vault | `Guitar` | Vault |
| Profile | `person` | Profile |

---

## 11. Screen-by-Screen Specifications

---

### Screen 1: Splash / Get Started

**Layout:** Full-screen hero with bottom glassmorphic card

**Background:** Full-bleed editorial fashion photo. Gradient overlay:
```html
<div class="absolute inset-0 bg-gradient-to-b from-surface/10 via-surface/30 to-surface/90"></div>
```

**Logo:** Centered, `font-display-lg text-display-lg text-primary tracking-tighter`
Text shadow: `text-shadow: 0 4px 20px rgba(107,56,212,0.3)`

**Bottom Card (Glassmorphic):**
```html
<div class="w-full bg-surface/70 backdrop-blur-xl border border-white/40 rounded-[2rem] p-8 flex flex-col items-center gap-8 shadow-[0_20px_40px_rgba(139,92,246,0.15)] mb-8">
```

**Quote Text:** `font-quote-vibrant text-quote-vibrant text-center bg-clip-text text-transparent bg-gradient-to-br from-primary to-secondary-container`

**CTA Button:** Primary full-width pill with arrow icon (see Button System §7)

---

### Screen 2: Login

**Layout:** Two ambient orbs (top-left primary, bottom-right secondary). Centered content max-w-md.

**Hero Image Card:** `relative w-full h-64 rounded-xl overflow-hidden shadow-[0_20px_40px_rgba(139,92,246,0.15)] mb-8 glass-panel` — fashion editorial photo with `bg-gradient-to-t from-background/80 to-transparent` overlay. Title "Welcome Back" and subtitle overlaid on bottom.

**Form Card:** `glass-panel rounded-xl p-6` (70% white, blur 24px)

**Fields:** Email (with mail icon), Password (with lock icon + "Forgot?" link aligned right)
- Input background: `bg-surface-container-low`
- Border radius: `rounded-[24px]`
- Focus ring: `focus:ring-2 focus:ring-primary`

**Divider:** `Or continue with` centered between two `border-t border-outline-variant/50` lines

**Social Buttons:** Two equal-width rounded-full buttons (Google with logo image, Apple with `ios` Material icon)

**Footer:** "New here? Join" — "Join" in `text-primary font-bold`

---

### Screen 3: Registration / Join

**Layout:** Ambient gradient background (3 large blurred orbs: pink top-left, purple right, pink bottom-left). Back button header. Glass card centered.

**Card:** `bg-surface/70 backdrop-blur-[30px] border border-white/60 rounded-[32px] p-8 shadow-[0_20px_60px_rgba(180,19,109,0.1)]`

**Decorative element:** `absolute -z-10 -bottom-6 -right-6 w-32 h-32 bg-primary-container rounded-full blur-[40px] opacity-60`

**Fields:** Name, Email, Password — all `rounded-[24px] bg-surface-container-low border border-outline-variant/30`
Focus: `focus:ring-2 focus:ring-secondary-container focus:border-secondary-container`

**CTA:** Hot pink gradient button (secondary-container → secondary) — see Button System §7

**Footer:** "Already have an account? Log In" — "Log In" in `text-secondary-container font-bold underline decoration-2 underline-offset-4 decoration-secondary-fixed`

---

### Screen 4: Forgot Password (Email)

**Layout:** Fixed gradient background (radial: pink top-right + purple bottom-left). Back button in header. Content centered max-w-md.

**Icon:** `w-20 h-20 mx-auto mb-6 rounded-[2rem] bg-surface-container-high` with `lock_reset` Material icon in `text-primary text-[40px]`. Soft glow behind: `absolute inset-0 bg-primary/10 rounded-[2rem] blur-xl`

**Heading:** `font-display-lg text-display-lg` (48px!) — "Reset Password"
**Subtitle:** `font-body-lg text-body-lg text-on-surface-variant max-w-[280px] mx-auto text-center`

**Card:** `glass-panel rounded-xl p-container-padding` (white 70%, blur 24px, border white/40, shadow purple)

**Email Input:** Pill-shaped `rounded-[24px]` with mail icon, `bg-surface-container`
Focus: `input-focus-glow` class (box-shadow: 0 0 0 2px primary + 15px glow)

**CTA:** Primary pill with "Send Code" + `arrow_forward` icon

**Footer link:** "Remember your password? Log in" — "Log in" in `text-primary font-bold hover:underline`

---

### Screen 5: OTP Verification — Phone (4-digit)

**Layout:** Blurred fashion image background (opacity 30% + blur-3xl + scale-110) with `bg-surface/40` overlay. Centered glass card.

**Card:** `bg-surface-container-lowest/70 backdrop-blur-3xl border border-white/60 shadow-[0_30px_60px_rgba(139,92,246,0.15)] rounded-xl p-8`

**Icon Circle:** `w-16 h-16 rounded-full bg-primary-fixed/50 shadow-[0_0_20px_rgba(132,85,239,0.2)]` with `lock_open` icon (FILL 1)

**Heading:** `font-display-lg text-headline-lg` — "Verify It's You"
**Subtitle:** `font-body-lg text-body-lg text-on-surface-variant` — "We sent a code to your phone."

**OTP Inputs:** 4 boxes, each `w-14 h-16` (or `w-16 h-20` on md). Background: `bg-white/50`. Border: `border-outline-variant/40`. Focus: `focus:bg-white focus:border-secondary-container focus:ring-2 focus:ring-secondary-container/50 focus:shadow-[0_0_25px_rgba(253,86,167,0.35)]`

**CTA:** `w-full bg-primary text-on-primary font-headline-md py-4 rounded-full shadow-[0_10px_30px_rgba(107,56,212,0.3)]`

**Resend:** "Didn't receive it? Send Again" — "Send Again" in `text-secondary font-bold hover:text-secondary-container hover:underline`

---

### Screen 6: OTP Verification — Email (6-digit)

**Layout:** Radial gradient background (`from primary-fixed-dim/30 blur-[100px]` + `from secondary-fixed-dim/20 blur-[120px]`). Back button. Centered glass card.

**Card:** `glass-panel rounded-xl p-container-padding` with `shadow-[0_20px_40px_rgba(139,92,246,0.08)]`

**Icon Circle:** `w-16 h-16 rounded-full bg-primary-container text-primary shadow-lg shadow-primary/20` with `mark_email_read` icon (FILL 1, 32px)

**Heading:** `font-headline-lg text-headline-lg` — "Check Your Email"
**Subtitle:** `font-body-md text-body-md text-on-surface-variant` — "We sent a 6-digit code to your email."

**OTP Inputs:** 6 boxes, each `w-12 h-14`. Background: `bg-surface-container-high`. Border: `border border-outline-variant/50`. Focus: `input-glow` class (purple glow).

**CTA:** `w-full py-4 rounded-full bg-primary text-on-primary font-headline-md text-[20px] btn-glow`
```css
.btn-glow { box-shadow: 0 8px 24px rgba(107, 56, 212, 0.3); }
.btn-glow:hover { box-shadow: 0 12px 32px rgba(107, 56, 212, 0.4); }
```

**Resend:** "Didn't receive code? Resend" — "Resend" in `text-primary font-bold`

---

### Screen 7: Create New Password

**Layout:** Two luminous orbs background (top-left primary/40, bottom-right secondary/30). Back button. Centered content max-w-md.

**Card:** `bg-white/70 backdrop-blur-2xl border border-white/40 shadow-[0_20px_40px_rgba(139,92,246,0.15)] rounded-xl p-8` with inner gradient overlay.

**Icon:** `w-16 h-16 rounded-full bg-primary-container/30 shadow-[0_0_20px_rgba(132,85,239,0.2)]` with `password` icon (FILL 1, 30px)

**Heading:** `font-headline-lg text-headline-lg` — "New Password"
**Subtitle:** `font-body-md text-body-md text-on-surface-variant`

**Fields:** New Password + Confirm Password, each with:
- Lock icon (left): `absolute left-5 top-1/2 -translate-y-1/2 text-outline-variant`
- Visibility toggle (right): `absolute right-5 top-1/2 -translate-y-1/2 text-outline-variant hover:text-primary`
- Background: `bg-surface-container`
- Padding: `py-4 pl-14 pr-12`
- Focus: `input-glow` (purple ring)

**CTA:** Primary pill with shimmer hover effect:
```html
<button class="w-full relative overflow-hidden group bg-primary text-on-primary font-headline-md text-headline-md rounded-full py-5 shadow-[0_10px_30px_rgba(107,56,212,0.4)] hover:shadow-[0_15px_40px_rgba(107,56,212,0.6)] active:scale-[0.98] transition-all duration-300">
  <div class="absolute inset-0 bg-white/20 translate-y-full group-hover:translate-y-0 transition-transform duration-300 ease-out"></div>
  <span class="relative z-10 flex items-center justify-center gap-2">
    Change Password
    <span class="material-symbols-outlined text-lg">arrow_forward</span>
  </span>
</button>
```

---

### Screen 8: Onboarding (3-step, Step 1)

**Layout:** Full-bleed fashion photo background. Gradient overlays (via/secondary-fixed/20 + from-surface bottom). Content pushed to bottom.

**Progress Indicator:**
```html
<div class="flex gap-2 items-center justify-center mb-8 w-full">
  <!-- Active step: wide pill -->
  <div class="h-2 w-10 bg-secondary rounded-full shadow-[0_0_12px_rgba(180,19,109,0.5)]"></div>
  <!-- Inactive steps: small dot -->
  <div class="h-2 w-2 bg-surface-variant rounded-full"></div>
  <div class="h-2 w-2 bg-surface-variant rounded-full"></div>
</div>
```

**Bottom Sheet:** `bg-surface/70 backdrop-blur-2xl border border-white/40 shadow-[0_-20px_60px_rgba(253,86,167,0.15)] rounded-[2rem] p-8`

Internal glow: `absolute -top-10 left-1/2 -translate-x-1/2 w-32 h-32 bg-secondary-container/30 rounded-full blur-[40px]`

**Heading:** `font-display-lg text-display-lg text-on-surface` — "See yourself in new clothes."
**Subtitle:** `font-body-lg text-body-lg text-on-surface-variant/80`

**CTA:** Secondary glow button (see §7 Glow CTA) — "Next" with `arrow_forward` in `font-label-caps text-label-caps uppercase tracking-widest`

---

### Screen 9: Profile Setup / "Tell Us About You"

**Layout:** Two ambient orbs. Back button. Scrollable main content. Fixed bottom "Go" button.

**Header:** `font-display-lg text-display-lg` — "Tell us about you"
Subtitle: `font-body-lg text-body-lg text-on-surface-variant`

**Quote Card:** `bg-surface/70 backdrop-blur-xl border border-white/60 rounded-xl p-8 shadow-[0_20px_40px_rgba(139,92,246,0.08)]` — gradient fill from-primary/5 to-secondary/5. Quote in `font-quote-vibrant text-quote-vibrant text-primary`

**Base Model Selector (Horizontal Scroll):**
Container: `flex gap-gutter overflow-x-auto no-scrollbar pb-4 snap-x snap-mandatory -mx-margin-mobile px-margin-mobile`

Inactive card: `snap-start shrink-0 w-[140px] aspect-[3/4] rounded-lg border border-white/40 bg-surface-container/50 shadow-sm`

Active card: `snap-start shrink-0 w-[140px] aspect-[3/4] rounded-lg border-2 border-primary bg-primary-container/10 shadow-[0_10px_30px_rgba(107,56,212,0.15)] scale-[1.02]`
Active checkmark badge: `absolute top-2 right-2 w-6 h-6 rounded-full bg-primary flex items-center justify-center`

**Measurement Sliders (Height + Weight):**
Card: `bg-surface/60 backdrop-blur-2xl border border-white/50 rounded-xl p-6 shadow-[0_10px_30px_rgba(139,92,246,0.05)]`

Label row: icon (text-primary for height, text-secondary for weight) + CAPS label + value right-aligned in `font-headline-md text-headline-md`

Track: `w-full h-2 bg-surface-container-high rounded-full overflow-hidden`
Fill: `h-full bg-primary/80` (or `bg-secondary/80` for weight)
Thumb: `w-6 h-6 bg-surface rounded-full border border-outline-variant shadow-[0_4px_12px_rgba(107,56,212,0.3)]`

**Aesthetic Core Chips:** See Chip System §9

**Sticky Bottom CTA:**
```html
<div class="fixed bottom-0 left-0 w-full p-margin-mobile bg-gradient-to-t from-background via-background/90 to-transparent z-40 pb-8">
  <div class="max-w-lg mx-auto">
    <button class="w-full bg-primary text-on-primary rounded-full py-4 font-headline-md text-headline-md shadow-[0_15px_40px_rgba(107,56,212,0.4)] ...">Go</button>
  </div>
</div>
```

---

### Screen 10: Settings

**Layout:** Gradient body (`bg-gradient-to-br from-surface to-surface-container-high`). TopAppBar + BottomNavBar (Me tab active). Body padded `pt-[80px] pb-[120px]`.

**Quote:** `font-quote-vibrant text-quote-vibrant text-primary drop-shadow-[0_4px_12px_rgba(107,56,212,0.15)] tracking-tight` — `"Stay fresh, stay you."`

**Profile Card:** `glass-card rounded-lg p-container-padding flex items-center gap-container-padding`
Avatar: `w-20 h-20 rounded-full border-4 border-white shadow-[0_8px_16px_rgba(107,56,212,0.15)]`
Name: `font-headline-md text-headline-md`
Username: `font-body-md text-body-md text-on-surface-variant`

**Settings List Cards:** `glass-card rounded-lg overflow-hidden flex flex-col`
Each row: `w-full flex items-center justify-between p-container-padding hover:bg-white/40 transition-colors group`
Icon: `text-outline group-hover:text-primary`
Label: `font-headline-md text-body-lg`
Chevron: `material-symbols-outlined group-hover:translate-x-1`
Divider: `h-px bg-white/50 w-full`

**Glass card CSS:**
```css
.glass-card {
  background-color: rgba(255, 255, 255, 0.6);
  backdrop-filter: blur(24px);
  -webkit-backdrop-filter: blur(24px);
  border: 1px solid rgba(255, 255, 255, 0.5);
  box-shadow: 0 10px 30px rgba(107, 56, 212, 0.05), inset 0 1px 0 rgba(255, 255, 255, 0.8);
}
```

**Notifications Card:**
Section header: icon (FILL 1) + `font-headline-md text-headline-md text-primary`
Toggle row: title `text-body-lg text-on-surface` + subtitle `text-body-md text-on-surface-variant text-sm` + toggle (see §8 Toggle Switch)

Active toggle color: `secondary-container` (#fd56a7)

---

### Screen 11: Home Dashboard

**Layout:** Sticky gradient background. TopAppBar. BottomNavBar (Home active). FAB chat button fixed bottom-right.

**Welcome:** `font-headline-lg text-headline-lg text-primary` + `font-body-lg text-body-lg text-on-surface-variant`

**Quick Actions Bento Grid:** `grid grid-cols-2 gap-gutter`

Scan button (square glass card):
```html
<button class="col-span-1 aspect-square bg-surface/70 backdrop-blur-2xl rounded-lg border border-white/40 shadow-[0_20px_40px_rgba(139,92,246,0.1)] flex flex-col items-center justify-center gap-4 hover:scale-95 transition-transform group">
```
Icon container: `w-16 h-16 rounded-full bg-primary-container/20 shadow-[0_0_15px_rgba(132,85,239,0.3)] group-hover:bg-primary group-hover:text-on-primary`

Try On button (primary fill):
```html
<button class="col-span-1 aspect-square bg-primary text-on-primary rounded-lg shadow-[0_20px_40px_rgba(139,92,246,0.25)]">
```
Inner white overlay: `absolute inset-0 bg-gradient-to-tr from-transparent to-white/20`

Hair button (secondary tint, 2-col on mobile):
`col-span-2 md:col-span-1 bg-secondary-container/20 backdrop-blur-2xl rounded-lg border border-white/40`

**Quote Block:** `bg-surface/70 backdrop-blur-2xl rounded-xl border border-white/40 p-8 text-center relative overflow-hidden`
Pink orb: `absolute top-0 right-0 w-32 h-32 bg-secondary-fixed-dim/30 rounded-full blur-3xl -translate-y-1/2 translate-x-1/2`

**Trending Cards:** Each card: `bg-surface/70 backdrop-blur-2xl rounded-xl border border-white/40 shadow-[0_20px_40px_rgba(139,92,246,0.1)] overflow-hidden group`
Image: `aspect-[4/5] group-hover:scale-105 transition-transform duration-700`
Gradient overlay: `absolute inset-0 bg-gradient-to-t from-surface-dim/80 to-transparent`
Tag badge: `bg-surface-container/80 backdrop-blur-md rounded-full font-label-caps text-label-caps text-primary`

**FAB Chat Button:**
```html
<button class="fixed bottom-28 right-6 w-16 h-16 rounded-full bg-gradient-to-tr from-secondary-container to-primary shadow-[0_15px_30px_rgba(139,92,246,0.3)] flex items-center justify-center text-white z-40 hover:scale-110 transition-transform active:scale-95 group">
  <div class="absolute inset-0 rounded-full bg-white/20 blur-sm group-hover:blur-md transition-all"></div>
  <span class="material-symbols-outlined text-3xl relative z-10" style="font-variation-settings: 'FILL' 1;">chat_bubble</span>
</button>
```

---

### Screen 12: AI Stylist Chat

**Layout:** TopAppBar. Ambient glow (top-right primary, bottom-left secondary). Chat bubbles. Fixed chat input bar. BottomNavBar (AI Styles active).

**Chat Quote Block:** `bg-surface/60 backdrop-blur-2xl border border-white/50 rounded-[2rem] p-8 text-center`
Quote: `font-quote-vibrant text-quote-vibrant bg-clip-text text-transparent bg-gradient-to-br from-primary via-primary to-secondary`

**User Bubble (right-aligned):**
```html
<div class="self-end max-w-[85%]">
  <div class="bg-surface-container-high text-on-surface px-6 py-4 rounded-[1.5rem] rounded-br-[0.5rem] shadow-sm border border-white/30">
    <p class="font-body-md text-body-md">Message text</p>
  </div>
  <p class="font-label-caps text-[10px] text-on-surface-variant/50 text-right mt-1.5 mr-2">10:42 AM</p>
</div>
```

**AI Bubble (left-aligned):**
```html
<div class="self-start max-w-[95%] flex flex-col gap-4 w-full">
  <div class="bg-surface/80 backdrop-blur-xl border border-white/60 px-6 py-4 rounded-[1.5rem] rounded-bl-[0.5rem] shadow-[0_10px_30px_rgba(139,92,246,0.08)] inline-block max-w-[90%]">
    <p class="font-body-md text-body-md text-on-surface">AI response text</p>
  </div>
```

**Product Card (inside AI bubble):**
```html
<div class="bg-surface/70 backdrop-blur-2xl border border-white/60 rounded-[2rem] p-4 shadow-[0_20px_40px_rgba(139,92,246,0.12)] w-full ml-2 relative overflow-hidden group">
  <div class="absolute inset-0 bg-gradient-to-br from-white/40 to-transparent pointer-events-none rounded-[2rem]"></div>
  <!-- Image: aspect-[4/5], group-hover:scale-105 duration-700 -->
  <!-- Match badge: top-4 right-4, bg-surface/80 backdrop-blur-md, rounded-full, text-primary, font-label-caps -->
  <!-- Title: font-headline-md text-headline-md -->
  <!-- Price/color: font-label-caps text-label-caps text-on-surface-variant opacity-70 uppercase -->
  <!-- CTA: bg-primary rounded-full font-label-caps shadow-[0_0_20px_rgba(107,56,212,0.4)] -->
</div>
```

**Match Badge:**
```html
<div class="absolute top-4 right-4 bg-surface/80 backdrop-blur-md px-4 py-1.5 rounded-full text-primary font-label-caps text-[10px] border border-white/60 shadow-[0_4px_12px_rgba(0,0,0,0.05)] tracking-widest flex items-center gap-1">
  <span class="material-symbols-outlined text-[14px]" style="font-variation-settings: 'FILL' 1;">auto_awesome</span>
  94% MATCH
</div>
```

**Chat Input Bar (fixed above BottomNavBar):**
```html
<div class="fixed bottom-[96px] w-full px-margin-mobile left-1/2 -translate-x-1/2 z-40 max-w-2xl">
  <div class="bg-surface/80 backdrop-blur-2xl border border-white/60 rounded-full p-2 flex items-center gap-2 shadow-[0_-10px_30px_rgba(139,92,246,0.08)] focus-within:ring-2 focus-within:ring-primary/40 focus-within:bg-surface transition-all duration-300">
    <!-- Photo icon btn: bg-primary/10 rounded-full -->
    <input class="flex-1 bg-transparent border-none focus:ring-0 font-body-md text-body-md text-on-surface placeholder-on-surface-variant/60 px-3 outline-none" placeholder="Describe a vibe or upload a photo..." />
    <!-- Send btn: bg-primary rounded-full shadow-[0_0_15px_rgba(107,56,212,0.4)] active:scale-90 -->
  </div>
</div>
```

---

### Screen 13: Your Vault

**Layout:** TopAppBar (hidden on mobile). BottomNavBar (Vault active). Bento grid.

**Title:** `font-display-lg text-display-lg text-on-surface` — "Your Vault"

**Quote Card:** `bg-surface-container-low/60 backdrop-blur-xl rounded-xl border border-white/60 shadow-[0_20px_40px_rgba(253,86,167,0.08)]`
Quote: `font-quote-vibrant text-quote-vibrant text-transparent bg-clip-text bg-gradient-to-r from-primary to-secondary-container`
Decorative orbs inside card: `absolute -top-4 -left-4 w-12 h-12 bg-secondary-container/20 rounded-full blur-xl` + `absolute -bottom-4 -right-4 w-16 h-16 bg-primary-container/20 rounded-full blur-xl`

**Filter Chips:** See Chip System §9 — `flex justify-center gap-gutter overflow-x-auto pb-4 hide-scrollbar`

**Bento Grid:** `grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-gutter`
- Tall item: `row-span-2 aspect-[3/5]`
- Wide item: `col-span-2 aspect-[16/9]`
- Square item: `aspect-square`

Each vault item:
```html
<div class="relative rounded-[24px] overflow-hidden group shadow-[0_10px_30px_rgba(139,92,246,0.08)] border border-white/40 cursor-pointer">
  <img class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700" />
  <div class="absolute bottom-0 left-0 w-full p-4 bg-gradient-to-t from-black/50 via-black/20 to-transparent">
    <div class="bg-surface/80 backdrop-blur-xl rounded-[16px] p-3 border border-white/30 transform translate-y-2 group-hover:translate-y-0 opacity-90 group-hover:opacity-100 transition-all duration-300">
      <h3 class="font-headline-md text-[16px] text-on-surface">Item Name</h3>
      <p class="font-label-caps text-label-caps text-secondary-container mt-1">Category</p>
    </div>
  </div>
</div>
```

Category label colors:
- Outfits: `text-secondary-container`
- Hair: `text-primary`

---

### Screen 14: Wardrobe Scanner (Camera View)

**Layout:** Full-bleed camera background. TopAppBar (blurred). Camera content fills screen.

**Quote Pill (top center):**
```html
<div class="bg-white/60 backdrop-blur-2xl border border-white/60 px-8 py-4 rounded-full shadow-[0_10px_30px_rgba(139,92,246,0.1)]">
  <p class="font-quote-vibrant text-quote-vibrant text-primary text-center">Your closet, evolved.</p>
</div>
```

**Scan Reticle:**
```html
<div class="w-[280px] h-[280px] relative">
  <!-- Four corners: 48px x 48px, 4px border, primary color, rounded corners -->
  <div class="absolute top-0 left-0 w-12 h-12 border-t-[4px] border-l-[4px] border-primary rounded-tl-[1.5rem] shadow-[0_0_15px_rgba(107,56,212,0.5)]"></div>
  <!-- ...repeat for all 4 corners -->
  <!-- Scan laser line: -->
  <div class="absolute top-[40%] left-0 w-full h-[2px] bg-gradient-to-r from-transparent via-primary to-transparent shadow-[0_0_10px_rgba(107,56,212,0.8)]"></div>
  <!-- AI Detect badge: bg-white/80 backdrop-blur-md rounded-full, secondary icon, label-caps text -->
</div>
```

**Found It Card (bottom glass):**
`bg-white/75 backdrop-blur-3xl border-[1px] border-white/60 rounded-xl p-6 shadow-[0_20px_40px_rgba(139,92,246,0.15)]`

Header: `check_circle` icon (text-primary, FILL 1) + "Found It!" in `font-headline-md font-bold tracking-tight`

Product row: `bg-white/40 p-3 rounded-[1.5rem] border border-white/30` with thumbnail image + category label (text-secondary) + product name (font-bold) + brand/material (text-on-surface-variant)

CTA: Primary pill "Save to Vault" with `Guitar` icon

---

## 12. Icon System

All icons use **Material Symbols Outlined** from Google Fonts.

**Default icon style (outlined):**
```css
font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
```

**Filled icon style (active/accent states):**
```css
font-variation-settings: 'FILL' 1;
```

### Icon Usage Reference

| Context | Icon Name | Fill | Color |
|---|---|---|---|
| Email input | `mail` | 0 | `text-outline` |
| Password input | `lock` | 0 | `text-outline-variant` |
| New password | `password` | 1 | `text-primary` |
| Password reset | `lock_reset` | 1 | `text-primary` |
| Visibility toggle | `visibility_off` | 0 | `text-outline-variant` |
| Back button | `arrow_back` | 0 | `text-primary` or `text-on-surface` |
| CTA arrow | `arrow_forward` | 0 | inherits button text color |
| Send (chat) | `arrow_upward` | 1 | `text-on-primary` |
| OTP lock | `lock_open` | 1 | `text-primary` |
| Email verified | `mark_email_read` | 1 | `text-primary` |
| Check/verified | `check_circle` | 1 | `text-primary` |
| Selection checkmark | `check` | 1 | `text-on-primary` |
| Menu | `menu` | 0 | `text-primary` |
| Person/profile | `person` | 0/1 | `text-on-surface-variant` / `text-primary` (active) |
| Account settings | `person` | 0 | `text-outline` |
| Privacy | `lock` | 0 | `text-outline` |
| Notifications | `notifications` | 1 | `text-primary` |
| Log out | `logout` | 0 | `text-error` |
| Chevron right | `chevron_right` | 0 | `text-outline` |
| AI match badge | `auto_awesome` | 1 | `text-primary` |
| Chat FAB | `chat_bubble` | 1 | `text-white` |
| Photo upload (chat) | `add_photo_alternate` | 0 | `text-primary` |
| Try-On nav | `checkroom` | 0/1 | inactive/active |
| AI Styles nav | `auto_awesome` | 0/1 | inactive/active |
| Home nav | `home` | 0/1 | inactive/active |
| Vault nav | `Guitar` | 0/1 | inactive/active (NOTE: unusual icon) |
| Scan | `qr_code_scanner` | 1 | `text-primary` |
| Height | `height` | 0 | `text-primary` |
| Weight | `monitor_weight` | 0 | `text-secondary` |
| Diamond (luxury chip) | `diamond` | 0 | inherits |
| Close/dismiss | `close` | 0 | `text-on-surface-variant` |

---

## 13. Special Effects & Reusable Patterns

### Text Gradient (Quote on glass)
```html
<p class="font-quote-vibrant text-quote-vibrant text-transparent bg-clip-text bg-gradient-to-br from-primary to-secondary-container">
  "Your fit, your future."
</p>
```

### Match/Score Badge
```html
<div class="bg-surface/80 backdrop-blur-md px-4 py-1.5 rounded-full text-primary font-label-caps text-[10px] border border-white/60 tracking-widest flex items-center gap-1 shadow-[0_4px_12px_rgba(0,0,0,0.05)]">
  <span class="material-symbols-outlined text-[14px]" style="font-variation-settings: 'FILL' 1;">auto_awesome</span>
  94% MATCH
</div>
```

### Image Hover Scale (Cards)
All fashion image cards use: `group-hover:scale-105 transition-transform duration-700 ease-out`

### Progress Steps (Onboarding)
Active step: `h-2 w-10 bg-secondary rounded-full shadow-[0_0_12px_rgba(180,19,109,0.5)]`
Inactive step: `h-2 w-2 bg-surface-variant rounded-full`

### Shimmer Button Hover
```html
<div class="absolute inset-0 bg-white/20 translate-y-full group-hover:translate-y-0 transition-transform duration-300 ease-out"></div>
```

### Glass Card Category Label
Positioned at bottom of image card:
```html
<span class="inline-block px-3 py-1 bg-surface-container/80 backdrop-blur-md rounded-full font-label-caps text-label-caps text-primary mb-2">
  Street Style
</span>
```

### Divider in Form Cards
```html
<div class="relative flex py-6 items-center">
  <div class="flex-grow border-t border-outline-variant/50"></div>
  <span class="flex-shrink-0 mx-4 font-body-md text-body-md text-on-surface-variant text-sm">Or continue with</span>
  <div class="flex-grow border-t border-outline-variant/50"></div>
</div>
```

### Hide Scrollbar (Horizontal scroll containers)
```css
.no-scrollbar::-webkit-scrollbar { display: none; }
.no-scrollbar { -ms-overflow-style: none; scrollbar-width: none; }
```

### Text Selection Color
```html
<body class="selection:bg-primary-fixed selection:text-on-primary-fixed">
```
Or pink variant: `selection:bg-secondary-fixed selection:text-on-secondary-fixed`

---

## 14. Body / Page Level Defaults

Every screen:
```html
<body class="bg-background text-on-background min-h-screen antialiased font-body-md text-body-md">
```

Minimum height override:
```css
body { min-height: max(884px, 100dvh); }
```

Text selection (default): `selection:bg-primary-fixed selection:text-on-primary-fixed`

---

## 15. Responsive Breakpoints

The app is mobile-first. Key breakpoints:
- `md:` (768px) — tablet/desktop adjustments
- Most content is capped at `max-w-md` (448px) or `max-w-lg` (512px)
- BottomNavBar: `md:hidden` (hidden on desktop)
- TopAppBar on Vault screen: `hidden md:flex`
- Grid adjustments: `grid-cols-2 md:grid-cols-3 lg:grid-cols-4`

---

## 16. Animation & Transition Standards

| Interaction | Class |
|---|---|
| Button press scale | `active:scale-[0.98]` or `active:scale-95` |
| Button hover opacity | `hover:opacity-90` |
| Button hover scale up | `hover:scale-[1.02]` |
| Icon hover translate (arrow) | `group-hover:translate-x-1 transition-transform duration-200` |
| Icon hover scale | `group-hover:scale-110 transition-transform` |
| Chevron hover translate | `group-hover:translate-x-1` |
| Image zoom on hover | `group-hover:scale-105 transition-transform duration-700` |
| Card lift on hover | `hover:scale-[1.01] duration-300` |
| All transitions default | `transition-all duration-200` or `transition-colors` |
| Shimmer on button hover | `translate-y-full group-hover:translate-y-0 transition-transform duration-300 ease-out` |
| Nav active scale | `scale-110 duration-300 ease-out` |

---

## 17. Z-Index Layers

| Layer | z-index | Elements |
|---|---|---|
| Background (orbs, image) | `z-0` | Ambient glows, hero photos |
| Content | `z-10` | Main page content |
| Chat input | `z-40` | Fixed chat bar |
| FAB | `z-40` | Floating action button |
| TopAppBar | `z-50` | Fixed header |
| BottomNavBar | `z-50` | Fixed nav |