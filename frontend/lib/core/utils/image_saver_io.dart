import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:smartfit/core/utils/image_saver.dart';

/// Android / iOS: into the photo gallery, in a "SmartFit" album.
/// [fileName] without extension, e.g. "smartfit-tryon-front".
Future<void> saveImageBytes(Uint8List bytes, String fileName) async {
  try {
    if (!await Gal.hasPermission(toAlbum: true) && !await Gal.requestPermission(toAlbum: true)) {
      throw const SaveImageException('Allow SmartFit to add photos in your phone settings, then try again.');
    }
    await Gal.putImageBytes(bytes, album: 'SmartFit', name: fileName);
  } on GalException catch (e) {
    throw SaveImageException(switch (e.type) {
      GalExceptionType.permissionDenied => 'Allow SmartFit to add photos in your phone settings, then try again.',
      GalExceptionType.notEnoughSpace => 'Your phone is out of storage space.',
      _ => "Couldn't save the image. Please try again.",
    });
  }
}

/// Where the image ends up, for the confirmation message.
const savedImageLocation = 'your gallery (SmartFit album)';
