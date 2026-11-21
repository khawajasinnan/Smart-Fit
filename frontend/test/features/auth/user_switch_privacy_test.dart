import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/features/scoring/providers/look_score_provider.dart';
import 'package:smartfit/features/tryon/data/tryon_api_service.dart';
import 'package:smartfit/features/tryon/data/tryon_models.dart';
import 'package:smartfit/features/tryon/providers/tryon_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../helpers/fake_auth_repository.dart';

/// Found 18 Nov 2026: the try-on state was app-wide, so after one person
/// logged out and another logged in on the same phone, the second saw the
/// first person's body photos. Per-account state now resets on a user change.
void main() {
  test("a new sign-in never sees the previous user's try-on photos or chosen hairstyle", () {
    final user = StateProvider<User?>((ref) => FakeAuthRepository.fakeUser(id: 'user-a'));
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(user)),
      tryOnApiServiceProvider.overrideWithValue(TryOnApiService(Dio())),
    ]);
    addTearDown(container.dispose);

    container.read(tryOnControllerProvider.notifier).setPhoto(TryOnAngle.front, Uint8List.fromList([1, 2, 3]));
    container.read(chosenHairstyleProvider.notifier).state =
        const ChosenHairstyle(id: 'm-1', name: 'Side-swept quiff', score: 0.8, faceShape: 'Oval');
    expect(container.read(tryOnControllerProvider).photos, isNotEmpty);

    container.read(user.notifier).state = null; // sign-out
    expect(container.read(tryOnControllerProvider).photos, isEmpty);
    expect(container.read(chosenHairstyleProvider), isNull);

    container.read(tryOnControllerProvider.notifier).setPhoto(TryOnAngle.front, Uint8List.fromList([9]));
    container.read(user.notifier).state = FakeAuthRepository.fakeUser(id: 'user-b'); // someone else signs in
    expect(container.read(tryOnControllerProvider).photos, isEmpty);
  });

  test('a token refresh for the same user keeps the photos', () {
    final user = StateProvider<User?>((ref) => FakeAuthRepository.fakeUser(id: 'user-a'));
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(user)),
      tryOnApiServiceProvider.overrideWithValue(TryOnApiService(Dio())),
    ]);
    addTearDown(container.dispose);
    container.read(tryOnControllerProvider.notifier).setPhoto(TryOnAngle.front, Uint8List.fromList([1]));
    container.read(user.notifier).state = FakeAuthRepository.fakeUser(id: 'user-a'); // new User object, same id
    expect(container.read(tryOnControllerProvider).photos, isNotEmpty);
  });
}
