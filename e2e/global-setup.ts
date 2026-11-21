import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/** Fails fast if the web build is incomplete (seen 20 Nov 2026: assets missing after mixing
 * `flutter test` and `flutter build web`; fix: `flutter clean` then build again). */
export default function globalSetup() {
  const manifest = fileURLToPath(new URL('../frontend/build/web/assets/FontManifest.json', import.meta.url));
  if (!existsSync(manifest)) {
    throw new Error('frontend/build/web is missing its assets. Run in frontend/: flutter clean; flutter pub get; '
      + 'flutter build web --release --dart-define-from-file=env/dev.json --dart-define=E2E=true');
  }
}
