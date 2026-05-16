import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/constants/app_text_styles.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/widgets/camera_preview_dialog.dart';
import 'package:smartfit/core/widgets/safe_network_image.dart';
import 'package:smartfit/features/auth/providers/auth_provider.dart';
import 'package:smartfit/features/profile/data/models/user_profile_model.dart';
import 'package:smartfit/features/profile/providers/profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  int _step = 0; // 0: gender+photo, 1: body measurements, 2: style preferences
  final _totalSteps = 3;

  // Step 0 — Gender + Photo
  String? _gender;
  Uint8List? _avatarBytes;
  final _phoneCtrl = TextEditingController();

  // Step 1 — Body
  String _selectedBodyType = 'Athletic';
  double _height = 170;
  double _weight = 70;
  double _chest = 90;
  double _waist = 76;
  double _hip = 94;

  // Step 2 — Style + Skin
  String _skinTone = 'Medium';
  final List<String> _selectedStyles = [];

  final _skinTones = ['Fair', 'Light', 'Medium', 'Olive', 'Brown', 'Dark'];
  final _styles = [
    {'label': 'Streetwear', 'icon': Icons.checkroom},
    {'label': 'Clean', 'icon': Icons.auto_awesome},
    {'label': 'Luxury', 'icon': Icons.diamond},
    {'label': 'Casual', 'icon': Icons.weekend},
    {'label': 'Formal', 'icon': Icons.business_center},
    {'label': 'Sporty', 'icon': Icons.fitness_center},
  ];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_step == 0 && _gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your gender')),
      );
      return;
    }
    // Validate phone if provided (must be Pakistani number)
    if (_step == 0 && _phoneCtrl.text.trim().isNotEmpty) {
      final phone = _phoneCtrl.text.trim();
      if (!_isValidPakistaniPhone(phone)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enter a valid Pakistani mobile number (e.g. 03XXXXXXXXX or +923XXXXXXXXX)',
            ),
          ),
        );
        return;
      }
    }
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    } else {
      _finishSetup();
    }
  }

  bool _isValidPakistaniPhone(String input) {
    final p = input.replaceAll(RegExp(r'[^0-9+]'), '');
    // Normalize common variants and check lengths/prefixes
    // Valid examples: 03XXXXXXXXX, +923XXXXXXXXX, 00923XXXXXXXXX, 923XXXXXXXXX
    if (p.startsWith('+')) {
      // +923XXXXXXXXX -> +923######### length 13
      return p.length == 13 && p.startsWith('+923');
    }
    if (p.startsWith('0092')) {
      return p.length == 14 && p.startsWith('00923');
    }
    if (p.startsWith('92')) {
      return p.length == 12 && p.startsWith('923');
    }
    // Local format 03XXXXXXXXX (11 chars)
    if (p.startsWith('0')) {
      return p.length == 11 && p.startsWith('03');
    }
    return false;
  }

  String _normalizePakistaniPhone(String input) {
    var p = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('0092')) {
      p = '+${p.substring(2)}'; // 0092 -> +92
    } else if (p.startsWith('92') && !p.startsWith('+')) {
      p = '+$p';
    } else if (p.startsWith('0')) {
      // 03XXXXXXXXX -> +923XXXXXXXXX
      p = '+92${p.substring(1)}';
    }
    return p;
  }

  void _prevStep() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Add Profile Photo',
                style: AppTextStyles.headlineMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_camera_rounded,
                    color: AppColors.primary,
                  ),
                ),
                title: Text(
                  'Take a Photo',
                  style: AppTextStyles.titleMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: AppColors.secondaryContainer,
                  ),
                ),
                title: Text(
                  'Choose from Gallery',
                  style: AppTextStyles.titleMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    if (source == ImageSource.camera) {
      if (!mounted) return;
      final bytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const CameraPreviewDialog(),
      );
      if (bytes != null && mounted) {
        setState(() => _avatarBytes = bytes);
      }
      return;
    }
    final xFile = await picker.pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    if (mounted) setState(() => _avatarBytes = bytes);
  }

  Future<void> _finishSetup() async {
    final authUser = Supabase.instance.client.auth.currentUser;
    final user = ref.read(authNotifierProvider).user;
    final userId = user?.id ?? authUser?.id;
    if (userId == null) {
      if (mounted) context.go(RoutePaths.login);
      return;
    }

    try {
      String? avatarUrl;
      if (_avatarBytes != null) {
        avatarUrl = await ref
            .read(profileNotifierProvider(userId).notifier)
            .uploadAvatar(_avatarBytes!);
      }

      final profile = UserProfileModel(
        id: userId,
        fullName:
            user?.fullName ?? authUser?.userMetadata?['full_name'] as String?,
        dateOfBirth: DateTime.tryParse(
          authUser?.userMetadata?['date_of_birth'] as String? ?? '',
        ),
        gender: _gender,
        phone: _phoneCtrl.text.trim().isNotEmpty
            ? _normalizePakistaniPhone(_phoneCtrl.text.trim())
            : null,
        bodyType: _selectedBodyType,
        heightCm: _height,
        weightKg: _weight,
        chestCm: _chest,
        waistCm: _waist,
        hipCm: _hip,
        skinTone: _skinTone,
        photoUrl: avatarUrl,
        stylePreferences: _selectedStyles,
        profileCompleted: true,
      );
      await ref
          .read(profileNotifierProvider(userId).notifier)
          .updateProfile(profile);

      if (mounted) {
        context.go(RoutePaths.home);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ambient orbs
          Positioned(
            top: 50,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.secondaryFixedDim.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    if (_step > 0)
                      GestureDetector(
                        onTap: _prevStep,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer.withValues(
                              alpha: 0.5,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: AppColors.onSurface,
                            size: 22,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 48),
                    const Spacer(),
                    // Step indicator
                    Text(
                      '${_step + 1}/$_totalSteps',
                      style: AppTextStyles.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 70),
                // Progress bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: List.generate(
                      _totalSteps,
                      (i) => Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsets.only(
                            right: i < _totalSteps - 1 ? 8 : 0,
                          ),
                          decoration: BoxDecoration(
                            color: i <= _step
                                ? AppColors.primary
                                : AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tell us about you',
                        style: AppTextStyles.displayXl.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _stepSubtitle,
                        style: AppTextStyles.bodyLg.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Step content
                Expanded(child: _buildStepContent()),
                // Bottom CTA
                _buildBottomCta(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _stepSubtitle {
    switch (_step) {
      case 0:
        return 'Start with the basics — your gender and a profile photo.';
      case 1:
        return 'Help us find your perfect fit with your measurements.';
      case 2:
        return 'Tell us about your style so we can personalize your experience.';
      default:
        return '';
    }
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildGenderStep();
      case 1:
        return _buildBodyStep();
      case 2:
        return _buildStyleStep();
      default:
        return const SizedBox();
    }
  }

  // ── Step 0: Gender + Photo + Phone ──
  Widget _buildGenderStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Photo
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceContainer,
                      border: Border.all(
                        color: _avatarBytes != null
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                        width: 3,
                      ),
                      boxShadow: [
                        if (_avatarBytes != null)
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                      ],
                    ),
                    child: ClipOval(
                      child: _avatarBytes != null
                          ? Image.memory(
                              _avatarBytes!,
                              fit: BoxFit.cover,
                              width: 120,
                              height: 120,
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate,
                                  size: 32,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Add photo',
                                  style: AppTextStyles.labelSm.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Gender Selection
          Text(
            'GENDER',
            style: AppTextStyles.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _genderCard('Male', Icons.male)),
              const SizedBox(width: 16),
              Expanded(child: _genderCard('Female', Icons.female)),
            ],
          ),
          const SizedBox(height: 24),

          // Phone (optional)
          Text(
            'PHONE (OPTIONAL)',
            style: AppTextStyles.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: AppColors.surfaceContainerLow,
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[+\d]')),
              ],
              style: AppTextStyles.bodyLg.copyWith(color: AppColors.onSurface),
              decoration: InputDecoration(
                hintText: '+92 3XX XXXXXXX',
                hintStyle: AppTextStyles.bodyLg.copyWith(
                  color: AppColors.outline.withValues(alpha: 0.6),
                ),
                prefixIcon: const Icon(
                  Icons.phone_outlined,
                  color: AppColors.outline,
                  size: 22,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _genderCard(String label, IconData icon) {
    final isSelected = _gender == label;
    return GestureDetector(
      onTap: () => setState(() => _gender = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryContainer.withValues(alpha: 0.1)
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: isSelected
                  ? AppColors.primary
                  : AppColors.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.titleMd.copyWith(
                color: isSelected ? AppColors.primary : AppColors.onSurface,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Icon(Icons.check_circle, size: 20, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }

  // ── Step 1: Body Type + Measurements ──
  Widget _buildBodyStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BODY TYPE',
            style: AppTextStyles.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: ['Slim', 'Athletic', 'Broad']
                  .map(
                    (type) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _bodyTypeCard(type),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
          _sliderCard(
            'HEIGHT',
            _height,
            140,
            220,
            'cm',
            AppColors.primary,
            Icons.height,
            (v) => setState(() => _height = v),
          ),
          const SizedBox(height: 16),
          _sliderCard(
            'WEIGHT',
            _weight,
            40,
            150,
            'kg',
            AppColors.secondary,
            Icons.monitor_weight_outlined,
            (v) => setState(() => _weight = v),
          ),
          const SizedBox(height: 16),
          // Chest/Waist/Hip
          Text(
            'BODY MEASUREMENTS',
            style: AppTextStyles.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _miniSlider(
            'Chest',
            _chest,
            60,
            140,
            (v) => setState(() => _chest = v),
          ),
          _miniSlider(
            'Waist',
            _waist,
            50,
            130,
            (v) => setState(() => _waist = v),
          ),
          _miniSlider('Hip', _hip, 60, 140, (v) => setState(() => _hip = v)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _bodyTypeCard(String type) {
    final isSelected = _selectedBodyType == type;
    final images = {
      'Slim':
          'https://images.unsplash.com/photo-1516257984-b1b4d707412e?q=80&w=300&auto=format&fit=crop',
      'Athletic':
          'https://images.unsplash.com/photo-1583485088034-697b5bc54ccd?q=80&w=300&auto=format&fit=crop',
      'Broad':
          'https://images.unsplash.com/photo-1616847209176-788df0a5eab4?q=80&w=300&auto=format&fit=crop',
    };
    return GestureDetector(
      onTap: () => setState(() => _selectedBodyType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? AppColors.primaryContainer.withValues(alpha: 0.1)
              : AppColors.surfaceContainer.withValues(alpha: 0.5),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: SafeNetworkImage(
                  imageUrl: images[type]!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 120,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  if (isSelected) const SizedBox(width: 4),
                  Text(
                    type,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderCard(
    String label,
    double value,
    double min,
    double max,
    String unit,
    Color color,
    IconData icon,
    ValueChanged<double> onChanged,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.05),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: AppTextStyles.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${value.round()} $unit',
                    style: AppTextStyles.headlineMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 8,
                  activeTrackColor: color.withValues(alpha: 0.8),
                  inactiveTrackColor: AppColors.surfaceContainerHigh,
                  thumbColor: AppColors.surface,
                  overlayColor: color.withValues(alpha: 0.2),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 12,
                  ),
                ),
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.6),
                inactiveTrackColor: AppColors.surfaceContainerHigh,
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withValues(alpha: 0.1),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '${value.round()} cm',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Style + Skin Tone ──
  Widget _buildStyleStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skin Tone
          Text(
            'SKIN TONE',
            style: AppTextStyles.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _skinTones.map((tone) {
              final isSelected = _skinTone == tone;
              final toneColors = {
                'Fair': const Color(0xFFFCE4D6),
                'Light': const Color(0xFFF5D0B0),
                'Medium': const Color(0xFFD4A574),
                'Olive': const Color(0xFFB08D57),
                'Brown': const Color(0xFF8B6914),
                'Dark': const Color(0xFF5C4033),
              };
              return GestureDetector(
                onTap: () => setState(() => _skinTone = tone),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.outlineVariant.withValues(alpha: 0.3),
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 20,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: toneColors[tone],
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tone,
                        style: AppTextStyles.labelCaps.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),

          // Style Preferences
          Text(
            'AESTHETIC CORE',
            style: AppTextStyles.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick the styles that resonate with you',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _styles.map((s) {
              final label = s['label'] as String;
              final icon = s['icon'] as IconData;
              final isSelected = _selectedStyles.contains(label);
              return GestureDetector(
                onTap: () => setState(() {
                  if (isSelected) {
                    _selectedStyles.remove(label);
                  } else {
                    _selectedStyles.add(label);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.outlineVariant.withValues(alpha: 0.3),
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 25,
                              offset: const Offset(0, 10),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.bodyLg.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        icon,
                        size: 18,
                        color: isSelected
                            ? Colors.white
                            : AppColors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Bottom CTA ──
  Widget _buildBottomCta() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            AppColors.background,
            AppColors.background.withValues(alpha: 0.9),
            Colors.transparent,
          ],
        ),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(9999),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 40,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          onPressed: _nextStep,
          child: Text(
            _step == _totalSteps - 1 ? 'Go' : 'Continue',
            style: AppTextStyles.headlineMd.copyWith(
              color: Colors.white,
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
  }
}
