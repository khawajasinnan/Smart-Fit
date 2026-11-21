/// Save an image the app made (e.g. a virtual try-on) for the user:
/// a normal file download in the browser, the photo gallery on Android / iOS.
library;

export 'image_saver_io.dart' if (dart.library.js_interop) 'image_saver_web.dart';

/// Why saving failed, in words the user can act on.
class SaveImageException implements Exception {
  const SaveImageException(this.message);

  final String message;

  @override
  String toString() => message;
}
