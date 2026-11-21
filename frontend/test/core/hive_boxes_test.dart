import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:smartfit/core/utils/hive_boxes.dart';

/// deleteLocalBox (account deletion, legacy cache clean-up): the box is closed before it is
/// deleted. On the web a plain delete of an open box never finished (E2E run, 20 Nov 2026).
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_boxes_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('an open box is closed and its data deleted', () async {
    final box = await Hive.openBox<String>('smartfit_taste_u1');
    await box.put('liked', 'blue');
    await deleteLocalBox('smartfit_taste_u1');
    expect(Hive.isBoxOpen('smartfit_taste_u1'), isFalse);
    expect(await Hive.boxExists('smartfit_taste_u1'), isFalse);
  });

  test('a closed box is deleted too', () async {
    final box = await Hive.openBox<String>('smartfit_wardrobe_u1');
    await box.put('item', '{}');
    await box.close();
    await deleteLocalBox('smartfit_wardrobe_u1');
    expect(await Hive.boxExists('smartfit_wardrobe_u1'), isFalse);
  });

  test('a box that never existed is no error', () async {
    await deleteLocalBox('smartfit_loved_fits_nobody');
    expect(await Hive.boxExists('smartfit_loved_fits_nobody'), isFalse);
  });
}
