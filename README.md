# SmartFit

SmartFit is a Flutter and Supabase mobile app for AI-assisted fashion recommendations in Pakistan. It supports email authentication, mandatory profile setup, AI stylist chat, photo-based outfit discussion, voice input, and profile-aware styling suggestions.

## Current Stack

- Flutter + Dart
- Riverpod for state management
- GoRouter for navigation
- Supabase Auth, PostgreSQL, and Storage
- Gemini REST API for AI stylist responses
- Camera, image picker, and speech-to-text for chat/profile inputs

## Project Architecture

```text
lib/
├── app.dart
├── main.dart
├── core/
│   ├── constants/      App colors, strings, text styles, API endpoints
│   ├── providers/      Shared app providers
│   ├── router/         GoRouter routes
│   ├── theme/          Light and dark theme setup
│   ├── utils/          Validation helpers
│   └── widgets/        Shared UI widgets
└── features/
    ├── auth/           Login, registration, password recovery, auth provider
    ├── chat/           AI stylist chat, image upload, voice input, history
    ├── home/           Home dashboard
    ├── profile/        Profile setup, profile gate, profile repository
    └── settings/       Settings and logout
```

Platform folders (`android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`) are standard Flutter build targets and should stay in the project.

## Important Files

- `.gitignore` is located at `/home/sinnan/Desktop/Smart-Fit/smartfit/.gitignore`
- Supabase schema setup: `supabase_setup.sql`
- Project guide and roadmap: `claude.md`
- Design references: `design.md`, `stitch_designs/`, `stitch_screens/`

## Setup

1. Install Flutter and run:

```bash
flutter pub get
```

2. Configure Supabase values in:

```text
lib/core/constants/api_endpoints.dart
```

3. Apply the Supabase schema from:

```text
supabase_setup.sql
```

4. Run the app:

```bash
flutter run
```

## Verification

Use these commands before pushing changes:

```bash
flutter analyze
flutter test
```

## Notes

- Do not expose Supabase service-role keys in Flutter.
- Keep profile completion enforced before giving users access to main app features.
