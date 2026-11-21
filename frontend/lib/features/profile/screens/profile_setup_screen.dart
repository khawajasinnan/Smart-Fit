import 'dart:convert';
import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/utils/validators.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/theme/app_tokens.dart';
import 'package:smartfit/core/theme/sf_colors.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/data/services/cv_analysis_api_service.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:smartfit/features/profile/screens/skin_tone_analyzer_screen.dart';
import 'package:smartfit/features/profile/widgets/body_silhouette.dart';
import 'package:smartfit/features/body_scan/screens/body_scan_camera.dart';
import 'package:smartfit/shared_widgets/notice_banner.dart';
import 'package:smartfit/shared_widgets/pressable.dart';
import 'package:smartfit/shared_widgets/safe_network_image.dart';
import 'package:smartfit/shared_widgets/sf_animated_size.dart';
import 'package:smartfit/shared_widgets/sf_button.dart';
import 'package:smartfit/shared_widgets/sf_entrance.dart';
import 'package:smartfit/shared_widgets/sf_glass_card.dart';
import 'package:smartfit/shared_widgets/sf_scaffold.dart';
import 'package:smartfit/shared_widgets/sf_step_progress.dart';
import 'package:smartfit/shared_widgets/sf_text_field.dart';
import 'package:smartfit/shared_widgets/tilt_card.dart';

/// Mandatory profile setup (SFR-006, SFR-009..013) and, when pushed from
/// the Profile tab, profile editing (SFR-007).
///
/// Step 1: photo, gender, phone, ethnicity. Step 2: body type and
/// measurements. Step 3: skin tone and style preferences. First-time setup
/// ends with a short celebration, then Home; editing pops back.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  static const _totalSteps = 3;

  int _step = 0;
  bool _prefilledProfile = false;
  UserProfileModel? _existingProfile;

  /// Step-level problem or save failure, shown above the button.
  String? _error;
  bool _saving = false;
  bool _celebrating = false;

  // Step 1 — photo, gender, phone, ethnicity
  String? _gender;
  Uint8List? _avatarBytes;
  String? _avatarUrl;
  final _phoneCtrl = TextEditingController();
  String? _ethnicity;

  /// Asked only when the account has no date of birth: Google
  /// sign-ups (email sign-up collects it). SRDS SFR-001: 15+ only.
  DateTime? _dob;

  // Step 2 — body. No shape pre-selected: the shapes depend on the gender (21 Nov 2026).
  String _selectedBodyType = '';
  String? _usualSize; // the size the user usually buys (optional)
  double _height = 170;
  double _weight = 70;
  double _chest = 90;
  double _waist = 76;
  double _hip = 94;
  bool _useFeetInches = true;

  // Step 3 — skin tone + style
  String _skinTone = 'Medium';
  String? _undertone; // warm | cool | neutral (skin tone analyzer or the user's pick)
  final List<String> _selectedStyles = [];

  static const _ethnicities = [
    ('Punjabi', Icons.local_florist_outlined),
    ('Sindhi', Icons.palette_outlined),
    ('Balochi', Icons.blur_on),
    ('Pathan', Icons.shield_outlined),
    ('Saraiki', Icons.spa_outlined),
    ('Gilgiti', Icons.landscape_outlined), // Gilgit-Baltistan (21 Nov 2026)
  ];

  static const _usualSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL', '4XL'];

  static const _styles = [
    ('Streetwear', Icons.checkroom),
    ('Clean', Icons.auto_awesome),
    ('Luxury', Icons.diamond_outlined),
    ('Casual', Icons.weekend_outlined),
    ('Formal', Icons.business_center_outlined),
    ('Sporty', Icons.fitness_center),
    ('Ethnic', Icons.palette_outlined),
    ('Modest', Icons.shield_outlined),
    ('Bohemian', Icons.local_florist_outlined),
    ('Minimalist', Icons.crop_square),
    ('Glam', Icons.star_rounded),
    ('Fusion', Icons.merge_type),
    ('Shalwar Kameez', Icons.checkroom),
    ('Lawn Suit', Icons.wb_sunny_outlined),
    ('Dupatta Styling', Icons.auto_awesome_motion),
    ('Lehenga', Icons.diamond_outlined),
    ('Gharara', Icons.flare),
    ('Khussa', Icons.shopping_bag_outlined),
  ];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  /// The gender, and no body shape that belongs only to the other gender's list.
  void _setGender(String? gender) {
    _gender = gender;
    if (_selectedBodyType.isNotEmpty &&
        !bodyShapesFor(gender).containsKey(_selectedBodyType) &&
        bodyShapesFor(gender == 'Female' ? 'Male' : 'Female').containsKey(_selectedBodyType)) {
      _selectedBodyType = '';
    }
  }

  /// The shapes to offer: the gender's five, plus a body type saved before 21 Nov 2026 so
  /// editing a profile never loses it.
  Map<String, BodyProportions> get _shapeChoices {
    final shapes = Map.of(bodyShapesFor(_gender));
    final saved = proportionsFor(_selectedBodyType);
    if (_selectedBodyType.isNotEmpty && !shapes.containsKey(_selectedBodyType) && saved != null) {
      shapes[_selectedBodyType] = saved;
    }
    return shapes;
  }

  /// setState that also clears a shown step error (the user is fixing it).
  void _update(VoidCallback change) {
    setState(() {
      change();
      _error = null;
    });
  }

  // ── Validation ───────────────────────────────────────────────────────────

  /// The date of birth already on the account (email sign-up), if any.
  DateTime? get _knownDob {
    final meta = ref.read(currentUserProvider)?.userMetadata;
    return DateTime.tryParse(meta?['date_of_birth'] as String? ?? '') ?? _existingProfile?.dateOfBirth;
  }

  bool get _needsDob => _knownDob == null;

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final latest = DateTime(now.year - Validators.minimumAge, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Your date of birth',
    );
    if (picked != null) {
      _update(() => _dob = picked);
      if (picked.isAfter(latest) && mounted) setState(() => _error = Validators.dateOfBirth(picked));
    }
  }

  String? _validateStep(int step) {
    if (step == 0) {
      if (_needsDob) {
        final dobError = Validators.dateOfBirth(_dob);
        if (dobError != null) return dobError;
      }
      if (_gender == null) return 'Please select your gender.';
      if (_avatarBytes == null && (_avatarUrl == null || _avatarUrl!.isEmpty)) {
        return 'Please add a profile photo so recommendations can match you.';
      }
      final phone = _phoneCtrl.text.trim();
      if (phone.isEmpty) return 'Please add your phone number.';
      if (!_isValidPakistaniPhone(phone)) {
        return 'Please enter a valid Pakistani mobile number (e.g. 03XXXXXXXXX or +923XXXXXXXXX).';
      }
      if (_ethnicity == null) return 'Please select your ethnicity / culture.';
    }
    if (step == 1) {
      if (_selectedBodyType.trim().isEmpty) return 'Please select your body shape.';
      if (_height <= 0 || _weight <= 0 || _chest <= 0 || _waist <= 0 || _hip <= 0) {
        return 'Please add your height, weight, chest, waist, and hip measurements.';
      }
    }
    if (step == 2) {
      if (_skinTone.trim().isEmpty) return 'Please select your skin tone.';
      if (_selectedStyles.isEmpty) return 'Please pick at least one style preference.';
    }
    return null;
  }

  /// Valid: 03XXXXXXXXX, +923XXXXXXXXX, 00923XXXXXXXXX, 923XXXXXXXXX.
  bool _isValidPakistaniPhone(String input) {
    final p = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('+')) return p.length == 13 && p.startsWith('+923');
    if (p.startsWith('0092')) return p.length == 14 && p.startsWith('00923');
    if (p.startsWith('92')) return p.length == 12 && p.startsWith('923');
    if (p.startsWith('0')) return p.length == 11 && p.startsWith('03');
    return false;
  }

  /// Stored as +923XXXXXXXXX.
  String _normalizePakistaniPhone(String input) {
    var p = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('0092')) {
      p = '+${p.substring(2)}';
    } else if (p.startsWith('92') && !p.startsWith('+')) {
      p = '+$p';
    } else if (p.startsWith('0')) {
      p = '+92${p.substring(1)}';
    }
    return p;
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void _next() {
    FocusScope.of(context).unfocus();
    final error = _validateStep(_step);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_step < _totalSteps - 1) {
      setState(() {
        _step++;
        _error = null;
      });
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() {
        _step--;
        _error = null;
      });
    }
  }

  // ── Photo ────────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Profile photo', style: ctx.tt.headlineSmall),
              const SizedBox(height: AppSpace.xxs),
              Text('A clear, well-lit, front-facing photo works best.', style: ctx.tt.bodyMedium),
              const SizedBox(height: AppSpace.lg),
              _SheetOption(
                icon: Icons.photo_camera_rounded,
                title: 'Take a photo',
                subtitle: 'With a pose guide to line you up',
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: AppSpace.sm),
              _SheetOption(
                icon: Icons.photo_library_rounded,
                title: 'Choose from gallery',
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    Uint8List? bytes;
    if (source == ImageSource.camera) {
      bytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const BodyScanCamera(title: 'Profile photo'),
      );
    } else {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 800, imageQuality: 85);
      bytes = await file?.readAsBytes();
    }
    if (bytes == null || !mounted) return;
    _update(() => _avatarBytes = bytes);
    _checkPhotoGenderMatch();
  }

  /// Non-blocking suggestion: if the CV service is confident the photo shows
  /// a different gender than selected, offer to switch.
  Future<void> _checkPhotoGenderMatch() async {
    if (_avatarBytes == null || _gender == null) return;
    try {
      final result = await ref.read(cvAnalysisApiServiceProvider).analyzeBody(
            imageBase64: base64Encode(_avatarBytes!),
            gender: _gender,
            heightCm: _height,
            weightKg: _weight,
          );
      if (!result.success || !mounted) return;
      final estimated = result.estimatedGender;
      final confidence = result.genderConfidence ?? 0.0;
      if (estimated != null &&
          estimated != 'uncertain' &&
          estimated.toLowerCase() != _gender!.toLowerCase() &&
          confidence >= 0.7) {
        _showGenderMismatchDialog(estimated);
      }
    } catch (e) {
      debugPrint('Gender detection check failed (non-blocking): $e');
    }
  }

  void _showGenderMismatchDialog(String detectedGender) {
    final detected = detectedGender.substring(0, 1).toUpperCase() + detectedGender.substring(1).toLowerCase();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.info_outline_rounded, color: ctx.sf.warning, size: 32),
        title: const Text("Photo and gender don't match"),
        content: Text(
          'The photo appears to show a ${detectedGender.toLowerCase()} person, but you selected $_gender. '
          'For the best styling recommendations, both should match.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep current')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _update(() => _setGender(detected));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gender updated to $detected')));
            },
            child: Text('Update to $detected'),
          ),
        ],
      ),
    );
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    // Re-check every step and jump to the first one with a problem.
    for (var i = 0; i < _totalSteps; i++) {
      final error = _validateStep(i);
      if (error != null) {
        setState(() {
          _step = i;
          _error = error;
        });
        return;
      }
    }

    final authUser = ref.read(currentUserProvider);
    final user = ref.read(authNotifierProvider).user;
    final userId = user?.id ?? authUser?.id;
    if (userId == null) {
      context.go(RoutePaths.login);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var avatarUrl = _avatarUrl ?? _existingProfile?.photoUrl;
      if (_avatarBytes != null) {
        avatarUrl = await ref.read(profileNotifierProvider(userId).notifier).uploadAvatar(_avatarBytes!);
      }
      if (avatarUrl == null || avatarUrl.isEmpty) {
        throw Exception('Profile photo upload failed. Please check the avatars bucket policies and try again.');
      }

      final metadata = authUser?.userMetadata;
      final phone = _normalizePakistaniPhone(_phoneCtrl.text.trim());
      final profile = UserProfileModel(
        id: userId,
        fullName: _existingProfile?.fullName ?? user?.fullName ?? metadata?['full_name'] as String?,
        username: _existingProfile?.username ?? metadata?['username'] as String?,
        email: _existingProfile?.email ?? user?.email ?? authUser?.email,
        dateOfBirth: DateTime.tryParse(metadata?['date_of_birth'] as String? ?? '') ?? _existingProfile?.dateOfBirth ?? _dob,
        gender: _gender,
        ethnicity: _ethnicity,
        phone: phone,
        bodyType: _selectedBodyType,
        heightCm: _height,
        weightKg: _weight,
        chestCm: _chest,
        waistCm: _waist,
        hipCm: _hip,
        skinTone: _skinTone,
        skinUndertone: _undertone,
        usualSize: _usualSize,
        photoUrl: avatarUrl,
        stylePreferences: List.of(_selectedStyles),
        preferredColors: _existingProfile?.preferredColors ?? const [],
        budgetMin: _existingProfile?.budgetMin,
        budgetMax: _existingProfile?.budgetMax,
        occasions: _existingProfile?.occasions ?? const [],
        profileCompleted: true,
      );
      await ref.read(profileNotifierProvider(userId).notifier).updateProfile(profile);
      await ref.read(authRepositoryProvider).updateUserMetadata({'phone': phone, 'avatar_url': avatarUrl});

      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        // Editing from the Profile tab: back to where they came from.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
        Navigator.of(context).pop();
      } else {
        HapticFeedback.mediumImpact();
        setState(() {
          _saving = false;
          _celebrating = true;
        });
      }
    } catch (e) {
      debugPrint('[ProfileSetup] save failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save your profile. Check your connection and try again.";
        });
      }
    }
  }

  void _applyExistingProfile(UserProfileModel profile) {
    final metadata = ref.read(currentUserProvider)?.userMetadata;
    setState(() {
      _existingProfile = profile;
      _prefilledProfile = true;
      _gender = profile.gender ?? _gender;
      _ethnicity = profile.ethnicity ?? _ethnicity;
      _avatarUrl = profile.photoUrl ?? metadata?['avatar_url'] as String?;
      _phoneCtrl.text = profile.phone ?? metadata?['phone'] as String? ?? _phoneCtrl.text;
      _selectedBodyType = profile.bodyType ?? _selectedBodyType;
      _height = profile.heightCm ?? _height;
      _weight = profile.weightKg ?? _weight;
      _chest = profile.chestCm ?? _chest;
      _waist = profile.waistCm ?? _waist;
      _hip = profile.hipCm ?? _hip;
      _skinTone = profile.skinTone ?? _skinTone;
      _undertone = profile.skinUndertone ?? _undertone;
      _usualSize = profile.usualSize ?? _usualSize;
      _selectedStyles
        ..clear()
        ..addAll(profile.stylePreferences);
    });
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _formatDob(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  String? get _firstName {
    final full = _existingProfile?.fullName ??
        ref.read(authNotifierProvider).user?.fullName ??
        ref.read(currentUserProvider)?.userMetadata?['full_name'] as String?;
    final first = full?.trim().split(RegExp(r'\s+')).first;
    return (first == null || first.isEmpty) ? null : first;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(currentUserProvider);
    final userId = ref.watch(authNotifierProvider).user?.id ?? authUser?.id;
    if (userId != null) {
      ref.watch(profileNotifierProvider(userId)).whenData((profile) {
        if (!_prefilledProfile && profile != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_prefilledProfile) _applyExistingProfile(profile);
          });
        }
      });
    }

    if (_celebrating) {
      return _Celebration(
        name: _firstName,
        avatarBytes: _avatarBytes,
        avatarUrl: _avatarUrl,
        onContinue: () => context.go(RoutePaths.home),
      );
    }

    final editing = Navigator.of(context).canPop();
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: SFScaffold(
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.xs, AppSpace.gutter, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: _step > 0
                        ? IconButton(
                            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                            onPressed: _back,
                            icon: const Icon(Icons.arrow_back_rounded),
                          )
                        : editing
                            ? IconButton(
                                tooltip: 'Close',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded),
                              )
                            : null,
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: SFStepProgress(step: _step + 1, total: _totalSteps)),
                ],
              ),
            ),
            Expanded(
              child: PageTransitionSwitcher(
                duration: context.reduceMotion ? Duration.zero : AppDurations.slow,
                reverse: false,
                layoutBuilder: (entries) => Stack(fit: StackFit.expand, children: entries),
                transitionBuilder: (child, primary, secondary) => SharedAxisTransition(
                  animation: primary,
                  secondaryAnimation: secondary,
                  transitionType: SharedAxisTransitionType.horizontal,
                  fillColor: Colors.transparent,
                  child: child,
                ),
                child: KeyedSubtree(key: ValueKey(_step), child: _stepPage()),
              ),
            ),
            _bottomBar(editing),
          ],
        ),
      ),
    );
  }

  Widget _stepPage() {
    final (title, subtitle, content) = switch (_step) {
      0 => ("Let's get to know you", 'A photo and a few basics, so every suggestion looks like you.', _basicsStep()),
      1 => ('Your shape & size', 'Measurements make sizes and fits accurate. You can change them anytime.', _bodyStep()),
      _ => ('Your style DNA', 'Your skin tone and the styles you love shape every recommendation.', _styleStep()),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xl),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _padded(SFEntrance(child: Semantics(header: true, child: Text(title, style: context.tt.displaySmall)))),
          const SizedBox(height: AppSpace.xs),
          _padded(
            SFEntrance(
              index: 1,
              child: Text(subtitle, style: context.tt.bodyLarge?.copyWith(color: context.sf.textMuted)),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SFEntrance(index: 2, child: content),
        ],
      ),
    );
  }

  Widget _padded(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter), child: child);

  Widget _label(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Row(
          children: [
            Expanded(child: Text(text, style: context.tt.titleMedium)),
            ?trailing,
          ],
        ),
      );

  Widget _bottomBar(bool editing) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final last = _step == _totalSteps - 1;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.sm,
        AppSpace.gutter,
        AppSpace.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [bg, bg.withValues(alpha: 0.92), bg.withValues(alpha: 0)],
          stops: const [0, 0.75, 1],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SFAnimatedSize(
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: NoticeBanner(
                      tone: NoticeTone.error,
                      message: _error!,
                      onClose: () => setState(() => _error = null),
                    ),
                  ),
          ),
          SFButton(
            label: last ? (editing ? 'Save changes' : 'Finish') : 'Continue',
            trailingIcon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
            isLoading: _saving,
            onPressed: _next,
          ),
        ],
      ),
    );
  }

  // ── Step 1: photo, gender, phone, ethnicity ─────────────────────────────

  Widget _basicsStep() {
    return _padded(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _AvatarPicker(bytes: _avatarBytes, url: _avatarUrl, onTap: _pickPhoto)),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Use a clear, front-facing photo — it helps us match outfits to you.',
            textAlign: TextAlign.center,
            style: context.tt.bodySmall,
          ),
          const SizedBox(height: AppSpace.xl),
          _label('Gender'),
          Row(
            children: [
              Expanded(
                child: _ChoiceCard(
                  icon: Icons.male_rounded,
                  label: 'Male',
                  selected: _gender == 'Male',
                  onTap: () => _update(() => _setGender('Male')),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: _ChoiceCard(
                  icon: Icons.female_rounded,
                  label: 'Female',
                  selected: _gender == 'Female',
                  onTap: () => _update(() => _setGender('Female')),
                ),
              ),
            ],
          ),
          if (_needsDob) ...[
            const SizedBox(height: AppSpace.xl),
            _label('Date of birth'),
            Semantics(
              button: true,
              label: _dob == null ? 'Choose your date of birth' : 'Date of birth ${_formatDob(_dob!)}. Tap to change',
              excludeSemantics: true,
              child: OutlinedButton.icon(
                onPressed: _pickDob,
                icon: const Icon(Icons.cake_outlined),
                label: Text(_dob == null ? 'Choose your date of birth' : _formatDob(_dob!)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  alignment: Alignment.centerLeft,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text('SmartFit is for ages ${Validators.minimumAge}+.',
                  style: context.tt.bodySmall?.copyWith(color: context.sf.textMuted)),
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          SFTextField(
            controller: _phoneCtrl,
            label: 'Phone number',
            hint: '03XX XXXXXXX',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            autocorrect: false,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[+\d]')),
              LengthLimitingTextInputFormatter(14),
            ],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: AppSpace.xl),
          _label('Ethnicity / culture'),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final (label, icon) in _ethnicities)
                _SelectChip(
                  label: label,
                  icon: icon,
                  selected: _ethnicity == label,
                  onTap: () => _update(() => _ethnicity = label),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 2: body type + measurements ────────────────────────────────────

  String _formatHeight(double cm) {
    if (!_useFeetInches) return '${cm.round()} cm';
    final totalInches = cm / 2.54;
    var feet = totalInches ~/ 12;
    var inches = (totalInches % 12).round();
    if (inches == 12) {
      feet += 1;
      inches = 0;
    }
    return '$feet\'$inches"';
  }

  String _formatMeasurement(double cm) => _useFeetInches ? '${(cm / 2.54).toStringAsFixed(1)} in' : '${cm.round()} cm';

  Widget _bodyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _padded(
          _label(
            'Body shape',
            trailing: _UnitToggle(metric: !_useFeetInches, onChanged: (metric) => setState(() => _useFeetInches = !metric)),
          ),
        ),
        SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter, vertical: AppSpace.xxs),
            itemCount: _shapeChoices.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
            itemBuilder: (context, i) {
              final entry = _shapeChoices.entries.elementAt(i);
              return _BodyTypeCard(
                label: entry.key,
                proportions: entry.value,
                selected: _selectedBodyType == entry.key,
                onTap: () => _update(() => _selectedBodyType = entry.key),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        _padded(_label('Your usual size (optional)')),
        _padded(
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final size in _usualSizes)
                ChoiceChip(
                  label: Text(size),
                  selected: _usualSize == size,
                  // tap again to clear: it is optional
                  onSelected: (on) => _update(() => _usualSize = on ? size : null),
                ),
            ],
          ),
        ),
        _padded(
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(
              'The size you usually buy in shirts or kameez. Shown sizes follow it.',
              style: context.tt.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        _padded(
          _SliderCard(
            icon: Icons.height_rounded,
            label: 'Height',
            value: _height,
            min: 120,
            max: 230,
            display: _formatHeight(_height),
            onChanged: (v) => _update(() => _height = v),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _padded(
          _SliderCard(
            icon: Icons.monitor_weight_outlined,
            label: 'Weight',
            value: _weight,
            min: 30,
            max: 200,
            display: '${_weight.round()} kg',
            onChanged: (v) => _update(() => _weight = v),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _padded(
          SFGlassCard(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.md, AppSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _IconBadge(icon: Icons.straighten_rounded),
                    const SizedBox(width: AppSpace.sm),
                    Flexible(child: Text('Chest · Waist · Hip', style: context.tt.titleMedium)),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                _MiniSlider(
                  label: 'Chest',
                  value: _chest,
                  min: 50,
                  max: 160,
                  display: _formatMeasurement(_chest),
                  onChanged: (v) => _update(() => _chest = v),
                ),
                _MiniSlider(
                  label: 'Waist',
                  value: _waist,
                  min: 40,
                  max: 160,
                  display: _formatMeasurement(_waist),
                  onChanged: (v) => _update(() => _waist = v),
                ),
                _MiniSlider(
                  label: 'Hip',
                  value: _hip,
                  min: 50,
                  max: 170,
                  display: _formatMeasurement(_hip),
                  onChanged: (v) => _update(() => _hip = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        _padded(
          Text(
            'Tip: measure around the fullest part, keeping the tape level and snug.',
            style: context.tt.bodySmall,
          ),
        ),
      ],
    );
  }

  // ── Step 3: skin tone + style ───────────────────────────────────────────

  Future<void> _openSkinAnalyzer() async {
    final choice = await Navigator.of(context).push<SkinToneChoice>(
      MaterialPageRoute(
        builder: (_) => SkinToneAnalyzerScreen(profilePhotoBytes: _avatarBytes, profilePhotoUrl: _avatarUrl),
      ),
    );
    if (choice == null || !mounted) return;
    _update(() {
      if (AppColors.skinToneSwatches.containsKey(choice.skinTone)) _skinTone = choice.skinTone;
      _undertone = choice.undertone ?? _undertone;
    });
  }

  Widget _styleStep() {
    return _padded(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Skin tone'),
          OutlinedButton.icon(
            onPressed: _openSkinAnalyzer,
            icon: const Icon(Icons.face_retouching_natural_rounded),
            label: const Text('Analyze my skin tone'),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: [
              for (final entry in AppColors.skinToneSwatches.entries)
                _SkinSwatch(
                  label: entry.key,
                  color: entry.value,
                  selected: _skinTone == entry.key,
                  onTap: () => _update(() => _skinTone = entry.key),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text('Undertone', style: context.tt.labelLarge),
          const SizedBox(height: AppSpace.xxs),
          Wrap(
            spacing: AppSpace.xs,
            children: [
              for (final (label, value) in const [('Warm', 'warm'), ('Cool', 'cool'), ('Neutral', 'neutral')])
                ChoiceChip(
                  label: Text(label),
                  selected: _undertone == value,
                  onSelected: (on) => _update(() => _undertone = on ? value : null),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text("Not sure? The analyzer finds it with a photo and two quick questions.",
                style: context.tt.bodySmall),
          ),
          const SizedBox(height: AppSpace.xl),
          _label(
            'Styles you love',
            trailing: Text('${_selectedStyles.length} selected', style: context.tt.labelMedium),
          ),
          Text('Pick as many as you like.', style: context.tt.bodySmall),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final (label, icon) in _styles)
                _SelectChip(
                  label: label,
                  icon: icon,
                  selected: _selectedStyles.contains(label),
                  onTap: () => _update(() {
                    if (!_selectedStyles.remove(label)) _selectedStyles.add(label);
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.bytes, required this.url, required this.onTap});

  final Uint8List? bytes;
  final String? url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final hasPhoto = bytes != null || (url?.isNotEmpty ?? false);
    return Semantics(
      button: true,
      label: hasPhoto ? 'Change profile photo' : 'Add profile photo',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: AppDurations.base,
                width: 132,
                height: 132,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasPhoto ? sf.brandGradient : LinearGradient(colors: [sf.orbA, sf.orbB]),
                  boxShadow: hasPhoto ? AppShadows.glow(AppColors.accent600, opacity: 0.25) : null,
                ),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: sf.surfaceElevated),
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: bytes != null
                        ? Image.memory(bytes!, fit: BoxFit.cover)
                        : (url?.isNotEmpty ?? false)
                            ? SafeNetworkImage(imageUrl: url!, fallbackIcon: Icons.person_rounded)
                            : ColoredBox(
                                color: sf.surfaceSunken,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined, size: 30, color: sf.accentText),
                                    const SizedBox(height: AppSpace.xxs),
                                    Text('Add photo', style: context.tt.labelMedium?.copyWith(color: sf.accentText)),
                                  ],
                                ),
                              ),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: sf.brandGradient,
                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
                  ),
                  child: Icon(Icons.photo_camera_rounded, color: sf.onBrand, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.base,
          curve: AppCurves.enter,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent600.withValues(alpha: context.isDark ? 0.16 : 0.07) : sf.surfaceElevated,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: selected ? AppColors.accent600 : sf.divider, width: selected ? 2 : 1.2),
            boxShadow: selected ? AppShadows.glow(AppColors.accent600, opacity: 0.16) : null,
          ),
          child: Column(
            children: [
              AnimatedContainer(
                duration: AppDurations.base,
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selected ? sf.brandGradient : null,
                  color: selected ? null : sf.surfaceSunken,
                ),
                child: Icon(icon, size: 28, color: selected ? sf.onBrand : sf.textMuted),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(label, style: context.tt.titleMedium?.copyWith(color: selected ? sf.accentText : sf.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill chip; selected = brand gradient. Used single- and multi-select.
class _SelectChip extends StatelessWidget {
  const _SelectChip({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final fg = selected ? sf.onBrand : sf.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        haptic: false,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? sf.brandGradient : null,
            color: selected ? null : sf.surfaceElevated,
            borderRadius: AppRadius.pillAll,
            border: Border.all(color: selected ? Colors.transparent : sf.divider, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? Icons.check_rounded : icon, size: 16, color: selected ? fg : sf.textMuted),
              const SizedBox(width: 6),
              Text(label, style: context.tt.labelLarge?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BodyTypeCard extends StatelessWidget {
  const _BodyTypeCard({required this.label, required this.proportions, required this.selected, required this.onTap});

  final String label;
  final BodyProportions proportions;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final muted = sf.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label body type',
      excludeSemantics: true,
      child: TiltCard(
        child: Pressable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppDurations.base,
            curve: AppCurves.enter,
            width: 108,
            padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.sm, AppSpace.xs, AppSpace.sm),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent600.withValues(alpha: context.isDark ? 0.16 : 0.07) : sf.surfaceElevated,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: selected ? AppColors.accent600 : sf.divider, width: selected ? 2 : 1.2),
              boxShadow: selected ? AppShadows.glow(AppColors.accent600, opacity: 0.18) : null,
            ),
            child: Column(
              children: [
                Expanded(
                  child: BodySilhouette(
                    proportions: proportions,
                    fill: selected
                        ? sf.brandGradient
                        : LinearGradient(colors: [muted.withValues(alpha: 0.5), muted.withValues(alpha: 0.35)]),
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (selected) ...[
                      Icon(Icons.check_circle_rounded, size: 16, color: sf.accentText),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.labelLarge?.copyWith(color: selected ? sf.accentText : sf.ink),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.metric, required this.onChanged});

  final bool metric;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    Widget segment(String text, bool isMetric) {
      final on = metric == isMetric;
      return Semantics(
        button: true,
        selected: on,
        label: isMetric ? 'Centimetres' : 'Feet and inches',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => onChanged(isMetric),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(gradient: on ? sf.brandGradient : null, borderRadius: AppRadius.pillAll),
            child: Text(text, style: context.tt.labelMedium?.copyWith(color: on ? sf.onBrand : sf.ink)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: sf.surfaceSunken, borderRadius: AppRadius.pillAll),
      child: Row(mainAxisSize: MainAxisSize.min, children: [segment('ft / in', false), segment('cm', true)]),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.accent600.withValues(alpha: context.isDark ? 0.2 : 0.1),
          borderRadius: AppRadius.smAll,
        ),
        child: Icon(icon, size: 20, color: context.sf.accentText),
      );
}

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SFGlassCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.md, AppSpace.xxs),
      child: Column(
        children: [
          Row(
            children: [
              _IconBadge(icon: icon),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(label, style: context.tt.titleMedium)),
              Text(display, style: context.tt.headlineSmall),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            label: display,
            semanticFormatterCallback: (_) => display,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _MiniSlider extends StatelessWidget {
  const _MiniSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        children: [
          SizedBox(width: 52, child: Text(label, style: context.tt.bodyMedium?.copyWith(color: context.sf.ink))),
          Expanded(
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              semanticFormatterCallback: (_) => display,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(display, textAlign: TextAlign.end, style: context.tt.labelLarge),
          ),
        ],
      ),
    );
  }
}

class _SkinSwatch extends StatelessWidget {
  const _SkinSwatch({required this.label, required this.color, required this.selected, required this.onTap});

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final checkColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : AppColors.ink900;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label skin tone',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 60,
          child: Column(
            children: [
              AnimatedContainer(
                duration: AppDurations.base,
                width: 56,
                height: 56,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? AppColors.accent600 : sf.divider, width: selected ? 2.5 : 1.2),
                  boxShadow: selected ? AppShadows.glow(AppColors.accent600, opacity: 0.2) : null,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: AppDurations.base,
                    curve: AppCurves.playful,
                    child: Icon(Icons.check_rounded, color: checkColor, size: 22),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: context.tt.labelMedium?.copyWith(color: selected ? sf.ink : sf.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({required this.icon, required this.title, required this.onTap, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    return Material(
      color: sf.surfaceSunken,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: sf.brandGradient),
                child: Icon(icon, color: sf.onBrand, size: 22),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.tt.titleMedium),
                    if (subtitle != null) Text(subtitle!, style: context.tt.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: sf.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Celebration (first-time setup only) ─────────────────────────────────────

class _Celebration extends StatefulWidget {
  const _Celebration({required this.name, required this.avatarBytes, required this.avatarUrl, required this.onContinue});

  final String? name;
  final Uint8List? avatarBytes;
  final String? avatarUrl;
  final VoidCallback onContinue;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && !context.reduceMotion) {
      _started = true;
      _burst.forward();
    }
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sf = context.sf;
    final title = widget.name == null ? "You're all set!" : "You're all set, ${widget.name}!";
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onContinue();
      },
      child: SFScaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ConfettiPainter(
                    animation: _burst,
                    colors: [AppColors.primary600, AppColors.accent600, sf.orbC.withValues(alpha: 1), AppColors.warning],
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.gutter),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.6, end: 1),
                      duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
                      curve: Curves.elasticOut,
                      builder: (context, s, child) => Transform.scale(scale: s, child: child),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 128,
                            height: 128,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: sf.brandGradient,
                              boxShadow: AppShadows.glow(AppColors.accent600, opacity: 0.3),
                            ),
                            child: ClipOval(
                              child: widget.avatarBytes != null
                                  ? Image.memory(widget.avatarBytes!, fit: BoxFit.cover)
                                  : SafeNetworkImage(imageUrl: widget.avatarUrl ?? '', fallbackIcon: Icons.person_rounded),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: sf.success,
                                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
                              ),
                              child: const Icon(Icons.check_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    SFEntrance(
                      index: 1,
                      child: Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(title, textAlign: TextAlign.center, style: context.tt.displaySmall),
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    SFEntrance(
                      index: 2,
                      child: Text(
                        'Your style profile is ready. From now on every suggestion is picked for your body, '
                        'skin tone and taste.',
                        textAlign: TextAlign.center,
                        style: context.tt.bodyLarge?.copyWith(color: sf.textMuted),
                      ),
                    ),
                    const SizedBox(height: AppSpace.xxl),
                    SFEntrance(
                      index: 3,
                      child: SFButton(
                        label: 'Start exploring',
                        trailingIcon: Icons.arrow_forward_rounded,
                        onPressed: widget.onContinue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-shot confetti burst from just above the avatar.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.animation, required this.colors}) : super(repaint: animation);

  final Animation<double> animation;
  final List<Color> colors;

  static final _pieces = List.generate(46, (i) {
    final r = math.Random(i * 7919 + 13);
    return (
      angle: -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.5,
      speed: 0.35 + r.nextDouble() * 0.45,
      spin: (r.nextDouble() - 0.5) * 12,
      w: 5 + r.nextDouble() * 5,
      h: 8 + r.nextDouble() * 8,
      color: i,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t == 0 || t == 1) return;
    final origin = Offset(size.width / 2, size.height * 0.36);
    final reach = size.shortestSide * 0.9;
    final fade = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
    final paint = Paint();
    for (final p in _pieces) {
      final d = reach * p.speed * Curves.easeOutCubic.transform(t);
      final pos = origin + Offset(math.cos(p.angle) * d, math.sin(p.angle) * d + 260 * t * t);
      paint.color = colors[p.color % colors.length].withValues(alpha: fade.clamp(0, 1).toDouble());
      canvas
        ..save()
        ..translate(pos.dx, pos.dy)
        ..rotate(p.spin * t)
        ..drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h), const Radius.circular(2)), paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
