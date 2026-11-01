import 'dart:convert';

/// The team's deployed backend. Clear the URL under Profile → Developer to
/// use the built-in demo answers instead.
const String kDefaultBackendUrl = 'https://cookalong-backend.onrender.com';

/// User preferences persisted locally in SharedPreferences.
class UserPreferences {
  final bool voiceGuidance;
  final bool showCaptions;
  final bool handsFreeListening;
  final String serverBaseUrl;

  /// Developer only: take step photos from the Mock Device Kit instead of
  /// the phone camera when no real glasses are connected.
  final bool simulatedGlassesPhotos;

  /// Developer only: record speech with the phone's mic even when the
  /// glasses are connected, for when their mic link keeps dropping (#40).
  final bool phoneMicOnly;

  /// Developer only: every step check gives this result (a
  /// VisualCheckStatus wire value) without a photo or the backend, so demos
  /// and tests work without a camera. Empty means off.
  final String forcedCheckResult;

  /// User study only: recipes open as a plain step list on the phone, with
  /// no voice, glasses or AI (condition B).
  final bool phoneRecipeMode;

  /// Selected TTS voice name, or empty string for the default system voice.
  final String ttsVoiceName;

  /// Selected TTS voice locale (default 'en-US').
  final String ttsVoiceLocale;

  /// Pitch multiplier for spoken assistant voice (default 1.0).
  final double ttsPitch;

  /// Speech rate multiplier for spoken assistant voice (default 0.48).
  final double ttsRate;

  /// Voice Activity Detection (VAD) fixed RMS energy floor (default 0.012).
  final double vadFixedFloor;

  /// Voice Activity Detection (VAD) adaptive noise floor multiplier (default 2.2).
  final double vadNoiseMultiplier;

  const UserPreferences({
    this.voiceGuidance = true,
    this.showCaptions = true,
    this.handsFreeListening = true,
    this.serverBaseUrl = kDefaultBackendUrl,
    this.simulatedGlassesPhotos = false,
    this.phoneMicOnly = false,
    this.forcedCheckResult = '',
    this.phoneRecipeMode = false,
    this.ttsVoiceName = '',
    this.ttsVoiceLocale = 'en-US',
    this.ttsPitch = 1.0,
    this.ttsRate = 0.48,
    this.vadFixedFloor = 0.012,
    this.vadNoiseMultiplier = 2.2,
  });

  UserPreferences copyWith({
    bool? voiceGuidance,
    bool? showCaptions,
    bool? handsFreeListening,
    String? serverBaseUrl,
    bool? simulatedGlassesPhotos,
    bool? phoneMicOnly,
    String? forcedCheckResult,
    bool? phoneRecipeMode,
    String? ttsVoiceName,
    String? ttsVoiceLocale,
    double? ttsPitch,
    double? ttsRate,
    double? vadFixedFloor,
    double? vadNoiseMultiplier,
  }) {
    return UserPreferences(
      voiceGuidance: voiceGuidance ?? this.voiceGuidance,
      showCaptions: showCaptions ?? this.showCaptions,
      handsFreeListening: handsFreeListening ?? this.handsFreeListening,
      serverBaseUrl: serverBaseUrl ?? this.serverBaseUrl,
      simulatedGlassesPhotos:
          simulatedGlassesPhotos ?? this.simulatedGlassesPhotos,
      phoneMicOnly: phoneMicOnly ?? this.phoneMicOnly,
      forcedCheckResult: forcedCheckResult ?? this.forcedCheckResult,
      phoneRecipeMode: phoneRecipeMode ?? this.phoneRecipeMode,
      ttsVoiceName: ttsVoiceName ?? this.ttsVoiceName,
      ttsVoiceLocale: ttsVoiceLocale ?? this.ttsVoiceLocale,
      ttsPitch: ttsPitch ?? this.ttsPitch,
      ttsRate: ttsRate ?? this.ttsRate,
      vadFixedFloor: vadFixedFloor ?? this.vadFixedFloor,
      vadNoiseMultiplier: vadNoiseMultiplier ?? this.vadNoiseMultiplier,
    );
  }

  Map<String, dynamic> toJson() => {
    'voiceGuidance': voiceGuidance,
    'showCaptions': showCaptions,
    'handsFreeListening': handsFreeListening,
    'serverBaseUrl': serverBaseUrl,
    'simulatedGlassesPhotos': simulatedGlassesPhotos,
    'phoneMicOnly': phoneMicOnly,
    'forcedCheckResult': forcedCheckResult,
    'phoneRecipeMode': phoneRecipeMode,
    'ttsVoiceName': ttsVoiceName,
    'ttsVoiceLocale': ttsVoiceLocale,
    'ttsPitch': ttsPitch,
    'ttsRate': ttsRate,
    'vadFixedFloor': vadFixedFloor,
    'vadNoiseMultiplier': vadNoiseMultiplier,
  };

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      voiceGuidance: json['voiceGuidance'] as bool? ?? true,
      showCaptions: json['showCaptions'] as bool? ?? true,
      handsFreeListening: json['handsFreeListening'] as bool? ?? true,
      serverBaseUrl: json['serverBaseUrl'] as String? ?? kDefaultBackendUrl,
      simulatedGlassesPhotos: json['simulatedGlassesPhotos'] as bool? ?? false,
      phoneMicOnly: json['phoneMicOnly'] as bool? ?? false,
      forcedCheckResult: json['forcedCheckResult'] as String? ?? '',
      phoneRecipeMode: json['phoneRecipeMode'] as bool? ?? false,
      ttsVoiceName: json['ttsVoiceName'] as String? ?? '',
      ttsVoiceLocale: json['ttsVoiceLocale'] as String? ?? 'en-US',
      ttsPitch: (json['ttsPitch'] as num?)?.toDouble() ?? 1.0,
      ttsRate: (json['ttsRate'] as num?)?.toDouble() ?? 0.48,
      vadFixedFloor: (json['vadFixedFloor'] as num?)?.toDouble() ?? 0.012,
      vadNoiseMultiplier:
          (json['vadNoiseMultiplier'] as num?)?.toDouble() ?? 2.2,
    );
  }

  String encode() => jsonEncode(toJson());

  static UserPreferences decode(String? raw) {
    if (raw == null || raw.isEmpty) return const UserPreferences();
    try {
      return UserPreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const UserPreferences();
    }
  }
}

/// Completed cooking session saved in History.
class CookingHistoryItem {
  final String id;
  final String recipeId;
  final String recipeName;
  final String recipeIcon;
  final String date;
  final int durationSeconds;
  final int stepsCompleted;
  final int visualChecksCount;

  const CookingHistoryItem({
    required this.id,
    required this.recipeId,
    required this.recipeName,
    required this.recipeIcon,
    required this.date,
    required this.durationSeconds,
    required this.stepsCompleted,
    required this.visualChecksCount,
  });

  int get durationMinutes => (durationSeconds / 60).ceil().clamp(1, 999);

  Map<String, dynamic> toJson() => {
    'id': id,
    'recipeId': recipeId,
    'recipeName': recipeName,
    'recipeIcon': recipeIcon,
    'date': date,
    'durationSeconds': durationSeconds,
    'stepsCompleted': stepsCompleted,
    'visualChecksCount': visualChecksCount,
  };

  factory CookingHistoryItem.fromJson(Map<String, dynamic> json) {
    return CookingHistoryItem(
      id: json['id'] as String? ?? '',
      recipeId: json['recipeId'] as String? ?? 'salad',
      recipeName: json['recipeName'] as String? ?? 'Rainbow salad bowl',
      recipeIcon: json['recipeIcon'] as String? ?? '🥗',
      date: json['date'] as String? ?? 'Today',
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 60,
      stepsCompleted: (json['stepsCompleted'] as num?)?.toInt() ?? 4,
      visualChecksCount: (json['visualChecksCount'] as num?)?.toInt() ?? 1,
    );
  }

  static String encodeList(List<CookingHistoryItem> items) =>
      jsonEncode(items.map((item) => item.toJson()).toList());

  static List<CookingHistoryItem> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(CookingHistoryItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
