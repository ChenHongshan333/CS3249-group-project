import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../services/voice_controller.dart';
import '../theme/app_theme.dart';

/// Modal bottom sheet that lets users and developers tune Voice Activity
/// Detection (VAD) fixed floor and adaptive noise multiplier thresholds
/// directly during cooking tests.
class VadTuningSheet extends StatefulWidget {
  final VoiceController voiceController;
  final UserPreferences preferences;
  final ValueChanged<UserPreferences>? onSavePreferences;

  const VadTuningSheet({
    super.key,
    required this.voiceController,
    required this.preferences,
    this.onSavePreferences,
  });

  @override
  State<VadTuningSheet> createState() => _VadTuningSheetState();
}

class _VadTuningSheetState extends State<VadTuningSheet> {
  late double _fixedFloor;
  late double _noiseMultiplier;

  @override
  void initState() {
    super.initState();
    _fixedFloor = widget.voiceController.vadFixedFloor;
    _noiseMultiplier = widget.voiceController.vadNoiseMultiplier;
  }

  void _applyTuning({double? fixedFloor, double? noiseMultiplier}) {
    setState(() {
      if (fixedFloor != null) _fixedFloor = fixedFloor;
      if (noiseMultiplier != null) _noiseMultiplier = noiseMultiplier;
    });

    widget.voiceController.setVadTuning(
      fixedFloor: _fixedFloor,
      noiseMultiplier: _noiseMultiplier,
    );

    final updated = widget.preferences.copyWith(
      vadFixedFloor: _fixedFloor,
      vadNoiseMultiplier: _noiseMultiplier,
    );
    widget.onSavePreferences?.call(updated);
  }

  void _applyPreset(String name, double floor, double multiplier) {
    _applyTuning(fixedFloor: floor, noiseMultiplier: multiplier);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: const BoxDecoration(
        color: CookTogetherTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CookTogetherTheme.gutter,
            12,
            CookTogetherTheme.gutter,
            24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: CookTogetherTheme.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title row with Reset button
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    color: CookTogetherTheme.ink,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Voice Detection Tuning',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: CookTogetherTheme.ink,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _applyTuning(fixedFloor: 0.012, noiseMultiplier: 2.2);
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reset'),
                    style: TextButton.styleFrom(
                      foregroundColor: CookTogetherTheme.inkMuted,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Adjust microphone sensitivity in real time to test whisper detection or noisy room rejection.',
                style: textTheme.bodySmall?.copyWith(
                  color: CookTogetherTheme.inkMuted,
                ),
              ),

              const SizedBox(height: 16),

              // Status badges
              ListenableBuilder(
                listenable: widget.voiceController,
                builder: (context, _) {
                  final isWhisper = widget.voiceController.isUsingWhisper;
                  final micName =
                      widget.voiceController.bluetoothMic ?? 'Phone microphone';
                  return Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isWhisper
                              ? CookTogetherTheme.successSoft
                              : CookTogetherTheme.line.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isWhisper
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              size: 14,
                              color: isWhisper
                                  ? CookTogetherTheme.success
                                  : CookTogetherTheme.inkMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isWhisper ? 'VAD Active' : 'VAD Standby',
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isWhisper
                                    ? CookTogetherTheme.success
                                    : CookTogetherTheme.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: CookTogetherTheme.line.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.mic_rounded,
                              size: 14,
                              color: CookTogetherTheme.inkMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              micName,
                              style: textTheme.labelSmall?.copyWith(
                                color: CookTogetherTheme.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 18),

              // Slider 1: Fixed RMS Energy Floor
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Fixed Energy Floor',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: CookTogetherTheme.ink,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: CookTogetherTheme.warningSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _fixedFloor.toStringAsFixed(3),
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: CookTogetherTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Minimum RMS sound required to trigger speech. Lower values detect soft whispers and quiet voices; higher values reject kitchen clatter.',
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: CookTogetherTheme.inkMuted,
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: CookTogetherTheme.warning,
                  inactiveTrackColor: CookTogetherTheme.line,
                  thumbColor: CookTogetherTheme.warning,
                ),
                child: Slider(
                  value: _fixedFloor.clamp(0.003, 0.030),
                  min: 0.003,
                  max: 0.030,
                  divisions: 27,
                  label: _fixedFloor.toStringAsFixed(3),
                  onChanged: (val) {
                    final rounded = double.parse(val.toStringAsFixed(3));
                    _applyTuning(fixedFloor: rounded);
                  },
                ),
              ),

              const SizedBox(height: 8),

              // Slider 2: Adaptive Noise Multiplier
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Adaptive Noise Multiplier',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: CookTogetherTheme.ink,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: CookTogetherTheme.warningSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_noiseMultiplier.toStringAsFixed(1)}x',
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: CookTogetherTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'How much louder than background room noise speech must be. Lower is more sensitive in noisy rooms; higher prevents sizzling pans from triggering.',
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: CookTogetherTheme.inkMuted,
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: CookTogetherTheme.warning,
                  inactiveTrackColor: CookTogetherTheme.line,
                  thumbColor: CookTogetherTheme.warning,
                ),
                child: Slider(
                  value: _noiseMultiplier.clamp(1.0, 3.5),
                  min: 1.0,
                  max: 3.5,
                  divisions: 25,
                  label: '${_noiseMultiplier.toStringAsFixed(1)}x',
                  onChanged: (val) {
                    final rounded = double.parse(val.toStringAsFixed(1));
                    _applyTuning(noiseMultiplier: rounded);
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Quick Presets
              Text(
                'Quick Presets:',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: CookTogetherTheme.inkMuted,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _PresetChip(
                    label: 'Default (0.012 / 2.2x)',
                    selected: (_fixedFloor - 0.012).abs() < 0.001 &&
                        (_noiseMultiplier - 2.2).abs() < 0.05,
                    onTap: () => _applyPreset('Default', 0.012, 2.2),
                  ),
                  _PresetChip(
                    label: 'Sensitive / Whisper (0.006 / 1.6x)',
                    selected: (_fixedFloor - 0.006).abs() < 0.001 &&
                        (_noiseMultiplier - 1.6).abs() < 0.05,
                    onTap: () => _applyPreset('Sensitive', 0.006, 1.6),
                  ),
                  _PresetChip(
                    label: 'Glasses / Headset (0.008 / 1.8x)',
                    selected: (_fixedFloor - 0.008).abs() < 0.001 &&
                        (_noiseMultiplier - 1.8).abs() < 0.05,
                    onTap: () => _applyPreset('Glasses', 0.008, 1.8),
                  ),
                  _PresetChip(
                    label: 'Noisy Kitchen (0.018 / 2.8x)',
                    selected: (_fixedFloor - 0.018).abs() < 0.001 &&
                        (_noiseMultiplier - 2.8).abs() < 0.05,
                    onTap: () => _applyPreset('Noisy', 0.018, 2.8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? CookTogetherTheme.warningSoft
              : CookTogetherTheme.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? CookTogetherTheme.warning : CookTogetherTheme.line,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? CookTogetherTheme.warning : CookTogetherTheme.ink,
          ),
        ),
      ),
    );
  }
}
