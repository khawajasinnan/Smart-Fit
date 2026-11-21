import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/utils/validators.dart';

/// Validation bugs found on 18 Nov 2026: real emails / passwords / names were refused.
void main() {
  group('email', () {
    for (final ok in [
      'sara@gmail.com',
      'name+shop@gmail.com', // Gmail aliases were refused
      'first.last@uni.edu.pk',
      'a_b-c@my-brand.online', // 5+ letter endings were refused
      'x@sub.domain.agency',
      '  padded@gmail.com  ',
    ]) {
      test('accepts $ok', () => expect(Validators.email(ok), isNull));
    }
    for (final bad in [
      '',
      'plain',
      'no-at.gmail.com',
      '@gmail.com',
      'sara@',
      'sara@gmail',
      'sara@gmail.c',
      '.sara@gmail.com',
      'sara.@gmail.com',
      'sa..ra@gmail.com',
      'sara@-gmail.com',
      'sara@gmail..com',
      'sa ra@gmail.com',
    ]) {
      test('rejects "$bad"', () => expect(Validators.email(bad), isNotNull));
    }
  });

  group('password', () {
    test('any symbol counts as special (underscore, dash, plus, slash, quote)', () {
      for (final p in ['Hello_World1', 'Hello-World1', 'Hello+World1', 'Hello/World1', "Hello'World1", 'Pass~word12']) {
        expect(Validators.password(p), isNull, reason: p);
        expect(Validators.hasSpecial(p), isTrue, reason: p);
      }
    });
    test('each rule is still enforced', () {
      expect(Validators.password('Ab1!'), isNotNull); // too short
      expect(Validators.password('abcdefg1!'), isNotNull); // no uppercase
      expect(Validators.password('ABCDEFG1!'), isNotNull); // no lowercase
      expect(Validators.password('Abcdefgh!'), isNotNull); // no number
      expect(Validators.password('Abcdefgh1'), isNotNull); // no symbol
      expect(Validators.password('Abcdefgh 1'), isNotNull); // a space is not a symbol
      expect(Validators.password('Aa1!${'x' * 80}'), isNotNull); // over 72
    });
    test('strength bar uses the same symbol rule', () {
      expect(Validators.passwordStrength('Hello_World1'), greaterThan(Validators.passwordStrength('HelloWorld12')));
    });
  });

  group('full name', () {
    for (final ok in ['Sara Khan', "D'Souza", 'Muhammad Ali-Raza', 'Dr. Ayesha', 'محمد علی']) {
      test('accepts $ok', () => expect(Validators.fullName(ok), isNull));
    }
    for (final bad in ['', ' ', 'A', '1234', 'Sara123', '@@@', 'Sara <script>', 'x' * 61]) {
      test('rejects "$bad"', () => expect(Validators.fullName(bad), isNotNull));
    }
  });

  group('date of birth', () {
    final now = DateTime(2026, 11, 18);
    test('future date is refused', () {
      expect(Validators.dateOfBirth(DateTime(2027, 1, 1), now: now), 'Date of birth cannot be in the future');
    });
    test('over 120 years is refused', () => expect(Validators.dateOfBirth(DateTime(1900, 1, 1), now: now), isNotNull));
    test('a normal adult is fine', () => expect(Validators.dateOfBirth(DateTime(2000, 5, 5), now: now), isNull));
  });

  group('phone (Pakistan)', () {
    for (final ok in ['03001234567', '+923001234567', '923001234567']) {
      test('accepts $ok', () => expect(Validators.phone(ok), isNull));
    }
    for (final bad in ['0300123456', '04001234567', '+92300123456', 'abc']) {
      test('rejects $bad', () => expect(Validators.phone(bad), isNotNull));
    }
  });
}
