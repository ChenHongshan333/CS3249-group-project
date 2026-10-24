import 'dart:convert';

/// The team's deployed backend. Clear the URL under Profile → Developer to
/// use the built-in demo answers instead.
const String kDefaultBackendUrl = 'https://cookalong-backend.onrender.com';

/// User preferences persisted locally in SharedPreferences.
class UserPreferences {
  final String level;
  final String diet;
  final bool voiceGuidance;
  final bool showCaptions;
  final bool handsFreeListening;
  final String serverBaseUrl;

  /// Developer only: take step photos from the Mock Device Kit instead of
  /// the phone camera when no real glasses are connected.
  final bool simulatedGlassesPhotos;

  /// Developer only: every step check gives this result (a
  /// VisualCheckStatus wire value) without a photo or the backend, so demos
  /// and tests work without a camera. Empty means off.
  final String forcedCheckResult;

  const UserPreferences({
    this.level = 'I know a few basics',
    this.diet = 'No restrictions',
    this.voiceGuidance = true,
    this.showCaptions = true,
    this.handsFreeListening = true,
    this.serverBaseUrl = kDefaultBackendUrl,
    this.simulatedGlassesPhotos = false,
    this.forcedCheckResult = '',
  });

  UserPreferences copyWith({
    String? level,
    String? diet,
    bool? voiceGuidance,
    bool? showCaptions,
    bool? handsFreeListening,
    String? serverBaseUrl,
    bool? simulatedGlassesPhotos,
    String? forcedCheckResult,
  }) {
    return UserPreferences(
      level: level ?? this.level,
      diet: diet ?? this.diet,
      voiceGuidance: voiceGuidance ?? this.voiceGuidance,
      showCaptions: showCaptions ?? this.showCaptions,
      handsFreeListening: handsFreeListening ?? this.handsFreeListening,
      serverBaseUrl: serverBaseUrl ?? this.serverBaseUrl,
      simulatedGlassesPhotos:
          simulatedGlassesPhotos ?? this.simulatedGlassesPhotos,
      forcedCheckResult: forcedCheckResult ?? this.forcedCheckResult,
    );
  }

  Map<String, dynamic> toJson() => {
    'level': level,
    'diet': diet,
    'voiceGuidance': voiceGuidance,
    'showCaptions': showCaptions,
    'handsFreeListening': handsFreeListening,
    'serverBaseUrl': serverBaseUrl,
    'simulatedGlassesPhotos': simulatedGlassesPhotos,
    'forcedCheckResult': forcedCheckResult,
  };

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      level: json['level'] as String? ?? 'I know a few basics',
      diet: json['diet'] as String? ?? 'No restrictions',
      voiceGuidance: json['voiceGuidance'] as bool? ?? true,
      showCaptions: json['showCaptions'] as bool? ?? true,
      handsFreeListening: json['handsFreeListening'] as bool? ?? true,
      serverBaseUrl: json['serverBaseUrl'] as String? ?? kDefaultBackendUrl,
      simulatedGlassesPhotos: json['simulatedGlassesPhotos'] as bool? ?? false,
      forcedCheckResult: json['forcedCheckResult'] as String? ?? '',
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
