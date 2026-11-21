import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartfit/core/constants/app_strings.dart';
import 'package:smartfit/core/utils/validators.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';

void main() {
  group('AuthStateModel.copyWith', () {
    const errored = AuthStateModel(
      status: AuthStatus.error,
      errorMessage: 'Bad password',
      restrictionMessage: 'Banned',
    );

    test('keeps the error unless explicitly cleared (clearError bug)', () {
      expect(errored.copyWith(status: AuthStatus.unauthenticated).errorMessage, 'Bad password');
      final cleared = errored.copyWith(status: AuthStatus.unauthenticated, clearErrorMessage: true);
      expect(cleared.errorMessage, isNull);
      expect(cleared.restrictionMessage, 'Banned');
    });

    test('restriction message clears independently', () {
      expect(errored.copyWith(clearRestrictionMessage: true).restrictionMessage, isNull);
    });
  });

  group('age rule (SFR-001: 15+)', () {
    final now = DateTime(2026, 10, 18);

    test('turns 15 today -> allowed', () {
      expect(Validators.dateOfBirth(DateTime(2011, 10, 18), now: now), isNull);
    });

    test('turns 15 tomorrow -> rejected', () {
      expect(Validators.dateOfBirth(DateTime(2011, 10, 19), now: now), AppStrings.mustBe15);
    });

    test('missing date -> required message', () {
      expect(Validators.dateOfBirth(null, now: now), AppStrings.dobRequired);
    });

    test('ageOn handles leap-day birthdays', () {
      expect(Validators.ageOn(DateTime(2008, 2, 29), DateTime(2023, 2, 28)), 14);
      expect(Validators.ageOn(DateTime(2008, 2, 29), DateTime(2023, 3, 1)), 15);
    });
  });

  group('friendlyAuthError', () {
    test('maps common Supabase errors to plain language', () {
      expect(friendlyAuthError(const AuthException('Invalid login credentials')),
          'Incorrect email/username or password.');
      expect(friendlyAuthError(const AuthException('Token has expired or is invalid')),
          'That code is invalid or has expired. Please request a new one.');
      expect(friendlyAuthError(Exception('SocketException: Failed host lookup')),
          contains("Can't reach SmartFit"));
    });

    test('never shows raw exception text for unknown errors', () {
      expect(friendlyAuthError(StateError('internal detail')), 'Something went wrong. Please try again.');
    });
  });
}
