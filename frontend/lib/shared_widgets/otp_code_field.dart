import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';

/// One-time-code input drawn as separate digit boxes.
///
/// It is a single real (invisible) text field underneath, so pasting the
/// whole code, keyboard/email code autofill and backspace all just work —
/// unlike one field per digit.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.length = 6,
    this.onCompleted,
    this.hasError = false,
    this.enabled = true,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final int length;

  /// Called once all digits are entered.
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool enabled;
  final bool autofocus;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_onChanged);
    _focus.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(OtpCodeField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  /// Text at the last notification. The controller also notifies on
  /// selection changes (e.g. a tap), which must not re-submit the code.
  String _lastText = '';

  void _onChanged() {
    final code = widget.controller.text;
    if (code == _lastText) return;
    _lastText = code;
    setState(() {});
    if (code.length == widget.length) widget.onCompleted?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final code = widget.controller.text;

    return LayoutBuilder(
      builder: (context, c) {
        const gap = AppSpace.xs;
        final box = ((c.maxWidth - gap * (widget.length - 1)) / widget.length).clamp(36.0, 56.0);

        return SizedBox(
          height: box * 1.18,
          child: Stack(
            children: [
              ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      _DigitBox(
                        size: box,
                        digit: i < code.length ? code[i] : null,
                        active: _focus.hasFocus && widget.enabled && i == code.length.clamp(0, widget.length - 1),
                        error: widget.hasError,
                      ),
                    ],
                  ],
                ),
              ),
              // The real field: invisible, but it takes the taps, keyboard,
              // paste and autofill.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    showCursor: false,
                    maxLength: widget.length,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(widget.length),
                    ],
                    style: TextStyle(color: sf.ink),
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      semanticCounterText: '',
                      labelText: 'Verification code',
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DigitBox extends StatelessWidget {
  const _DigitBox({required this.size, required this.digit, required this.active, required this.error});

  final double size;
  final String? digit;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final borderColor = error
        ? context.cs.error
        : active
            ? AppColors.accent600
            : digit != null
                ? context.cs.primary.withValues(alpha: 0.5)
                : sf.divider;

    return AnimatedContainer(
      duration: AppDurations.fast,
      width: size,
      height: size * 1.18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: sf.surfaceElevated,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: borderColor, width: active || error ? 2 : 1.2),
        boxShadow: active ? AppShadows.glow(AppColors.accent600, opacity: 0.18) : null,
      ),
      child: Text(
        digit ?? '',
        style: context.tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: sf.ink),
      ),
    );
  }
}
