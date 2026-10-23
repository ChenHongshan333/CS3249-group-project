import 'dart:typed_data';

/// Represents who sent a message in the CookTogether conversational UI.
enum MessageSender { ai, user, system }

/// Visual check status matching `docs/api.md` (`"done"`, `"not_yet"`, `"unsure"`).
enum VisualCheckStatus {
  done('done', 'Looks ready', 'Step check looks good'),
  notYet('not_yet', 'Not quite yet', 'Keep going a little longer'),
  unsure('unsure', 'Needs clearer view', 'Adjust your glasses angle');

  final String wireValue;
  final String badgeLabel;
  final String subtitle;

  const VisualCheckStatus(this.wireValue, this.badgeLabel, this.subtitle);

  static VisualCheckStatus fromWire(String? raw) {
    return switch (raw) {
      'done' => VisualCheckStatus.done,
      'not_yet' => VisualCheckStatus.notYet,
      'unsure' => VisualCheckStatus.unsure,
      _ => VisualCheckStatus.done,
    };
  }
}

/// Listening mode on the active Cooking screen.
enum VoiceListeningMode { handsFree, tapToSpeak }

/// Real-time state of the Voice Orb & Assistant on the Cooking screen.
enum VoiceActivityState { idle, listening, capturingVision, thinking, speaking }

/// Snapshot captured from Meta glasses (via `meta_wearables_dat_flutter` Mock Device Kit)
/// or phone camera fallback during a visual check or visual question.
class VisionCapture {
  final String id;
  final String recipeId;
  final int stepIndex;
  final String source; // 'glasses' or 'phone'
  final String deviceName;
  final String sceneDescription;
  final String recipeIcon;
  final String recipeTone;
  final Uint8List? jpegBytes;
  final String base64Jpeg;
  final DateTime capturedAt;
  final VisualCheckStatus status;
  final String? userQuestion;

  const VisionCapture({
    required this.id,
    required this.recipeId,
    required this.stepIndex,
    required this.source,
    required this.deviceName,
    required this.sceneDescription,
    required this.recipeIcon,
    required this.recipeTone,
    this.jpegBytes,
    required this.base64Jpeg,
    required this.capturedAt,
    this.status = VisualCheckStatus.done,
    this.userQuestion,
  });

  VisionCapture copyWith({
    VisualCheckStatus? status,
    String? sceneDescription,
  }) {
    return VisionCapture(
      id: id,
      recipeId: recipeId,
      stepIndex: stepIndex,
      source: source,
      deviceName: deviceName,
      sceneDescription: sceneDescription ?? this.sceneDescription,
      recipeIcon: recipeIcon,
      recipeTone: recipeTone,
      jpegBytes: jpegBytes,
      base64Jpeg: base64Jpeg,
      capturedAt: capturedAt,
      status: status ?? this.status,
      userQuestion: userQuestion,
    );
  }
}

/// A single turn in the Cooking screen's conversational stream.
class ChatMessage {
  final String id;
  final MessageSender sender;
  final String text;
  final DateTime timestamp;
  final VisionCapture? visionCapture;
  final bool isStepAnnouncement;
  final int? stepIndex;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.visionCapture,
    this.isStepAnnouncement = false,
    this.stepIndex,
  });
}

/// An active or paused kitchen timer during cooking.
class CookingTimer {
  final String id;
  final String label;
  final int totalSeconds;
  final int remainingSeconds;
  final bool isRunning;

  const CookingTimer({
    required this.id,
    required this.label,
    required this.totalSeconds,
    required this.remainingSeconds,
    this.isRunning = true,
  });

  bool get isFinished => remainingSeconds <= 0;

  double get progress =>
      totalSeconds > 0 ? (totalSeconds - remainingSeconds) / totalSeconds : 1.0;

  String get formattedRemaining {
    final mins = remainingSeconds ~/ 60;
    final secs = remainingSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  CookingTimer copyWith({
    String? label,
    int? totalSeconds,
    int? remainingSeconds,
    bool? isRunning,
  }) {
    return CookingTimer(
      id: id,
      label: label ?? this.label,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}
