# CLAUDE.md — SmartFit Project Guide

## Project Overview

**SmartFit** is an AI-powered mobile fashion application built for the Pakistani e-commerce market. It provides users with a virtual try-on experience for clothing outfits and AI-suggested hairstyle recommendations in a single unified platform.

**Tech Stack:**
- **Frontend:** Flutter + Dart (mobile: iOS & Android)
- **Backend:** FastAPI + Python (AI model serving)
- **Database & Auth:** Supabase (PostgreSQL + Auth)
- **Infrastructure:** Docker + Kubernetes on AWS
- **AI Models:** Computer Vision (body feature extraction), Diffusion Models (virtual try-on), Pose Estimation
- **Scraping:** Python-based web scraper targeting Outfitters, Breakout, and similar Pakistani retailers

---

## Class Diagram Reference (Figure 5.3)

The system consists of the following core classes and their relationships:

| Class | Key Attributes | Key Methods |
|---|---|---|
| `User` | userID, name, email, isVerified, passwordHash | register(), login(), updateAccount() |
| `Admin` | adminID, role | manageUserAccounts(), monitorActivities(), viewSystemAnalytics() |
| `UserProfile` | profileID, gender, height, weight, clothes preferences, style preferences, sizing information | createProfile(), getStats() |
| `WardrobeSession` | wardrobeID, sessionID, sessionScore, savedDate | saveSession(), browseHistory() |
| `AIStylistChatbot` | sessionID, occasion, mood, cameraCapture, timestamp | startSession(), getSessionInputs() |
| `RecommendationEngine` | styleVector, occasion, mood, matrixThreshold | buildStyleVector(), scoreOutfit(), rankRecommendations() |
| `CVAnalysisService` | analysisID, inputImageURL, bodyMeasurements, detectedBodyType, poseVector | runPoseEstimation(), extractBodyMeasurements() |
| `VirtualTryOn` | tryOnID, userPoseURL, productImageURL, generatedImageURL, overlayBlob | generateTryOnImage(), getOverlayMask(), displayVisualization() |
| `HairstylePreview` | hairstyleID, hairstyleName, overlayImageURL, blendRatio | generatePreview(), getStyleVariants() |
| `ScoringEngine` | scoreID, outfitScore, styleScore, eventFitness, explainText | computeScore(), generateStyleHints() |
| `SavedItem` | saveID, productID | buyNow() |
| `ScraperService` | productID, brand, size, imageURL, price | checkAvailability(), redirectToBrand() |
| `Feedback` | feedbackID, rating, comment, suggestion, submittedAt | submitFeedback(), collectInsights() |

**Key Relationships:**
- `User` owns `WardrobeSession` (1 to many)
- `User` owns `UserProfile` (1 to 1)
- `User` initiates `AIStylistChatbot` sessions
- `AIStylistChatbot` feeds input to `RecommendationEngine`
- `UserProfile` provides static inputs to `RecommendationEngine`
- `RecommendationEngine` feeds analysis to `CVAnalysisService`
- `CVAnalysisService` enables `VirtualTryOn`
- `CVAnalysisService` uses `VirtualTryOn`
- `VirtualTryOn` enables `HairstylePreview`
- `WardrobeSession` scored by `ScoringEngine` and `HairstylePreview`
- `ScraperService` gets `SavedItem`; `RecommendationEngine` produces `SavedItem`
- `User` tries `Feedback`; `Feedback` reviewed in `ScoringEngine`
- `Admin` inherits from `User`; `Admin` gives access

---

## Full Functional Requirements Index

### SFR-001 to SFR-008 — User Account Management
### SFR-009 to SFR-013 — User Profile and Onboarding
### SFR-014 to SFR-021 — AI Chatbot and Dynamic Input Collection
### SFR-022 to SFR-028 — Product Scraping, Recommendation, and Virtual Try-On
### SFR-029 to SFR-034 — Hairstyle Recommendation and Scoring
### SFR-035 to SFR-038 — Wardrobe and History
### SFR-039 to SFR-042 — Admin Panel

---

## 30% Project Scope Definition

The 30% deliverable covers the complete **Authentication & User Foundation** layer, which is the mandatory prerequisite for all other features. Despite being "authentication," this scope is architecturally rich and includes full account management, complete profile onboarding, the entire Supabase backend foundation, and the Flutter app shell.

### What the 30% Covers

| # | Module | Requirements Covered |
|---|---|---|
| 1 | User Registration & Email Verification | SFR-001, SFR-002, SFR-003 |
| 2 | OAuth Integration (Google / Facebook) | SFR-001, SFR-004 |
| 3 | User Login & Session Management | SFR-004 |
| 4 | Password Recovery | SFR-005 |
| 5 | Mandatory Profile Completion Gate | SFR-006, SFR-013 |
| 6 | Profile Management (view/edit) | SFR-007 |
| 7 | Account Deactivation / Deletion | SFR-008 |
| 8 | Profile Photo Upload (gallery/camera) | SFR-009 |
| 9 | Gender Selection | SFR-010 |
| 10 | Body Measurement Input | SFR-011 |
| 11 | Skin Tone Selection | SFR-012 |
| 12 | Admin Role + Account Management | SFR-039 (partial) |
| 13 | Flutter App Shell + Navigation | Infrastructure |
| 14 | Supabase Schema + Database Setup | Infrastructure |

### What the 30% Does NOT Cover (Remaining 70%)
- AI Chatbot sessions (SFR-014 to SFR-021)
- Web scraping pipeline (SFR-022 to SFR-025)
- Virtual Try-On generation (SFR-026 to SFR-028)
- Hairstyle recommendations (SFR-029 to SFR-031)
- Scoring engine (SFR-032, SFR-033)
- Feedback system (SFR-034)
- Wardrobe and history (SFR-035 to SFR-038)
- Full Admin dashboard analytics (SFR-040, SFR-041, SFR-042)
- CV Analysis / body feature extraction
- Recommendation engine
- Diffusion model integration

---

## Phase Breakdown for 30% Deliverable

---

### Phase 1 — Project Foundation & Infrastructure Setup

**Goal:** Set up the entire project scaffold, Supabase backend, Flutter app shell, and CI/CD basics.

**Duration:** ~1 week

#### 1.1 Supabase Setup
- Create Supabase project (production + staging environments)
- Define database schema:

```sql
-- Users table (extends Supabase auth.users)
CREATE TABLE public.users (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  is_verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- User profiles table
CREATE TABLE public.user_profiles (
  profile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE REFERENCES public.users(user_id) ON DELETE CASCADE,
  gender TEXT,
  height FLOAT,
  weight FLOAT,
  chest FLOAT,
  waist FLOAT,
  hip FLOAT,
  skin_tone TEXT,
  clothes_preferences TEXT[],
  style_preferences TEXT[],
  sizing_information TEXT[],
  profile_photo_url TEXT,
  is_complete BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Admin roles table
CREATE TABLE public.admins (
  admin_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE REFERENCES public.users(user_id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'admin',
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

- Enable Row Level Security (RLS) on all tables
- Write RLS policies (users can only read/write their own data)
- Set up Supabase Storage bucket for profile photos (`profile-photos` bucket, private)
- Configure email templates for verification and password reset

#### 1.2 Flutter Project Setup
- Initialize Flutter project: `flutter create smartfit`
- Add dependencies to `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.x
  go_router: ^13.x
  flutter_riverpod: ^2.x  # or provider
  image_picker: ^1.x
  cached_network_image: ^3.x
  flutter_svg: ^2.x
  google_sign_in: ^6.x
  flutter_facebook_auth: ^6.x
  shared_preferences: ^2.x
  dio: ^5.x
  freezed_annotation: ^2.x
  json_annotation: ^4.x

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.x
  freezed: ^2.x
  json_serializable: ^6.x
  flutter_lints: ^3.x
```

- Configure folder structure:

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── constants/
│   ├── errors/
│   ├── router/
│   ├── theme/
│   └── utils/
├── features/
│   ├── auth/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   ├── profile/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   └── admin/
│       ├── data/
│       ├── domain/
│       └── presentation/
└── shared/
    ├── widgets/
    └── models/
```

- Set up go_router with route guards (auth-gated routes, profile-completion gate)
- Set up Riverpod providers structure
- Configure Supabase client initialization in `main.dart`

#### 1.3 CI/CD Setup
- Create GitHub repository with `main`, `develop`, and `feature/*` branch strategy
- Add GitHub Actions workflow for Flutter test + build on PR
- Connect Supabase CLI for database migrations versioning

**Deliverables:**
- [ ] Supabase project live with schema and RLS
- [ ] Flutter project runs on emulator with correct folder structure
- [ ] go_router routes defined (unauthenticated shell)
- [ ] GitHub Actions pipeline runs on push

---

### Phase 2 — Authentication Module (SFR-001 to SFR-005)

**Goal:** Implement complete user registration, email verification, OAuth login, password recovery, and session management.

**Duration:** ~1.5 weeks

#### 2.1 Registration Screen (SFR-001, SFR-002, SFR-003)

**UI Screens:**
- `RegisterScreen` — fields: Full Name, Email, Password, Confirm Password
- `EmailVerificationPendingScreen` — prompts user to check inbox

**Validation Rules (SFR-001):**
- Email: valid format
- Password: minimum 8 characters, at least 1 uppercase, 1 lowercase, 1 number, 1 special character
- Age: date-of-birth field with validation (minimum age 15 years)
- Confirm Password: must match password (SFR-003)

**Backend logic:**
- Call `supabase.auth.signUp()` with email + password
- Supabase sends verification email automatically (configure email template in Supabase dashboard)
- On successful signup → navigate to `EmailVerificationPendingScreen`
- Poll or listen to auth state change; on email verified → redirect to profile creation (SFR-006)

**Code Pattern:**
```dart
// auth_repository.dart
Future<void> registerWithEmail({
  required String name,
  required String email,
  required String password,
  required DateTime dateOfBirth,
}) async {
  final age = DateTime.now().year - dateOfBirth.year;
  if (age < 15) throw AgeValidationException();
  
  final response = await supabase.auth.signUp(
    email: email,
    password: password,
    data: {'name': name, 'date_of_birth': dateOfBirth.toIso8601String()},
  );
  
  if (response.user == null) throw RegistrationException();
  
  // Insert into public.users table
  await supabase.from('users').insert({
    'user_id': response.user!.id,
    'name': name,
    'email': email,
  });
}
```

#### 2.2 OAuth Login — Google & Facebook (SFR-001, SFR-004)

- Configure Google Sign-In in Supabase dashboard (add OAuth credentials)
- Configure Facebook Login in Supabase dashboard
- Add `google_sign_in` and `flutter_facebook_auth` packages
- OAuth users are pre-verified; on first login → check if profile is complete → if not, redirect to profile creation

**Code Pattern:**
```dart
Future<void> signInWithGoogle() async {
  await supabase.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: 'io.smartfit://login-callback',
  );
}
```

#### 2.3 Login Screen (SFR-004)

**UI Screen:** `LoginScreen`
- Email + Password fields
- "Login with Google" button
- "Login with Facebook" button
- "Forgot Password?" link
- "Create Account" link

**Logic:**
- `supabase.auth.signInWithPassword()`
- On success: check if user profile `is_complete = true`
  - If true → navigate to Home (placeholder for now)
  - If false → navigate to Profile Creation flow (SFR-006)

#### 2.4 Password Recovery (SFR-005)

**UI Screen:** `ForgotPasswordScreen`
- Email input field
- "Send Reset Link" button

**Logic:**
- `supabase.auth.resetPasswordForEmail(email)`
- Show confirmation message
- Supabase handles the reset email automatically

**UI Screen:** `ResetPasswordScreen` (deep link handler)
- New password + confirm password fields
- Calls `supabase.auth.updateUser(password: newPassword)`

#### 2.5 Session Management & Auth State

- Set up global auth state listener using Riverpod:

```dart
// auth_provider.dart
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});
```

- Route guard in go_router: redirect unauthenticated users to `/login`
- Persist session automatically (Supabase Flutter SDK handles this via secure storage)
- Handle token refresh transparently

**Deliverables:**
- [ ] Registration with validation working end-to-end
- [ ] Email verification flow working
- [ ] Google OAuth working
- [ ] Facebook OAuth working
- [ ] Login with email/password working
- [ ] Password reset email flow working
- [ ] Auth state persists across app restarts
- [ ] Route guards active

---

### Phase 3 — Profile Creation & Onboarding (SFR-006 to SFR-013)

**Goal:** Implement the mandatory profile completion gate and all profile input screens. No core features accessible until profile is complete.

**Duration:** ~1.5 weeks

#### 3.1 Profile Completion Gate (SFR-006, SFR-013)

- After any login (email or OAuth), check `user_profiles.is_complete` for the authenticated user
- If `is_complete = false` → force navigate to `ProfileCreationFlow` (cannot go back or skip)
- If `is_complete = true` → navigate to `HomeScreen` (placeholder screen for 30% scope)
- Implement as a route guard in go_router:

```dart
redirect: (context, state) {
  final isAuthenticated = ref.read(authStateProvider).value?.session != null;
  final isProfileComplete = ref.read(profileCompleteProvider);
  
  if (!isAuthenticated) return '/login';
  if (isAuthenticated && !isProfileComplete) return '/profile-setup';
  return null;
}
```

#### 3.2 Profile Photo Upload (SFR-009)

**UI:** `ProfilePhotoScreen`
- Two options: "Upload from Gallery" or "Take Photo"
- Preview the selected image before confirming
- Image cropper (square crop for profile photo)

**Logic:**
- Use `image_picker` package for gallery and camera
- Upload to Supabase Storage: `profile-photos/{user_id}/profile.jpg`
- Store public URL in `user_profiles.profile_photo_url`
- Apply size limit: max 5MB; compress if larger

```dart
Future<String> uploadProfilePhoto(File imageFile, String userId) async {
  final bytes = await imageFile.readAsBytes();
  final filePath = '$userId/profile.jpg';
  
  await supabase.storage
    .from('profile-photos')
    .uploadBinary(filePath, bytes, fileOptions: const FileOptions(upsert: true));
    
  return supabase.storage.from('profile-photos').getPublicUrl(filePath);
}
```

#### 3.3 Gender Selection (SFR-010)

**UI:** `GenderSelectionScreen`
- Visual gender selection cards: Male / Female / Non-binary / Prefer not to say
- Single select; required field
- Store in `user_profiles.gender`

#### 3.4 Body Measurements Input (SFR-011)

**UI:** `BodyMeasurementsScreen`
- Input fields: Height (cm), Weight (kg), Chest (cm), Waist (cm), Hip (cm)
- Toggle for cm/inches (convert and store in cm)
- Optional helper: diagram showing where to measure
- All fields required (validation before proceeding)
- Store in `user_profiles` (height, weight, chest, waist, hip columns)

#### 3.5 Skin Tone Selection (SFR-012)

**UI:** `SkinToneSelectionScreen`
- Visual palette with 6–8 predefined skin tone swatches (using Fitzpatrick scale or similar)
- Tap to select; selected swatch highlighted with checkmark
- Store selection label in `user_profiles.skin_tone`

#### 3.6 Clothing & Style Preferences (from UserProfile class)

**UI:** `PreferencesScreen`
- Chips/multi-select for clothing preferences: Casual, Formal, Ethnic, Streetwear, Sporty, etc.
- Chips/multi-select for style preferences: Minimalist, Bold, Classic, Trendy, etc.
- Store in `user_profiles.clothes_preferences[]` and `style_preferences[]`

#### 3.7 Profile Completion Submit

- After all steps completed, set `user_profiles.is_complete = true`
- Navigate to `HomeScreen` (placeholder)
- Show success animation/toast

#### 3.8 Profile Management — View & Edit (SFR-007)

**UI:** `ProfileScreen` (accessible from app settings after onboarding)
- Display all profile fields with current values
- Edit button per section or single "Edit Profile" flow
- Re-upload profile photo
- Update measurements, skin tone, preferences
- All updates persist to Supabase

#### 3.9 Account Deactivation & Deletion (SFR-008)

**UI:** `AccountSettingsScreen`
- "Deactivate Account" — sets a `deactivated_at` timestamp; user cannot log in (enforced via RLS or a flag check on login)
- "Delete Account" — shows confirmation dialog with warning text; calls Supabase admin API to delete `auth.users` record (cascades to all related tables via ON DELETE CASCADE)

**Deliverables:**
- [ ] Profile creation multi-step flow working
- [ ] Photo upload to Supabase Storage working
- [ ] Gender, measurements, skin tone, preferences all saving
- [ ] Profile gate blocking access until complete
- [ ] Profile edit screen working
- [ ] Account deactivation and deletion working

---

### Phase 4 — Admin Foundation (SFR-039 partial)

**Goal:** Build the basic admin role system and user management panel.

**Duration:** ~0.5 weeks

#### 4.1 Admin Role Assignment

- Admins are created by direct database insert into `public.admins` table (no self-registration for admin)
- On login, check if `user_id` exists in `public.admins` table
- If admin → show "Admin Panel" entry in navigation drawer

#### 4.2 Admin User Management Screen

**UI:** `AdminUsersScreen`
- List all users (paginated, 20 per page)
- Search by name or email
- Per user actions:
  - View profile details
  - Suspend account (set `deactivated_at`)
  - Permanently delete account

**Backend:**
- Use Supabase service role key (server-side only; never expose in Flutter app)
- FastAPI endpoint: `POST /admin/users/{user_id}/suspend`
- FastAPI endpoint: `DELETE /admin/users/{user_id}`
- Admin actions authenticated via JWT with admin role claim

#### 4.3 Admin Route Guard

- Separate route guards for admin routes
- Non-admin users attempting to access `/admin/*` routes are redirected to home

**Deliverables:**
- [ ] Admin role detection on login
- [ ] Admin user list screen working
- [ ] Suspend and delete user actions working
- [ ] Admin routes protected

---

### Phase 5 — Integration, Polish & Testing

**Goal:** Wire everything together, fix edge cases, write tests, and prepare for 30% demo.

**Duration:** ~1 week

#### 5.1 End-to-End Flow Testing

Test the complete user journey:

1. New user opens app → sees Login screen
2. Taps "Register" → fills form → submits → sees email verification screen
3. Verifies email → app detects verification → redirects to Profile Setup
4. Completes profile (photo, gender, measurements, skin tone, preferences) → reaches Home placeholder
5. Closes app → reopens → session persists → goes directly to Home
6. Navigates to Profile → edits measurements → saves
7. Navigates to Account Settings → deactivates account → cannot log in
8. Admin logs in → sees Admin Panel → views users → suspends a user

#### 5.2 Edge Case Handling

- Network offline: show appropriate error messages, retry buttons
- Image upload failure: retry logic with user notification
- Supabase auth errors: map error codes to user-friendly messages
- OAuth cancellation: graceful handling (no crash, return to login)
- Session expiry: auto-refresh token; if fails, redirect to login with message
- Duplicate email on registration: display "Email already in use" error

#### 5.3 Unit & Widget Tests

Write tests for:

```
test/
├── features/
│   ├── auth/
│   │   ├── auth_repository_test.dart
│   │   ├── registration_validator_test.dart
│   │   └── login_screen_test.dart (widget test)
│   └── profile/
│       ├── profile_repository_test.dart
│       └── profile_form_validator_test.dart
```

Key test cases:
- Password validation rules (all combinations)
- Age validation (under 15 rejected)
- Confirm password match
- Profile completion gate redirect logic
- Image upload mock

#### 5.4 UI Polish

- Apply consistent design system (colors, typography, spacing) across all screens
- Add loading states (skeleton screens or shimmer) on all async operations
- Add form field animations and error state styling
- Ensure keyboard avoidance on all form screens
- Test on both iOS and Android emulators

#### 5.5 FastAPI Backend Foundation

Even though AI features are not in scope for 30%, set up the FastAPI skeleton that auth-adjacent endpoints will use:

```
backend/
├── main.py
├── core/
│   ├── config.py         # env vars
│   ├── supabase.py       # Supabase client init
│   └── auth.py           # JWT verification middleware
├── routers/
│   ├── auth.py           # /auth/* endpoints if needed
│   └── admin.py          # /admin/* endpoints
├── models/
│   ├── user.py
│   └── profile.py
├── requirements.txt
└── Dockerfile
```

Docker Compose for local dev:
```yaml
version: '3.8'
services:
  api:
    build: ./backend
    ports:
      - "8000:8000"
    env_file: .env
```

**Deliverables:**
- [ ] Full E2E flow tested and working
- [ ] All edge cases handled with user-friendly messages
- [ ] Unit tests passing
- [ ] Widget tests passing
- [ ] UI consistent and polished
- [ ] FastAPI skeleton deployed locally via Docker

---

## Summary: 30% Deliverable Checklist

### Infrastructure
- [ ] Supabase project configured (auth, database, storage, RLS)
- [ ] Flutter project scaffolded with correct architecture
- [ ] go_router with auth guard and profile-completion guard
- [ ] Riverpod state management wired up
- [ ] FastAPI skeleton with Dockerfile
- [ ] GitHub Actions CI pipeline

### Authentication (SFR-001 to SFR-005)
- [ ] Email/password registration with full validation
- [ ] Email verification flow
- [ ] Google OAuth login
- [ ] Facebook OAuth login
- [ ] Email/password login
- [ ] Session persistence across app restarts
- [ ] Password reset via email link

### Profile Onboarding (SFR-006 to SFR-013)
- [ ] Profile completion gate enforced
- [ ] Profile photo upload (gallery + camera)
- [ ] Gender selection
- [ ] Body measurements input (height, weight, chest, waist, hip)
- [ ] Skin tone selection
- [ ] Clothing + style preferences
- [ ] Profile saved and `is_complete = true`
- [ ] Profile edit screen
- [ ] Account deactivation
- [ ] Account deletion

### Admin Foundation (SFR-039 partial)
- [ ] Admin role detection
- [ ] User list with search and pagination
- [ ] Suspend user
- [ ] Delete user
- [ ] Admin route protection

---

## Remaining 70% — High-Level Roadmap (Future Phases)

| Phase | Feature Area | Requirements |
|---|---|---|
| Phase 6 | AI Chatbot Session Interface | SFR-014, SFR-015, SFR-016, SFR-017, SFR-018 |
| Phase 7 | Computer Vision Body Analysis | SFR-019, SFR-020, SFR-021 |
| Phase 8 | Web Scraper + Product Catalog | SFR-022, SFR-023, SFR-024, SFR-025 |
| Phase 9 | Diffusion-Based Virtual Try-On | SFR-026, SFR-027, SFR-028 |
| Phase 10 | Hairstyle Recommendation & Preview | SFR-029, SFR-030, SFR-031 |
| Phase 11 | Scoring Engine + Styling Hints | SFR-032, SFR-033 |
| Phase 12 | User Feedback System | SFR-034 |
| Phase 13 | Wardrobe & Session History | SFR-035, SFR-036, SFR-037, SFR-038 |
| Phase 14 | Full Admin Dashboard & Analytics | SFR-040, SFR-041, SFR-042 |

---

## Important Development Notes

### Never Do
- Never expose Supabase service role key in Flutter app (use only in FastAPI backend)
- Never skip RLS policies (all tables must have RLS enabled)
- Never store plain-text passwords (Supabase auth handles hashing)
- Never allow access to any feature screen if `is_complete = false` on user profile
- Never hardcode API URLs (use environment variables)

### Always Do
- Always validate age (minimum 15 years) during registration
- Always use `upsert: true` when uploading profile photos to Supabase Storage
- Always handle Supabase auth state changes reactively (not one-time checks)
- Always cascade delete (set `ON DELETE CASCADE`) on all foreign keys referencing `auth.users`
- Always compress images before upload (max 5MB enforced)
- Always test OAuth flows on real devices (not just emulators)

### Environment Variables Required
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=      # backend only
GOOGLE_CLIENT_ID=
FACEBOOK_APP_ID=
FACEBOOK_APP_SECRET=
AWS_REGION=
```

### Database Migrations
All schema changes must go through Supabase CLI migrations:
```bash
supabase migration new <migration_name>
supabase db push
```
Never edit the database schema directly in production.