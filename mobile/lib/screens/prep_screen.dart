import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:meta_wearables_dat_flutter/meta_wearables_dat_flutter.dart';

import '../camera/phone_camera.dart';
import '../glasses/glasses_service.dart';
import '../models/conversation.dart';
import '../models/recipe.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Get ready: gather ingredients, pick optional swaps, check the setup.
/// The ingredient checklist gates the single "Start cooking" action.
class PrepScreen extends StatefulWidget {
  final Recipe recipe;
  final GlassesService glassesService;
  final PhoneCamera? phoneCamera;

  /// Use the Mock Device Kit photo when there are no real glasses, as the
  /// cooking screen does.
  final bool simulatedGlassesPhotos;
  final VoiceListeningMode initialListeningMode;
  final void Function({
    required Set<String> checkedIngredients,
    required VoiceListeningMode listeningMode,
    required Set<String> acceptedSwapIds,
  })
  onStartCookingSession;
  final VoidCallback onBack;
  final ValueChanged<String> onShowToast;

  const PrepScreen({
    super.key,
    required this.recipe,
    required this.glassesService,
    this.phoneCamera,
    this.simulatedGlassesPhotos = false,
    required this.initialListeningMode,
    required this.onStartCookingSession,
    required this.onBack,
    required this.onShowToast,
  });

  @override
  State<PrepScreen> createState() => _PrepScreenState();
}

class _PrepScreenState extends State<PrepScreen> {
  final Set<String> _checkedIngredients = {};
  final Set<String> _acceptedSwapIds = {};
  late VoiceListeningMode _listeningMode;

  int get _remaining =>
      widget.recipe.ingredients.length - _checkedIngredients.length;
  bool get _allIngredientsReady => _remaining == 0;

  @override
  void initState() {
    super.initState();
    _listeningMode = widget.initialListeningMode;
    if (!widget.glassesService.isConnected &&
        !widget.glassesService.usingRealGlasses) {
      widget.glassesService.initializeAndPairMockDevice();
    }
  }

  void _toggleAllIngredients() {
    setState(() {
      if (_allIngredientsReady) {
        _checkedIngredients.clear();
      } else {
        _checkedIngredients.addAll(widget.recipe.ingredients);
      }
    });
  }

  void _openGlassesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GlassesSheet(
        glassesService: widget.glassesService,
        onShowToast: widget.onShowToast,
      ),
    );
  }

  void _openCameraTest() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CameraTestSheet(
        recipe: widget.recipe,
        glassesService: widget.glassesService,
        phoneCamera: widget.phoneCamera,
        simulatedGlassesPhotos: widget.simulatedGlassesPhotos,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final recipe = widget.recipe;
    return Column(
      children: [
        ScreenHeader(title: 'Get ready', onBack: widget.onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CookTogetherTheme.gutter,
              4,
              CookTogetherTheme.gutter,
              24,
            ),
            children: [
              Row(
                children: [
                  EmojiTile(emoji: recipe.icon, tone: recipe.tone, size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(recipe.name, style: textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${recipe.timeMinutes} min · ${recipe.steps.length} steps',
                          style: textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SectionTitle(
                'Ingredients',
                trailing: TextButton(
                  onPressed: _toggleAllIngredients,
                  child: Text(_allIngredientsReady ? 'Clear' : 'Mark all'),
                ),
              ),
              for (final ingredient in recipe.ingredients)
                CheckRow(
                  label: _capitalise(ingredient),
                  checked: _checkedIngredients.contains(ingredient),
                  onTap: () => setState(() {
                    if (!_checkedIngredients.remove(ingredient)) {
                      _checkedIngredients.add(ingredient);
                    }
                  }),
                ),
              if (recipe.swaps.isNotEmpty) ...[
                const SizedBox(height: 32),
                SectionTitle(
                  'Healthier swaps',
                  trailing: Text('Optional', style: textTheme.bodyMedium),
                ),
                for (final swap in recipe.swaps)
                  _SwapRow(
                    swap: swap,
                    accepted: _acceptedSwapIds.contains(swap.id),
                    onChanged: (accepted) => setState(() {
                      if (accepted) {
                        _acceptedSwapIds.add(swap.id);
                      } else {
                        _acceptedSwapIds.remove(swap.id);
                      }
                    }),
                  ),
              ],
              const SizedBox(height: 32),
              const SectionTitle('How I listen'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<VoiceListeningMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: VoiceListeningMode.handsFree,
                      icon: Icon(Icons.hearing_rounded),
                      label: Text('Hands-free'),
                    ),
                    ButtonSegment(
                      value: VoiceListeningMode.tapToSpeak,
                      icon: Icon(Icons.touch_app_outlined),
                      label: Text('Tap to talk'),
                    ),
                  ],
                  selected: {_listeningMode},
                  onSelectionChanged: (s) =>
                      setState(() => _listeningMode = s.first),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _listeningMode == VoiceListeningMode.handsFree
                    ? 'Speak any time, like "next step" or "set a timer".'
                    : 'I only listen after you tap the mic.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              ListenableBuilder(
                listenable: widget.glassesService,
                builder: (context, _) {
                  final glasses = widget.glassesService;
                  return Row(
                    children: [
                      Expanded(
                        child: glasses.isConnected
                            ? StatusDot(
                                label:
                                    '${glasses.deviceName} · ${glasses.batteryLevel}%',
                                color: CookTogetherTheme.success,
                              )
                            : const StatusDot(
                                label: 'Glasses not connected',
                                color: CookTogetherTheme.warning,
                              ),
                      ),
                      TextButton(
                        onPressed: _openGlassesSheet,
                        child: const Text('Change'),
                      ),
                    ],
                  );
                },
              ),
              // Catch camera problems now rather than in the middle of a step.
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _openCameraTest,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Test camera'),
                ),
              ),
            ],
          ),
        ),
        // Ticking is optional: CookAlong asks about whatever is unticked in
        // the opening chat before step 1.
        BottomActionBar(
          hint: _allIngredientsReady
              ? null
              : "I'll ask about the $_remaining you haven't ticked",
          child: PrimaryButton(
            label: 'Start cooking',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => widget.onStartCookingSession(
              checkedIngredients: _checkedIngredients,
              listeningMode: _listeningMode,
              acceptedSwapIds: _acceptedSwapIds,
            ),
          ),
        ),
      ],
    );
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// One healthier swap with a switch: on means "use it".
class _SwapRow extends StatelessWidget {
  final HealthySwap swap;
  final bool accepted;
  final ValueChanged<bool> onChanged;

  const _SwapRow({
    required this.swap,
    required this.accepted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!accepted),
        borderRadius: BorderRadius.circular(CookTogetherTheme.radiusControl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(swap.title, style: textTheme.bodyLarge),
                    // The title says enough to decide; the how-to shows
                    // once the swap is chosen.
                    if (accepted) ...[
                      const SizedBox(height: 2),
                      Text(swap.detail, style: textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(value: accepted, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Takes one photo the way a step check would, and shows it: the glasses
/// when they are real (or simulated photos are on), otherwise the phone.
class _CameraTestSheet extends StatefulWidget {
  final Recipe recipe;
  final GlassesService glassesService;
  final PhoneCamera? phoneCamera;
  final bool simulatedGlassesPhotos;

  const _CameraTestSheet({
    required this.recipe,
    required this.glassesService,
    required this.phoneCamera,
    required this.simulatedGlassesPhotos,
  });

  @override
  State<_CameraTestSheet> createState() => _CameraTestSheetState();
}

class _CameraTestSheetState extends State<_CameraTestSheet> {
  bool _busy = true;
  Uint8List? _photo;
  bool _works = false;
  String _message = '';

  bool get _useGlasses =>
      widget.glassesService.usingRealGlasses || widget.simulatedGlassesPhotos;

  @override
  void initState() {
    super.initState();
    _takePhoto();
  }

  Future<void> _takePhoto() async {
    setState(() {
      _busy = true;
      _photo = null;
    });
    Uint8List? photo;
    var works = false;
    String message;
    if (_useGlasses) {
      try {
        final capture = await widget.glassesService.captureFrame(
          recipe: widget.recipe,
          stepIndex: 0,
        );
        photo = capture.jpegBytes;
        works = true;
        // The Mock Device Kit may send a placeholder too small to show.
        message = photo != null
            ? 'Your camera works. This photo is from ${capture.deviceName}.'
            : 'The simulated glasses work. They send a placeholder, not a '
                  'real photo.';
      } on GlassesCaptureException catch (e) {
        message =
            "${e.message} While cooking, I'll use your phone camera instead.";
      }
    } else {
      final camera = widget.phoneCamera;
      if (camera == null) {
        message = 'No camera is available on this device.';
      } else {
        try {
          photo = await camera.takePhoto();
          works = photo != null;
          message = works
              ? 'Your camera works. This photo is from your phone camera.'
              : 'No photo taken.';
        } on PhoneCameraException catch (e) {
          message = e.message;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _photo = photo;
      _works = works;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final photo = _photo;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CookTogetherTheme.gutter,
          0,
          CookTogetherTheme.gutter,
          16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Camera test', style: textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (_busy)
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _useGlasses
                          ? 'Taking a photo with your glasses…'
                          : 'Take a photo with your phone…',
                      style: textTheme.bodyLarge,
                    ),
                  ),
                ],
              )
            else ...[
              if (photo != null) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      CookTogetherTheme.radiusCard,
                    ),
                    child: Image.memory(
                      photo,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _works
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    color: _works
                        ? CookTogetherTheme.success
                        : CookTogetherTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_message, style: textTheme.bodyLarge)),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (!_busy)
                  TextButton(
                    onPressed: _takePhoto,
                    child: const Text('Try again'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mock Device Kit controls, kept out of the main flow.
class _GlassesSheet extends StatelessWidget {
  static const _modelNames = {
    MockGlassesModel.rayBanMeta: 'Ray-Ban Meta',
    MockGlassesModel.oakleyMetaHSTN: 'Oakley Meta HSTN',
    MockGlassesModel.metaRayBanDisplay: 'Meta Ray-Ban Display',
  };

  final GlassesService glassesService;
  final ValueChanged<String> onShowToast;

  const _GlassesSheet({
    required this.glassesService,
    required this.onShowToast,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: glassesService,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          CookTogetherTheme.gutter,
          0,
          CookTogetherTheme.gutter,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: glassesService.usingRealGlasses
              ? _realGlasses(context)
              : _simulated(context),
        ),
      ),
    );
  }

  List<Widget> _realGlasses(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final connected =
        glassesService.connectionState ==
        GlassesConnectionState.connectedHardware;
    return [
      Text(glassesService.deviceName, style: textTheme.headlineSmall),
      const SizedBox(height: 8),
      StatusDot(
        label: glassesService.lastStatusNote ?? '',
        color: connected
            ? CookTogetherTheme.success
            : CookTogetherTheme.warning,
      ),
      if (connected) ...[
        const SizedBox(height: 4),
        Text(
          'Battery ${glassesService.batteryLevel}%',
          style: textTheme.bodyMedium,
        ),
      ],
      const SizedBox(height: 12),
      Text(
        'The camera turns on only while a photo is taken.',
        style: textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: () => glassesService.initializeAndPairMockDevice(),
        child: const Text('Use simulated glasses instead'),
      ),
    ];
  }

  List<Widget> _simulated(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final connecting =
        glassesService.connectionState == GlassesConnectionState.connecting;
    final note = glassesService.lastStatusNote;
    final failed =
        glassesService.connectionState == GlassesConnectionState.disconnected;
    return [
      Text('Meta glasses', style: textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text(
        'Connect your own glasses through the Meta AI app (Developer Mode '
        'on), or keep using simulated ones.',
        style: textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      PrimaryButton(
        label: connecting ? 'Connecting…' : 'Connect my glasses',
        icon: Icons.link_rounded,
        onPressed: connecting
            ? null
            : () async {
                if (await glassesService.connectRealGlasses()) {
                  onShowToast('Connected to ${glassesService.deviceName}');
                }
              },
      ),
      if (failed && note != null) ...[
        const SizedBox(height: 8),
        Text(
          note,
          style: textTheme.bodyMedium?.copyWith(
            color: CookTogetherTheme.warning,
          ),
        ),
      ],
      const SizedBox(height: 28),
      Text('Simulated glasses', style: textTheme.titleMedium),
      const SizedBox(height: 4),
      RadioGroup<MockGlassesModel>(
        groupValue: glassesService.mockModel,
        onChanged: (model) async {
          if (model == null) return;
          await glassesService.initializeAndPairMockDevice(model: model);
          onShowToast('Switched to ${_modelNames[model]}');
        },
        child: Column(
          children: [
            for (final MapEntry(key: model, value: name) in _modelNames.entries)
              RadioListTile<MockGlassesModel>(
                contentPadding: EdgeInsets.zero,
                value: model,
                activeColor: CookTogetherTheme.success,
                title: Text(name, style: textTheme.bodyLarge),
              ),
          ],
        ),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          await glassesService.simulateTouchpadTap();
          onShowToast('Touchpad tap simulated');
        },
        icon: const Icon(Icons.touch_app_outlined),
        label: const Text('Test touchpad tap'),
      ),
    ];
  }
}
