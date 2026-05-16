import 'package:smartfit/core/constants/app_strings.dart';

/// Form validators for auth & profile forms
class Validators {
  Validators._();

  /// Validate email format
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return AppStrings.emailRequired;
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!regex.hasMatch(value.trim())) return AppStrings.emailInvalid;
    return null;
  }

  /// Validate password strength
  static String? password(String? value) {
    if (value == null || value.isEmpty) return AppStrings.passwordRequired;
    if (value.length < 8) return AppStrings.passwordTooShort;
    if (!value.contains(RegExp(r'[A-Z]'))) return AppStrings.passwordMustHaveUpper;
    if (!value.contains(RegExp(r'[a-z]'))) return AppStrings.passwordMustHaveLower;
    if (!value.contains(RegExp(r'[0-9]'))) return AppStrings.passwordMustHaveNumber;
    if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return AppStrings.passwordMustHaveSpecial;
    }
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

  /// Validate full name
  static String? fullName(String? value) {
    if (value == null || value.trim().isEmpty) return AppStrings.nameRequired;
    if (value.trim().length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  /// Validate date of birth (must be 18+)
  static String? dateOfBirth(DateTime? value) {
    if (value == null) return AppStrings.dobRequired;
    final now = DateTime.now();
    final age = now.year - value.year -
        (now.month < value.month || (now.month == value.month && now.day < value.day)
            ? 1
            : 0);
    if (age < 18) return AppStrings.mustBe18;
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
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength += 0.2;

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
