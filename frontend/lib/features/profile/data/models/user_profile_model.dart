class UserProfileModel {
  final String id;
  final String? fullName;
  final String? username;
  final String? email;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? phone;
  final double? heightCm;
  final double? weightKg;
  final String? bodyType;
  final String? skinTone;
  final String? photoUrl;
  final double? chestCm;
  final double? waistCm;
  final double? hipCm;
  final String? ethnicity;

  /// warm / cool / neutral (skin tone analyzer, 21 Nov 2026) and the size the user usually
  /// buys (XS..4XL). Saved apart from the main profile (see [extrasJson]).
  final String? skinUndertone;
  final String? usualSize;
  final List<String> stylePreferences;
  final List<String> preferredColors;
  final int? budgetMin;
  final int? budgetMax;
  final List<String> occasions;
  final bool profileCompleted;
  final bool isBanned;
  final String? banReason;

  const UserProfileModel({
    required this.id,
    this.fullName,
    this.username,
    this.email,
    this.dateOfBirth,
    this.gender,
    this.phone,
    this.heightCm,
    this.weightKg,
    this.bodyType,
    this.skinTone,
    this.photoUrl,
    this.chestCm,
    this.waistCm,
    this.hipCm,
    this.ethnicity,
    this.skinUndertone,
    this.usualSize,
    this.stylePreferences = const [],
    this.preferredColors = const [],
    this.budgetMin,
    this.budgetMax,
    this.occasions = const [],
    this.profileCompleted = false,
    this.isBanned = false,
    this.banReason,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    // Support older/newer DB column variants (e.g. `height` vs `height_cm`, `avatar_url` vs `photo_url`).
    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v == 1;
      if (v is String) {
        final normalized = v.trim().toLowerCase();
        return normalized == 'true' || normalized == 't' || normalized == '1';
      }
      return false;
    }

    List<String> parseStringList(dynamic v) {
      if (v is List) {
        return v
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toList();
      }
      if (v is String && v.trim().isNotEmpty) {
        return [v.trim()];
      }
      return [];
    }

    final heightVal = json['height_cm'] ?? json['height'];
    final weightVal = json['weight_kg'] ?? json['weight'];
    final photoVal = json['photo_url'] ?? json['avatar_url'];
    final chestVal = json['chest_cm'] ?? json['chest'];
    final waistVal = json['waist_cm'] ?? json['waist'];
    final hipVal = json['hip_cm'] ?? json['hip'];

    return UserProfileModel(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      username: json['username'] as String?,
      email: json['email'] as String?,
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'] as String)
          : null,
      gender: json['gender'] as String?,
      phone: json['phone'] as String?,
      heightCm: parseDouble(heightVal),
      weightKg: parseDouble(weightVal),
      bodyType: json['body_type'] as String?,
      skinTone: json['skin_tone'] as String?,
      photoUrl: photoVal as String?,
      chestCm: parseDouble(chestVal),
      waistCm: parseDouble(waistVal),
      hipCm: parseDouble(hipVal),
      ethnicity: json['ethnicity'] as String?,
      skinUndertone: json['skin_undertone'] as String?,
      usualSize: json['usual_size'] as String?,
      stylePreferences: parseStringList(
        json['style_preferences'] ?? json['style_vibe'],
      ),
      preferredColors: parseStringList(json['preferred_colors']),
      budgetMin: json['budget_min'] as int?,
      budgetMax: json['budget_max'] as int?,
      occasions: parseStringList(json['occasions']),
      profileCompleted: parseBool(
        json['profile_completed'] ?? json['is_complete'],
      ),
      isBanned: parseBool(json['is_banned']),
      banReason: json['ban_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'username': username,
    'email': email,
    'date_of_birth': dateOfBirth?.toIso8601String(),
    'gender': gender,
    'phone': phone,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'body_type': bodyType,
    'skin_tone': skinTone,
    'photo_url': photoUrl,
    'avatar_url': photoUrl,
    'chest_cm': chestCm,
    'waist_cm': waistCm,
    'hip_cm': hipCm,
    'ethnicity': ethnicity,
    'style_preferences': stylePreferences,
    'preferred_colors': preferredColors,
    'budget_min': budgetMin,
    'budget_max': budgetMax,
    'occasions': occasions,
    'profile_completed': profileCompleted,
    // skin_undertone / usual_size are NOT here: until migration 20261121000100 is applied
    // the columns don't exist, and an unknown column makes the save fall back to the legacy
    // format, which drops most fields. They go through [extrasJson] instead.
    // is_banned / ban_reason are admin-only and never sent from a profile
    // save — otherwise any save could overwrite moderation state.
  };

  Map<String, dynamic> toLegacyJson() => {
    'id': id,
    if (fullName != null) 'full_name': fullName,
    if (username != null) 'username': username,
    if (email != null) 'email': email,
    if (dateOfBirth != null) 'date_of_birth': dateOfBirth!.toIso8601String(),
    if (gender != null) 'gender': gender,
    if (heightCm != null) 'height': heightCm,
    if (weightKg != null) 'weight': weightKg,
    if (bodyType != null) 'body_type': bodyType,
    if (photoUrl != null) 'avatar_url': photoUrl,
    if (stylePreferences.isNotEmpty) 'style_vibe': stylePreferences.first,
    if (ethnicity != null) 'ethnicity': ethnicity,
    'profile_completed': profileCompleted,
  };

  /// The fields saved separately, best effort (ProfileRepository.saveExtras).
  Map<String, dynamic> extrasJson() => {'skin_undertone': skinUndertone, 'usual_size': usualSize};

  bool get isProfileComplete {
    // A date of birth is required (SRDS SFR-001: 15+). Google sign-ups never
    // have one until they finish onboarding, so a brand-new Google account
    // always gets the profile setup once, whatever else the row says.
    if (dateOfBirth == null) return false;
    if (profileCompleted) return true;

    final hasGender = gender != null && gender!.trim().isNotEmpty;
    final hasPhone = phone != null && phone!.trim().isNotEmpty;
    final hasPhoto = photoUrl != null && photoUrl!.trim().isNotEmpty;
    final hasBodyType = bodyType != null && bodyType!.trim().isNotEmpty;
    final hasHeight = heightCm != null && heightCm! > 0;
    final hasWeight = weightKg != null && weightKg! > 0;
    final hasMeasurements =
        chestCm != null &&
        chestCm! > 0 &&
        waistCm != null &&
        waistCm! > 0 &&
        hipCm != null &&
        hipCm! > 0;
    final hasSkinTone = skinTone != null && skinTone!.trim().isNotEmpty;
    final hasEthnicity = ethnicity != null && ethnicity!.trim().isNotEmpty;
    final hasStyle = stylePreferences.isNotEmpty;

    return hasGender &&
        hasPhone &&
        hasPhoto &&
        hasBodyType &&
        hasHeight &&
        hasWeight &&
        hasMeasurements &&
        hasSkinTone &&
        hasEthnicity &&
        hasStyle;
  }

  UserProfileModel copyWith({
    String? fullName,
    String? username,
    String? email,
    DateTime? dateOfBirth,
    String? gender,
    String? phone,
    double? heightCm,
    double? weightKg,
    String? bodyType,
    String? skinTone,
    String? photoUrl,
    double? chestCm,
    double? waistCm,
    double? hipCm,
    String? ethnicity,
    String? skinUndertone,
    String? usualSize,
    List<String>? stylePreferences,
    List<String>? preferredColors,
    int? budgetMin,
    int? budgetMax,
    List<String>? occasions,
    bool? profileCompleted,
    bool? isBanned,
    String? banReason,
  }) {
    return UserProfileModel(
      id: id,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      email: email ?? this.email,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      phone: phone ?? this.phone,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      bodyType: bodyType ?? this.bodyType,
      skinTone: skinTone ?? this.skinTone,
      photoUrl: photoUrl ?? this.photoUrl,
      chestCm: chestCm ?? this.chestCm,
      waistCm: waistCm ?? this.waistCm,
      hipCm: hipCm ?? this.hipCm,
      ethnicity: ethnicity ?? this.ethnicity,
      skinUndertone: skinUndertone ?? this.skinUndertone,
      usualSize: usualSize ?? this.usualSize,
      stylePreferences: stylePreferences ?? this.stylePreferences,
      preferredColors: preferredColors ?? this.preferredColors,
      budgetMin: budgetMin ?? this.budgetMin,
      budgetMax: budgetMax ?? this.budgetMax,
      occasions: occasions ?? this.occasions,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      isBanned: isBanned ?? this.isBanned,
      banReason: banReason ?? this.banReason,
    );
  }
}
