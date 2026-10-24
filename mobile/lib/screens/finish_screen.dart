import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Celebration screen shown when the user completes a recipe.
class FinishScreen extends StatelessWidget {
  final Recipe recipe;
  final int elapsedSeconds;
  final int visualChecksCount;
  final VoidCallback onBackToHome;

  const FinishScreen({
    super.key,
    required this.recipe,
    required this.elapsedSeconds,
    required this.visualChecksCount,
    required this.onBackToHome,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final minutes = (elapsedSeconds / 60).ceil().clamp(1, 999);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CookTogetherTheme.gutter),
              child: Column(
                children: [
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
                        value: '$visualChecksCount',
                        label: visualChecksCount == 1 ? 'check' : 'checks',
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text('Saved to your history.', style: textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ),
        BottomActionBar(
          child: PrimaryButton(label: 'Done', onPressed: onBackToHome),
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
