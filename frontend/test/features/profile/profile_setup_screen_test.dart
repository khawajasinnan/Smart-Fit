import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/router/route_paths.dart';
import 'package:smartfit/core/theme/app_theme.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/profile/screens/profile_setup_screen.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

const _photo = 'https://example.com/avatars/user-1.jpg';

/// Just a photo: everything else still to fill in (first-time setup).
const _partial = UserProfileModel(id: 'user-1', photoUrl: _photo);

const _complete = UserProfileModel(
  id: 'user-1',
  fullName: 'Sara Khan',
  gender: 'Female',
  phone: '+923001234567',
  ethnicity: 'Punjabi',
  photoUrl: _photo,
  bodyType: 'Curvy',
  heightCm: 165,
  weightKg: 60,
  chestCm: 88,
  waistCm: 70,
  hipCm: 98,
  skinTone: 'Olive',
  stylePreferences: ['Casual'],
  profileCompleted: true,
);

/// [editing]: pushed on top of a Profile stub (as from Settings); otherwise
/// opened directly, as the onboarding gate does.
Future<void> _pump(WidgetTester tester, FakeProfileRepository profiles, FakeAuthRepository auth,
    {bool editing = false, bool viaOAuth = false}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SafeNetworkImage.debugImageProviderOverride = (_) => MemoryImage(Uint8List(0));
  addTearDown(() => SafeNetworkImage.debugImageProviderOverride = null);

  final router = GoRouter(
    initialLocation: editing ? RoutePaths.profile : RoutePaths.profileSetup,
    routes: [
      GoRoute(path: RoutePaths.profile, builder: (_, _) => const Scaffold(body: Text('stub:profile'))),
      GoRoute(path: RoutePaths.home, builder: (_, _) => const Scaffold(body: Text('stub:home'))),
      GoRoute(path: RoutePaths.profileSetup, builder: (_, _) => const ProfileSetupScreen()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(FakeAuthRepository.fakeUser(viaOAuth: viaOAuth)),
        profileRepositoryProvider.overrideWithValue(profiles),
        authRepositoryProvider.overrideWithValue(auth),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  if (editing) router.push(RoutePaths.profileSetup);
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _tapChoice(WidgetTester tester, String semanticsLabel) async {
  final f = find.bySemanticsLabel(semanticsLabel);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first-time setup: basics → body → style → celebration → home', (tester) async {
    final profiles = FakeProfileRepository(loads: [_partial]);
    final auth = FakeAuthRepository();
    await _pump(tester, profiles, auth);

    expect(find.text("Let's get to know you"), findsOneWidget);
    await _tapButton(tester, 'Continue');
    expect(find.text('Please select your gender.'), findsOneWidget);

    await _tapChoice(tester, 'Female');
    expect(find.text('Please select your gender.'), findsNothing); // fixing it clears the error
    await tester.enterText(find.byType(TextFormField), '0300 1234567'.replaceAll(' ', ''));
    await _tapChoice(tester, 'Sindhi');
    await _tapButton(tester, 'Continue');

    expect(find.text('Your shape & size'), findsOneWidget);
    // a woman sees the women's shapes (21 Nov 2026), nothing pre-selected
    expect(find.bySemanticsLabel('Hourglass body type'), findsOneWidget);
    expect(find.bySemanticsLabel('Trapezoid body type'), findsNothing);
    await _tapButton(tester, 'Continue');
    expect(find.text('Please select your body shape.'), findsOneWidget);
    await _tapChoice(tester, 'Pear body type');
    final xl = find.widgetWithText(ChoiceChip, 'XL');
    await tester.ensureVisible(xl);
    await tester.tap(xl);
    await tester.pumpAndSettle();
    await _tapButton(tester, 'Continue');

    expect(find.text('Your style DNA'), findsOneWidget);
    await _tapButton(tester, 'Finish');
    expect(find.text('Please pick at least one style preference.'), findsOneWidget);

    await _tapChoice(tester, 'Dark skin tone');
    final warm = find.widgetWithText(ChoiceChip, 'Warm');
    await tester.ensureVisible(warm);
    await tester.tap(warm);
    await tester.pumpAndSettle();
    await _tapChoice(tester, 'Streetwear');
    await _tapChoice(tester, 'Lawn Suit');
    await _tapButton(tester, 'Finish');

    final saved = profiles.saved.single;
    expect(saved.gender, 'Female');
    expect(saved.phone, '+923001234567');
    expect(saved.ethnicity, 'Sindhi');
    expect(saved.bodyType, 'Pear');
    expect(saved.usualSize, 'XL');
    expect(saved.skinTone, 'Dark');
    expect(saved.skinUndertone, 'warm');
    expect(saved.stylePreferences, ['Streetwear', 'Lawn Suit']);
    expect(saved.photoUrl, _photo);
    expect(saved.profileCompleted, isTrue);
    expect(auth.metadata, {'phone': '+923001234567', 'avatar_url': _photo});

    expect(find.text("You're all set, Sara!"), findsOneWidget);
    await _tapButton(tester, 'Start exploring');
    expect(find.text('stub:home'), findsOneWidget);
  });

  testWidgets('a Google sign-up must give a date of birth, 15+ (SFR-001)', (tester) async {
    final profiles = FakeProfileRepository(loads: [_partial]);
    await _pump(tester, profiles, FakeAuthRepository(), viaOAuth: true);

    expect(find.text('Date of birth'), findsOneWidget);
    await _tapButton(tester, 'Continue');
    expect(find.text(AppStrings.dobRequired), findsOneWidget);

    // too young: 10 years old today
    await _tapChoice(tester, 'Choose your date of birth');
    final now = DateTime.now();
    await tester.tap(find.byTooltip('Switch to input')); // type the date instead of scrolling the calendar
    await tester.pumpAndSettle();
    final young = DateTime(now.year - 10, 1, 1);
    await tester.enterText(find.byType(TextField).last,
        '${young.month.toString().padLeft(2, '0')}/${young.day.toString().padLeft(2, '0')}/${young.year}');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.mustBe15), findsOneWidget);

    // 20 years old: accepted, the next problem is the gender
    final change = find.bySemanticsLabel(RegExp('Date of birth .* Tap to change'));
    await tester.ensureVisible(change);
    await tester.tap(change);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '05/14/${now.year - 20}');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _tapButton(tester, 'Continue');
    expect(find.text('Please select your gender.'), findsOneWidget);
  });

  testWidgets('an email sign-up is not asked again for its date of birth', (tester) async {
    await _pump(tester, FakeProfileRepository(loads: [_partial]), FakeAuthRepository());
    expect(find.text('Date of birth'), findsNothing);
  });

  testWidgets('an invalid Pakistani number is rejected', (tester) async {
    await _pump(tester, FakeProfileRepository(loads: [_partial]), FakeAuthRepository());
    await _tapChoice(tester, 'Male');
    await tester.enterText(find.byType(TextFormField), '12345');
    await _tapChoice(tester, 'Pathan');
    await _tapButton(tester, 'Continue');
    expect(find.textContaining('valid Pakistani mobile number'), findsOneWidget);
    expect(find.text("Let's get to know you"), findsOneWidget);
  });

  testWidgets('editing: prefilled, saves and returns to the profile tab', (tester) async {
    final profiles = FakeProfileRepository(loads: [_complete]);
    await _pump(tester, profiles, FakeAuthRepository(), editing: true);

    expect(find.byTooltip('Close'), findsOneWidget);
    await _tapButton(tester, 'Continue');
    await _tapButton(tester, 'Continue');
    await _tapButton(tester, 'Save changes');

    expect(profiles.saved.single.bodyType, 'Curvy');
    expect(profiles.saved.single.skinTone, 'Olive');
    expect(find.text('stub:profile'), findsOneWidget);
    expect(find.text('Profile updated'), findsOneWidget);
  });

  testWidgets('back returns to the previous step', (tester) async {
    await _pump(tester, FakeProfileRepository(loads: [_complete]), FakeAuthRepository(), editing: true);
    await _tapButton(tester, 'Continue');
    expect(find.text('Your shape & size'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text("Let's get to know you"), findsOneWidget);
  });

  testWidgets('a failed save shows an error and stays on the screen', (tester) async {
    final profiles = FakeProfileRepository(loads: [_complete], saveError: Exception('offline'));
    await _pump(tester, profiles, FakeAuthRepository(), editing: true);
    await _tapButton(tester, 'Continue');
    await _tapButton(tester, 'Continue');
    await _tapButton(tester, 'Save changes');
    expect(find.text("Couldn't save your profile. Check your connection and try again."), findsOneWidget);
    expect(find.text('Your style DNA'), findsOneWidget);
  });
}
