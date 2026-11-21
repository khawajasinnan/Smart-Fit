import 'dart:js_interop';
import 'dart:typed_data';

import 'package:smartfit/core/utils/image_saver.dart';
import 'package:web/web.dart' as web;

/// Browser: a normal file download ([fileName].jpg in the Downloads folder).
Future<void> saveImageBytes(Uint8List bytes, String fileName) async {
  try {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/jpeg'));
    final url = web.URL.createObjectURL(blob);
    final link = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = '$fileName.jpg'
      ..style.display = 'none';
    web.document.body?.append(link);
    link.click();
    link.remove();
    // Give the browser a moment to start the download before the link is freed.
    Future<void>.delayed(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
  } catch (_) {
    throw const SaveImageException("Couldn't download the image. Please try again.");
  }
}

/// Where the image ends up, for the confirmation message.
const savedImageLocation = 'your Downloads folder';
