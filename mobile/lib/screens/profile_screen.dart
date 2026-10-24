import 'package:flutter/material.dart';
import 'package:meta_wearables_dat_flutter/meta_wearables_dat_flutter.dart';

import '../glasses/glasses_service.dart';
import '../models/conversation.dart';
import '../models/user_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Preferences. Settings are grouped by section titles rather than cards,
/// and the backend URL sits in a collapsed Developer section.
class ProfileScreen extends StatefulWidget {
  final UserPreferences preferences;
  final List<CookingHistoryItem> history;
  final ValueChanged<UserPreferences> onSavePreferences;
  final VoidCallback onOpenHistory;
  final VoidCallback onBack;

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
    required this.onBack,
    this.glassesService,
    this.onShowToast,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Stored values stay the same so saved preferences keep working.
  static const _levels = {
    'First time cooking': 'First time',
    'I know a few basics': 'Know the basics',
  };
  static const _diets = ['No restrictions', 'Vegetarian', 'Halal', 'Other'];
  static const _glassesModels = {
    MockGlassesModel.rayBanMeta: 'Ray-Ban Meta',
    MockGlassesModel.oakleyMetaHSTN: 'Oakley Meta HSTN',
    MockGlassesModel.metaRayBanDisplay: 'Meta Ray-Ban Display',
  };

  late UserPreferences _draft;
  late final TextEditingController _serverUrlController;

  @override
  void initState() {
    super.initState();
    _draft = widget.preferences;
    _serverUrlController = TextEditingController(
      text: widget.preferences.serverBaseUrl,
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
              const SizedBox(height: 24),
              const SectionTitle('Cooking experience'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final MapEntry(key: value, value: label)
                        in _levels.entries)
                      ButtonSegment(value: value, label: Text(label)),
                  ],
                  selected: {_draft.level},
                  onSelectionChanged: (s) =>
                      setState(() => _draft = _draft.copyWith(level: s.first)),
                ),
              ),
              const SizedBox(height: 32),
              const SectionTitle('Diet'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final diet in _diets)
                    ChoiceChip(
                      label: Text(diet),
                      selected: _draft.diet == diet,
                      showCheckmark: false,
                      selectedColor: CookTogetherTheme.successSoft,
                      labelStyle: textTheme.labelMedium?.copyWith(
                        color: _draft.diet == diet
                            ? CookTogetherTheme.success
                            : CookTogetherTheme.ink,
                      ),
                      onSelected: (_) =>
                          setState(() => _draft = _draft.copyWith(diet: diet)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Always check labels yourself for allergies.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 32),
              const SectionTitle('While cooking'),
              _SwitchRow(
                title: 'Read steps aloud',
                value: _draft.voiceGuidance,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(voiceGuidance: v)),
              ),
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
