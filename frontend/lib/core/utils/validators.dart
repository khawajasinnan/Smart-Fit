import 'package:smartfit/core/constants/app_strings.dart';

/// Form validators for auth & profile forms
class Validators {
  Validators._();

  /// name+tag@gmail.com, first.last@uni.edu.pk, a@brand.online: letters, digits and . _ % + -
  /// before the @ (no leading, trailing or double dot), a domain of labels, and a 2-24 letter ending.
  static final RegExp _email = RegExp(
    r'^[A-Za-z0-9_%+\-]+(\.[A-Za-z0-9_%+\-]+)*@[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?'
    r'(\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,24}$',
  );

  /// Validate email format
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return AppStrings.emailRequired;
    final v = value.trim();
    if (v.length > 254 || !_email.hasMatch(v)) return AppStrings.emailInvalid;
    return null;
  }

  /// Any symbol counts as "special" (_ - + = / ~ ' included), not only a fixed list:
  /// the same rule for the validator, the live checklist and the strength bar.
  static bool hasSpecial(String value) => RegExp(r'[^A-Za-z0-9\s]').hasMatch(value);

  /// Supabase (bcrypt) only uses the first 72 bytes of a password.
  static const int maxPasswordLength = 72;

  /// Validate password strength
  static String? password(String? value) {
    if (value == null || value.isEmpty) return AppStrings.passwordRequired;
    if (value.length < 8) return AppStrings.passwordTooShort;
    if (value.length > maxPasswordLength) return 'Password must be at most $maxPasswordLength characters';
    if (!value.contains(RegExp(r'[A-Z]'))) return AppStrings.passwordMustHaveUpper;
    if (!value.contains(RegExp(r'[a-z]'))) return AppStrings.passwordMustHaveLower;
    if (!value.contains(RegExp(r'[0-9]'))) return AppStrings.passwordMustHaveNumber;
    if (!hasSpecial(value)) return AppStrings.passwordMustHaveSpecial;
    return null;
  }

  /// Validate confirm password matches
  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) return AppStrings.passwordRequired;
    if (value != password) return AppStrings.passwordsDoNotMatch;
    return null;
  }

  /// Validate Pakistani phone number
  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return AppStrings.phoneRequired;
    final v = value.trim();
    final regex = RegExp(r'^(?:03\d{9}|\+923\d{9}|923\d{9})$');
    if (!regex.hasMatch(v)) return AppStrings.phoneInvalid;
    return null;
  }

  /// Letters in any script (Muhammad, محمد), spaces, and . ' - between them.
  static final RegExp _name = RegExp(r"^\p{L}[\p{L}\p{M} .'\-]*$", unicode: true);

  /// Validate full name
  static String? fullName(String? value) {
    if (value == null || value.trim().isEmpty) return AppStrings.nameRequired;
    final v = value.trim();
    if (v.length < 2) return 'Name must be at least 2 characters';
    if (v.length > 60) return 'Name must be at most 60 characters';
    if (!_name.hasMatch(v)) return 'Use letters only (spaces, . \' and - are fine)';
    return null;
  }

  /// Minimum age to use SmartFit (SRDS SFR-001 / §4.2: 15 years).
  static const int minimumAge = 15;

  /// Whole years between [dob] and [now] (birthday counted on the day itself).
  static int ageOn(DateTime dob, DateTime now) =>
      now.year - dob.year - (now.month < dob.month || (now.month == dob.month && now.day < dob.day) ? 1 : 0);

  /// Validate date of birth (must be [minimumAge]+).
  static String? dateOfBirth(DateTime? value, {DateTime? now}) {
    if (value == null) return AppStrings.dobRequired;
    final today = now ?? DateTime.now();
    if (value.isAfter(today)) return 'Date of birth cannot be in the future';
    final age = ageOn(value, today);
    if (age < minimumAge) return AppStrings.mustBe15;
    if (age > 120) return 'Please check your date of birth';
    return null;
  }

  /// Calculate password strength (0.0 to 1.0)
  static double passwordStrength(String password) {
    if (password.isEmpty) return 0;

    double strength = 0;
    if (password.length >= 8) strength += 0.2;
    if (password.length >= 12) strength += 0.1;
    if (password.contains(RegExp(r'[A-Z]'))) strength += 0.2;
    if (password.contains(RegExp(r'[a-z]'))) strength += 0.15;
    if (password.contains(RegExp(r'[0-9]'))) strength += 0.15;
    if (hasSpecial(password)) strength += 0.2;

    return strength.clamp(0.0, 1.0);
  }

  /// Get password strength label
  static String passwordStrengthLabel(double strength) {
    if (strength <= 0.25) return 'Weak';
    if (strength <= 0.5) return 'Fair';
    if (strength <= 0.75) return 'Good';
    return 'Strong';
  }
}
