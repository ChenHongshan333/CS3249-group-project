import 'package:flutter/material.dart';

import '../glasses/glasses_service.dart';
import '../models/recipe.dart';
import '../models/user_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Home: one question ("what do I do now?") and one action.
class HomeScreen extends StatelessWidget {
  final GlassesService glassesService;
  final List<CookingHistoryItem> history;
  final VoidCallback onStartCooking;
  final VoidCallback onOpenWelcomeOverview;
  final ValueChanged<String> onCookAgain;

  /// Show the Mock Device Kit as connected (Profile → Developer).
  final bool showSimulatedGlasses;

  /// A session the user paused and left, if any.
  final Recipe? pausedRecipe;
  final VoidCallback? onResumeSession;

  const HomeScreen({
    super.key,
    required this.glassesService,
    required this.history,
    required this.onStartCooking,
    required this.onOpenWelcomeOverview,
    required this.onCookAgain,
    this.showSimulatedGlasses = false,
    this.pausedRecipe,
    this.onResumeSession,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CookTogetherTheme.gutter,
        8,
        CookTogetherTheme.gutter,
        24,
      ),
      children: [
        Row(
          children: [
            Expanded(child: Text('CookTogether', style: textTheme.titleMedium)),
            IconButton(
              tooltip: 'How CookTogether works',
              onPressed: onOpenWelcomeOverview,
              icon: const Icon(Icons.help_outline_rounded),
            ),
          ],
        ),
        if (pausedRecipe != null) ...[
          const SizedBox(height: 24),
          _PausedSessionCard(recipe: pausedRecipe!, onResume: onResumeSession),
        ],
        const SizedBox(height: 48),
        const Text(
          '🍳',
          style: TextStyle(
            fontSize: 56,
            fontFamilyFallback: ['Noto Color Emoji'],
          ),
        ),
        const SizedBox(height: 16),
        Text('What are we cooking today?', style: textTheme.displaySmall),
        const SizedBox(height: 12),
        Text(
          'Pick a recipe and I\'ll guide you step by step. '
          'Your hands stay free.',
          style: textTheme.bodyLarge?.copyWith(
            color: CookTogetherTheme.inkMuted,
          ),
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          label: 'Choose a recipe',
          icon: Icons.arrow_forward_rounded,
          onPressed: onStartCooking,
        ),
        const SizedBox(height: 16),
        Center(
          child: ListenableBuilder(
            listenable: glassesService,
            builder: (context, _) =>
                glassesReady(
                  glassesService,
                  allowSimulated: showSimulatedGlasses,
                )
                ? StatusDot(
                    label: '${glassesService.deviceName} connected',
                    color: CookTogetherTheme.success,
                  )
                : const StatusDot(
                    label: 'Glasses not connected',
                    color: CookTogetherTheme.warning,
                  ),
          ),
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 48),
          const SectionTitle('Cook again'),
          _CookAgainRow(
            item: history.first,
            onTap: () => onCookAgain(history.first.recipeId),
          ),
        ],
      ],
    );
  }
}

class _PausedSessionCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback? onResume;

  const _PausedSessionCard({required this.recipe, required this.onResume});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: CookTogetherTheme.surface,
      borderRadius: BorderRadius.circular(CookTogetherTheme.radiusCard),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EmojiTile(emoji: recipe.icon, tone: recipe.tone),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(recipe.name, style: textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('Paused', style: textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Resume cooking',
              icon: Icons.play_arrow_rounded,
              onPressed: onResume,
            ),
          ],
        ),
      ),
    );
  }
}

class _CookAgainRow extends StatelessWidget {
  final CookingHistoryItem item;
  final VoidCallback onTap;

  const _CookAgainRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final recipe = kStarterRecipes.where((r) => r.id == item.recipeId);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CookTogetherTheme.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            EmojiTile(
              emoji: item.recipeIcon,
              tone: recipe.isEmpty ? 'green' : recipe.first.tone,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.recipeName, style: textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text('Last made ${item.date}', style: textTheme.bodyMedium),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: CookTogetherTheme.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}
