/// Remote editorial imagery used across the app (Unsplash, hotlinked).
///
/// Keep every image URL here so screens never hard-code them, and so broken
/// links can be fixed in one place. Each was checked to return HTTP 200.
/// Screens must always render these through `SafeNetworkImage`, which shows a
/// branded fallback if a photo fails to load.
abstract final class AppImages {
  static const String _base = 'https://images.unsplash.com';

  static String _photo(String id, {int width = 800}) =>
      '$_base/$id?q=80&w=$width&auto=format&fit=crop';

  /// Phone-resolution 9:16 crop, framed on faces, for full-bleed screens.
  static String _portrait(String id) =>
      '$_base/$id?q=75&w=1080&h=1920&auto=format&fit=crop&crop=faces,center';

  /// Full-body street-style outfit — Virtual Try-On feature card.
  static final String tryOnHero = _photo('photo-1515886657613-9f3515b0c78f');

  /// Hair-focused portrait — AI Hairstyle feature card.
  static final String hairstyleHero = _photo('photo-1524504388940-b1c1722653e1');

  /// Violet-lit portrait (matches the brand palette) — AI Stylist.
  static final String stylistHero = _photo('photo-1534528741775-53994a69daeb');

  /// Shopping-bags editorial — wardrobe / saved looks.
  static final String shoppingHero = _photo('photo-1483985988355-763728e1935b');

  // Full-bleed versions (onboarding), sharp enough for a whole phone screen.
  // The two portraits keep their own framing at 1200 px wide; the landscape
  // shopping photo gets the face-aware 9:16 crop. Checked to return 200.
  static final String stylistFullBleed = _photo('photo-1534528741775-53994a69daeb', width: 1200);
  static final String tryOnFullBleed = _photo('photo-1515886657613-9f3515b0c78f', width: 1200);
  static final String shoppingFullBleed = _portrait('photo-1483985988355-763728e1935b');
}
