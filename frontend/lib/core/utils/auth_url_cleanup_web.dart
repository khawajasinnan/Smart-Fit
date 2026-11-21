import 'package:web/web.dart' as web;

import 'auth_callback_url.dart';

/// After Supabase has exchanged the one-time `?code=` from a Google sign-in
/// redirect (Supabase.initialize waits for it), drop it from the address bar:
/// a refresh would otherwise try to use the spent code again.
void clearAuthCallbackFromUrl() {
  final clean = withoutAuthCallbackParams(Uri.base);
  if (clean != null) web.window.history.replaceState(null, '', clean);
}
