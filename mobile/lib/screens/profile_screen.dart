import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../theme/app_theme.dart';

/// Combined Profile & Preferences screen ("My Kitchen / Make It Yours").
class ProfileScreen extends StatefulWidget {
  final UserPreferences preferences;
  final List<CookingHistoryItem> history;
  final ValueChanged<UserPreferences> onSavePreferences;
  final VoidCallback onOpenHistory;
  final VoidCallback onBack;

  const ProfileScreen({
    super.key,
    required this.preferences,
    required this.history,
    required this.onSavePreferences,
    required this.onOpenHistory,
    required this.onBack,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
    final updated = _draft.copyWith(
      serverBaseUrl: _serverUrlController.text.trim(),
    );
    widget.onSavePreferences(updated);
  }

  @override
  Widget build(BuildContext context) {
    final uniqueRecipes = widget.history.map((e) => e.recipeId).toSet().length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 6),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: widget.onBack,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: CookTogetherTheme.surface,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: CookTogetherTheme.border),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      size: 19,
                      color: CookTogetherTheme.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MY KITCHEN & PREFERENCES',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CookTogetherTheme.bodyStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: CookTogetherTheme.warmOrange,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'Your profile',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CookTogetherTheme.headingStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  '✳',
                  style: TextStyle(
                    color: CookTogetherTheme.butterYellow,
                    fontSize: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 108),
            children: [
              // Profile Hero
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4D6AB),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'H',
                    style: CookTogetherTheme.headingStyle(
                      fontSize: 30,
                      color: const Color(0xFFAA602B),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Hi, home cook!',
                  style: CookTogetherTheme.headingStyle(fontSize: 24),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Set things up the way that helps you feel comfortable.',
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 12,
                    color: CookTogetherTheme.muted,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Stats Banner
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2E2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${widget.history.length}',
                            style: CookTogetherTheme.headingStyle(
                              fontSize: 22,
                              color: const Color(0xFF5B9542),
                            ),
                          ),
                          Text(
                            'meals made',
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 10.5,
                              color: const Color(0xFF6F8763),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '$uniqueRecipes',
                            style: CookTogetherTheme.headingStyle(
                              fontSize: 22,
                              color: const Color(0xFF5B9542),
                            ),
                          ),
                          Text(
                            'recipes explored',
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 10.5,
                              color: const Color(0xFF6F8763),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Cooking Experience Level
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: CookTogetherTheme.surface,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: CookTogetherTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.soup_kitchen_outlined,
                          size: 19,
                          color: CookTogetherTheme.herbGreen,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Cooking experience',
                          style: CookTogetherTheme.headingStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    for (final option in const [
                      'First time cooking',
                      'I know a few basics',
                    ]) ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(11),
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(level: option),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _draft.level == option
                                ? const Color(0xFFF5FAEF)
                                : const Color(0xFFFBFAF5),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: _draft.level == option
                                  ? CookTogetherTheme.herbGreen
                                  : const Color(0xFFEEECE3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                option,
                                style: CookTogetherTheme.bodyStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Container(
                                width: 17,
                                height: 17,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: _draft.level == option
                                        ? CookTogetherTheme.herbGreen
                                        : const Color(0xFFC0C7BB),
                                    width: _draft.level == option ? 5 : 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Dietary Needs
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: CookTogetherTheme.surface,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: CookTogetherTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.favorite_outline_rounded,
                          size: 19,
                          color: CookTogetherTheme.herbGreen,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Dietary needs',
                          style: CookTogetherTheme.headingStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final item in const [
                          'No restrictions',
                          'Vegetarian',
                          'Halal',
                          'Other',
                        ])
                          GestureDetector(
                            onTap: () => setState(
                              () => _draft = _draft.copyWith(diet: item),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _draft.diet == item
                                    ? const Color(0xFFE6F0DD)
                                    : const Color(0xFFFBFAF6),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: _draft.diet == item
                                      ? CookTogetherTheme.herbGreen
                                      : const Color(0xFFE7E5DB),
                                ),
                              ),
                              child: Text(
                                item,
                                style: CookTogetherTheme.bodyStyle(
                                  fontSize: 11.5,
                                  fontWeight: _draft.diet == item
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: _draft.diet == item
                                      ? CookTogetherTheme.deepHerbGreen
                                      : const Color(0xFF5F675F),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Check ingredient labels yourself for allergies or specific dietary needs.',
                      style: CookTogetherTheme.bodyStyle(
                        fontSize: 10.5,
                        color: CookTogetherTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Voice & Glasses Guidance Toggles
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: CookTogetherTheme.surface,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: CookTogetherTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.record_voice_over_outlined,
                          size: 19,
                          color: CookTogetherTheme.herbGreen,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'During cooking',
                          style: CookTogetherTheme.headingStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _PreferenceSwitchRow(
                      title: 'Read steps & replies aloud',
                      subtitle: 'Spoken voice guidance (TTS)',
                      value: _draft.voiceGuidance,
                      onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(voiceGuidance: v),
                      ),
                    ),
                    _PreferenceSwitchRow(
                      title: 'Hands-free continuous listening',
                      subtitle: 'Default to hands-free mic when cooking starts',
                      value: _draft.handsFreeListening,
                      onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(handsFreeListening: v),
                      ),
                    ),
                    _PreferenceSwitchRow(
                      title: 'Show conversation captions',
                      subtitle: 'Display full conversational transcript',
                      value: _draft.showCaptions,
                      onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(showCaptions: v),
                      ),
                    ),
                    const Divider(height: 18),
                    Text(
                      'Optional LLM & Vision Server URL (docs/api.md)',
                      style: CookTogetherTheme.bodyStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _serverUrlController,
                      style: CookTogetherTheme.bodyStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Leave empty to use built-in mock assistant',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFFAF9F3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: CookTogetherTheme.border,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 49,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CookTogetherTheme.terracottaRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 19),
                  label: Text(
                    'Save preferences',
                    style: CookTogetherTheme.headingStyle(
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreferenceSwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PreferenceSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 10.5,
                    color: CookTogetherTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeTrackColor: CookTogetherTheme.herbGreen,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
