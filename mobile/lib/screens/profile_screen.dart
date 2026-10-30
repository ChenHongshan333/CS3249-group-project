import 'package:flutter/material.dart';
import 'package:meta_wearables_dat_flutter/meta_wearables_dat_flutter.dart';

import '../glasses/glasses_service.dart';
import '../models/conversation.dart';
import '../models/user_preferences.dart';
import '../services/voice_controller.dart'
    show VoiceController, kGlassesMicEnabled;
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Preferences. Settings are grouped by section titles rather than cards,
/// and the backend URL sits in a collapsed Developer section.
class ProfileScreen extends StatefulWidget {
  final UserPreferences preferences;
  final List<CookingHistoryItem> history;
  final ValueChanged<UserPreferences> onSavePreferences;
  final VoidCallback onOpenHistory;

  /// Shows the first-use guide again.
  final VoidCallback? onOpenGuide;
  final VoidCallback onBack;
  final VoiceController? voiceController;

  /// For the simulated glasses controls in the Developer section. They
  /// act at once, without Save.
  final GlassesService? glassesService;
  final ValueChanged<String>? onShowToast;

  const ProfileScreen({
    super.key,
    required this.preferences,
    required this.history,
    required this.onSavePreferences,
    required this.onOpenHistory,
    this.onOpenGuide,
    required this.onBack,
    this.voiceController,
    this.glassesService,
    this.onShowToast,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _glassesModels = {
    MockGlassesModel.rayBanMeta: 'Ray-Ban Meta',
    MockGlassesModel.oakleyMetaHSTN: 'Oakley Meta HSTN',
    MockGlassesModel.metaRayBanDisplay: 'Meta Ray-Ban Display',
  };

  late UserPreferences _draft;
  late final TextEditingController _serverUrlController;
  List<Map<String, String>> _availableVoices = [];
  bool _loadingVoices = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.preferences;
    _serverUrlController = TextEditingController(
      text: widget.preferences.serverBaseUrl,
    );
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    final vc = widget.voiceController;
    if (vc == null) return;
    setState(() => _loadingVoices = true);
    final voices = await vc.getAvailableVoices();
    if (mounted) {
      setState(() {
        _availableVoices = voices;
        _loadingVoices = false;
      });
    }
  }

  String _formatVoiceName(String rawName, String locale) {
    if (rawName.isEmpty) return 'Default system voice';
    var name = rawName;
    if (name.contains('.')) {
      name = name.split('.').last;
    }
    if (name.contains('-x-')) {
      final parts = name
          .split('-x-')
          .last
          .replaceAll('-local', '')
          .replaceAll('_', ' ');
      return 'Voice ($parts)';
    }
    return '$name ($locale)';
  }

  String _rateLabel(double rate) {
    if (rate < 0.42) return 'Slower';
    if (rate > 0.54) return 'Faster';
    return 'Normal';
  }

  String _pitchLabel(double pitch) {
    if (pitch < 0.85) return 'Lower';
    if (pitch > 1.15) return 'Higher';
    return 'Normal';
  }

  void _testVoice() {
    widget.voiceController?.previewVoice(
      voiceName: _draft.ttsVoiceName,
      voiceLocale: _draft.ttsVoiceLocale,
      pitch: _draft.ttsPitch,
      rate: _draft.ttsRate,
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSavePreferences(
      _draft.copyWith(serverBaseUrl: _serverUrlController.text.trim()),
    );
  }

  /// Mock Device Kit model and touchpad, for demos. Picking a model
  /// switches to simulated glasses.
  Widget _buildSimulatedGlasses(GlassesService glasses) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: glasses,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioGroup<MockGlassesModel>(
            groupValue: glasses.usingRealGlasses ? null : glasses.mockModel,
            onChanged: (model) async {
              if (model == null) return;
              await glasses.initializeAndPairMockDevice(model: model);
              widget.onShowToast?.call('Switched to ${_glassesModels[model]}');
            },
            child: Column(
              children: [
                for (final MapEntry(key: model, value: name)
                    in _glassesModels.entries)
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
              await glasses.simulateTouchpadTap();
              widget.onShowToast?.call('Touchpad tap simulated');
            },
            icon: const Icon(Icons.touch_app_outlined),
            label: const Text('Test touchpad tap'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final meals = widget.history.length;
    final recipes = widget.history.map((e) => e.recipeId).toSet().length;

    return Column(
      children: [
        ScreenHeader(title: 'Profile', onBack: widget.onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CookTogetherTheme.gutter,
              4,
              CookTogetherTheme.gutter,
              24,
            ),
            children: [
              InkWell(
                onTap: widget.onOpenHistory,
                borderRadius: BorderRadius.circular(
                  CookTogetherTheme.radiusControl,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '$meals meal${meals == 1 ? '' : 's'} made · '
                    '$recipes recipe${recipes == 1 ? '' : 's'} tried',
                    style: textTheme.bodyLarge?.copyWith(
                      color: CookTogetherTheme.inkMuted,
                    ),
                  ),
                ),
              ),
              if (widget.onOpenGuide != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onOpenGuide,
                    icon: const Icon(Icons.help_outline_rounded),
                    label: const Text('How to use CookTogether'),
                  ),
                ),
              const SizedBox(height: 24),
              const SectionTitle('While cooking'),
              _SwitchRow(
                title: 'Read steps aloud',
                value: _draft.voiceGuidance,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(voiceGuidance: v)),
              ),
              if (_draft.voiceGuidance) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: CookTogetherTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: CookTogetherTheme.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Assistant voice',
                                style: textTheme.titleSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                visualDensity: VisualDensity.compact,
                                foregroundColor: CookTogetherTheme.success,
                              ),
                              icon:
                                  const Icon(Icons.volume_up_rounded, size: 18),
                              label: const Text('Test voice'),
                              onPressed: _testVoice,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_loadingVoices)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text('Loading device voices…'),
                              ],
                            ),
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _availableVoices.any(
                                    (v) => v['name'] == _draft.ttsVoiceName)
                                ? _draft.ttsVoiceName
                                : '',
                            isExpanded: true,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('Default system voice'),
                              ),
                              for (final v in _availableVoices)
                                DropdownMenuItem<String>(
                                  value: v['name'],
                                  child: Text(
                                    _formatVoiceName(
                                      v['name'] ?? '',
                                      v['locale'] ?? '',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (val) {
                              if (val == null) return;
                              final match = _availableVoices.firstWhere(
                                (v) => v['name'] == val,
                                orElse: () => const {'locale': 'en-US'},
                              );
                              setState(() {
                                _draft = _draft.copyWith(
                                  ttsVoiceName: val,
                                  ttsVoiceLocale: match['locale'] ?? 'en-US',
                                );
                              });
                            },
                          ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text('Speaking speed', style: textTheme.bodySmall),
                            const Spacer(),
                            Text(
                              _rateLabel(_draft.ttsRate),
                              style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _draft.ttsRate,
                          min: 0.35,
                          max: 0.65,
                          divisions: 6,
                          activeColor: CookTogetherTheme.success,
                          onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(ttsRate: v),
                          ),
                        ),
                        Row(
                          children: [
                            Text('Pitch', style: textTheme.bodySmall),
                            const Spacer(),
                            Text(
                              _pitchLabel(_draft.ttsPitch),
                              style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _draft.ttsPitch,
                          min: 0.7,
                          max: 1.3,
                          divisions: 6,
                          activeColor: CookTogetherTheme.success,
                          onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(ttsPitch: v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              _SwitchRow(
                title: 'Hands-free listening',
                value: _draft.handsFreeListening,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(handsFreeListening: v),
                ),
              ),
              _SwitchRow(
                title: 'Show the full conversation',
                value: _draft.showCaptions,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(showCaptions: v)),
              ),
              const SizedBox(height: 16),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text('Developer', style: textTheme.titleMedium),
                  children: [
                    TextField(
                      controller: _serverUrlController,
                      keyboardType: TextInputType.url,
                      style: textTheme.bodyLarge,
                      decoration: const InputDecoration(
                        labelText: 'Backend URL',
                        helperText: 'Leave empty to use built-in demo answers.',
                      ),
                    ),
                    _SwitchRow(
                      title: 'Simulated glasses when no real ones',
                      value: _draft.simulatedGlassesPhotos,
                      onChanged: (v) => setState(
                        () =>
                            _draft = _draft.copyWith(simulatedGlassesPhotos: v),
                      ),
                    ),
                    if (widget.glassesService case final glasses?)
                      _buildSimulatedGlasses(glasses),
                    if (kGlassesMicEnabled)
                      _SwitchRow(
                        title: "Use the phone's mic only",
                        value: _draft.phoneMicOnly,
                        onChanged: (v) => setState(
                          () => _draft = _draft.copyWith(phoneMicOnly: v),
                        ),
                      ),
                    _SwitchRow(
                      title: 'User study: plain phone recipe',
                      value: _draft.phoneRecipeMode,
                      onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(phoneRecipeMode: v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _draft.forcedCheckResult,
                      // Fill the row so long labels shorten instead of
                      // overflowing on narrow phones.
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Step check result',
                        helperText:
                            'Skips the photo and the AI. For demos without a '
                            'camera.',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text(
                            'Real check (photo + AI)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        for (final status in VisualCheckStatus.values)
                          DropdownMenuItem(
                            value: status.wireValue,
                            child: Text(
                              'Always "${status.badgeLabel}"',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(
                          forcedCheckResult: v ?? '',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        BottomActionBar(
          child: PrimaryButton(label: 'Save', onPressed: _save),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
      value: value,
      onChanged: onChanged,
    );
  }
}
