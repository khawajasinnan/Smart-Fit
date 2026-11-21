import 'package:flutter/material.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/core/utils/validators.dart';

/// Live checklist of the password rules (same rules as Validators.password)
/// plus whether the confirmation matches.
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
      _Requirement(label: 'Includes an uppercase letter', isMet: password.contains(RegExp(r'[A-Z]'))),
      _Requirement(label: 'Includes a lowercase letter', isMet: password.contains(RegExp(r'[a-z]'))),
      _Requirement(label: 'Includes a number', isMet: password.contains(RegExp(r'[0-9]'))),
      _Requirement(
        label: 'Includes a special character',
        isMet: Validators.hasSpecial(password),
      ),
    ];

    final hasConfirmText = (confirmPassword ?? '').isNotEmpty;
    final passwordsMatch = password.isNotEmpty && confirmPassword == password;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xs),
          child: Text('Password should include:', style: context.tt.labelMedium),
        ),
        for (final r in requirements) _CheckRow(label: r.label, met: r.isMet),
        if (hasConfirmText)
          _CheckRow(
            label: passwordsMatch ? 'Passwords match' : 'Passwords do not match',
            met: passwordsMatch,
            failing: !passwordsMatch,
          ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.met, this.failing = false});

  final String label;
  final bool met;

  /// Show as a problem (red) rather than "not yet" (muted).
  final bool failing;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final color = met ? sf.success : (failing ? context.cs.error : sf.textMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: context.reduceMotion ? Duration.zero : AppDurations.fast,
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: Icon(
              met ? Icons.check_circle_rounded : (failing ? Icons.error_outline_rounded : Icons.circle_outlined),
              key: ValueKey('$met$failing'),
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text(
              label,
              style: context.tt.bodySmall?.copyWith(color: met ? sf.ink : (failing ? context.cs.error : sf.textMuted)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Requirement {
  const _Requirement({required this.label, required this.isMet});

  final String label;
  final bool isMet;
}
