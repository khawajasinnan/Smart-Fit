import 'package:flutter/material.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';

class PasswordRequirementsList extends StatelessWidget {
  const PasswordRequirementsList({
    super.key,
    required this.password,
    this.confirmPassword,
  });

  final String password;
  final String? confirmPassword;

  @override
  Widget build(BuildContext context) {
    final requirements = <_Requirement>[
      _Requirement(label: 'At least 8 characters', isMet: password.length >= 8),
      _Requirement(
        label: 'Includes an uppercase letter',
        isMet: password.contains(RegExp(r'[A-Z]')),
      ),
      _Requirement(
        label: 'Includes a lowercase letter',
        isMet: password.contains(RegExp(r'[a-z]')),
      ),
      _Requirement(
        label: 'Includes a number',
        isMet: password.contains(RegExp(r'[0-9]')),
      ),
      _Requirement(
        label: 'Includes a special character',
        isMet: password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]')),
      ),
    ];

    final hasConfirmText = (confirmPassword ?? '').isNotEmpty;
    final passwordsMatch = password.isNotEmpty && confirmPassword == password;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            'Password should include:',
            style: AppTextStyles.labelSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        ...requirements.map(
          (requirement) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  requirement.isMet
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 16,
                  color: requirement.isMet
                      ? AppColors.success
                      : AppColors.outline,
                ),
                const SizedBox(width: 8),
                Text(
                  requirement.label,
                  style: AppTextStyles.labelSm.copyWith(
                    color: requirement.isMet
                        ? AppColors.onSurface
                        : AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasConfirmText)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  passwordsMatch
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  size: 16,
                  color: passwordsMatch ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 8),
                Text(
                  passwordsMatch ? 'Passwords match' : 'Passwords do not match',
                  style: AppTextStyles.labelSm.copyWith(
                    color: passwordsMatch ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Requirement {
  const _Requirement({required this.label, required this.isMet});

  final String label;
  final bool isMet;
}
