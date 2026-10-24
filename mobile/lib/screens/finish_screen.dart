import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../camera/phone_camera.dart';
import '../glasses/glasses_service.dart';
import '../models/recipe.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Celebration screen shown when the user completes a recipe.
class FinishScreen extends StatefulWidget {
  final Recipe recipe;
  final int elapsedSeconds;
  final int visualChecksCount;
  final VoidCallback onBackToHome;

  /// For the optional photo of the finished dish.
  final GlassesService? glassesService;
  final PhoneCamera? phoneCamera;
  final bool allowSimulatedGlasses;
  final Uint8List? dishPhoto;
  final ValueChanged<Uint8List>? onDishPhoto;
  final ValueChanged<String>? onShowToast;

  const FinishScreen({
    super.key,
    required this.recipe,
    required this.elapsedSeconds,
    required this.visualChecksCount,
    required this.onBackToHome,
    this.glassesService,
    this.phoneCamera,
    this.allowSimulatedGlasses = false,
    this.dishPhoto,
    this.onDishPhoto,
    this.onShowToast,
  });

  @override
  State<FinishScreen> createState() => _FinishScreenState();
}

enum _PhotoSource { glasses, phone }

class _FinishScreenState extends State<FinishScreen> {
  bool _busy = false;

  /// The user's own glasses when connected, or the Mock Device Kit when
  /// Developer allows simulated glasses.
  bool get _glassesReady {
    final glasses = widget.glassesService;
    if (glasses == null) return false;
    return glasses.usingRealGlasses
        ? glasses.connectionState == GlassesConnectionState.connectedHardware
        : widget.allowSimulatedGlasses && glasses.isConnected;
  }

  /// With glasses connected, asks which camera to use; otherwise the phone.
  Future<void> _takeDishPhoto() async {
    var source = _PhotoSource.phone;
    if (_glassesReady) {
      final picked = await showModalBottomSheet<_PhotoSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('With my glasses'),
                onTap: () => Navigator.pop(context, _PhotoSource.glasses),
              ),
              ListTile(
                leading: const Icon(Icons.smartphone_rounded),
                title: const Text('With my phone'),
                onTap: () => Navigator.pop(context, _PhotoSource.phone),
              ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      source = picked;
    }

    setState(() => _busy = true);
    final photo = source == _PhotoSource.glasses
        ? await _fromGlasses()
        : await _fromPhone();
    if (!mounted) return;
    setState(() => _busy = false);
    if (photo != null) widget.onDishPhoto?.call(photo);
  }

  Future<Uint8List?> _fromGlasses() async {
    try {
      final capture = await widget.glassesService!.captureFrame(
        recipe: widget.recipe,
        stepIndex: widget.recipe.steps.length - 1,
      );
      final bytes = capture.jpegBytes;
      // The Mock Device Kit may send a placeholder too small to show.
      if (bytes == null) {
        widget.onShowToast?.call('The simulated glasses sent no image.');
      }
      return bytes;
    } on GlassesCaptureException catch (e) {
      widget.onShowToast?.call(e.message);
      return null;
    }
  }

  Future<Uint8List?> _fromPhone() async {
    final camera = widget.phoneCamera;
    if (camera == null) {
      widget.onShowToast?.call('No camera is available on this device.');
      return null;
    }
    try {
      // Null when the camera was closed without a photo.
      return await camera.takePhoto();
    } on PhoneCameraException catch (e) {
      widget.onShowToast?.call(e.message);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final recipe = widget.recipe;
    final minutes = (widget.elapsedSeconds / 60).ceil().clamp(1, 999);
    final photo = widget.dishPhoto;
    final canTakePhoto = widget.onDishPhoto != null;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CookTogetherTheme.gutter),
              child: Column(
                children: [
                  if (photo != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        CookTogetherTheme.radiusCard,
                      ),
                      child: Image.memory(
                        photo,
                        width: double.infinity,
                        height: 220,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => EmojiTile(
                          emoji: recipe.icon,
                          tone: recipe.tone,
                          size: 120,
                        ),
                      ),
                    )
                  else
                    EmojiTile(emoji: recipe.icon, tone: recipe.tone, size: 120),
                  const SizedBox(height: 28),
                  Text(
                    'You made it!',
                    textAlign: TextAlign.center,
                    style: textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    recipe.name,
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      color: CookTogetherTheme.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      _Stat(value: '${recipe.steps.length}', label: 'steps'),
                      _Stat(
                        value: '$minutes',
                        label: minutes == 1 ? 'minute' : 'minutes',
                      ),
                      _Stat(
                        value: '${widget.visualChecksCount}',
                        label: widget.visualChecksCount == 1
                            ? 'check'
                            : 'checks',
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    photo != null
                        ? 'Saved with your photo in your history.'
                        : 'Saved to your history.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium,
                  ),
                  if (canTakePhoto) ...[
                    const SizedBox(height: 8),
                    _busy
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                          )
                        : TextButton.icon(
                            onPressed: _takeDishPhoto,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: Text(
                              photo != null
                                  ? 'Retake photo'
                                  : 'Take a photo of your dish',
                            ),
                          ),
                  ],
                ],
              ),
            ),
          ),
        ),
        BottomActionBar(
          child: PrimaryButton(label: 'Done', onPressed: widget.onBackToHome),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(label, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
