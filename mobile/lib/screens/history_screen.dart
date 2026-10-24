import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../models/user_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Completed cooking sessions, newest first.
class HistoryScreen extends StatelessWidget {
  final List<CookingHistoryItem> history;

  /// Photos of finished dishes, by history item id.
  final Map<String, Uint8List> dishPhotos;
  final VoidCallback onChooseRecipe;
  final VoidCallback onBack;

  const HistoryScreen({
    super.key,
    required this.history,
    this.dishPhotos = const {},
    required this.onChooseRecipe,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        ScreenHeader(title: 'Cooking history', onBack: onBack),
        Expanded(
          child: history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.menu_book_rounded,
                          size: 48,
                          color: CookTogetherTheme.inkMuted,
                        ),
                        const SizedBox(height: 16),
                        Text('Nothing cooked yet', style: textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'Meals you finish will show up here.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: onChooseRecipe,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('Choose a recipe'),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    CookTogetherTheme.gutter,
                    4,
                    CookTogetherTheme.gutter,
                    24,
                  ),
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const Divider(indent: 70),
                  itemBuilder: (context, index) {
                    final item = history[index];
                    final recipe = kStarterRecipes.where(
                      (r) => r.id == item.recipeId,
                    );
                    final photo = dishPhotos[item.id];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          if (photo != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                CookTogetherTheme.radiusCard,
                              ),
                              child: Image.memory(
                                photo,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                semanticLabel: 'Photo of ${item.recipeName}',
                                errorBuilder: (_, _, _) => EmojiTile(
                                  emoji: item.recipeIcon,
                                  tone: 'green',
                                ),
                              ),
                            )
                          else
                            EmojiTile(
                              emoji: item.recipeIcon,
                              tone: recipe.isEmpty
                                  ? 'green'
                                  : recipe.first.tone,
                            ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.recipeName,
                                  style: textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item.date} · ${item.durationMinutes} min',
                                  style: textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
