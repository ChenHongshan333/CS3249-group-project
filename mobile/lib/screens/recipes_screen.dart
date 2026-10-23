import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Recipe list. Tapping a recipe opens it; there is no separate
/// "select then continue" step.
class RecipesScreen extends StatefulWidget {
  final List<Recipe> recipes;
  final String selectedRecipeId;
  final ValueChanged<String> onSelectRecipe;
  final VoidCallback onContinueToPrep;
  final VoidCallback onBack;
  final ValueChanged<String> onShowToast;

  const RecipesScreen({
    super.key,
    required this.recipes,
    required this.selectedRecipeId,
    required this.onSelectRecipe,
    required this.onContinueToPrep,
    required this.onBack,
    required this.onShowToast,
  });

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  String _searchQuery = '';

  List<Recipe> get _filteredRecipes {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.recipes;
    return widget.recipes.where((r) {
      final haystack = '${r.name} ${r.ingredients.join(" ")}'.toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  void _open(String recipeId) {
    widget.onSelectRecipe(recipeId);
    widget.onContinueToPrep();
  }

  void _openVideoImport() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _VideoImportSheet(
        onLoadDemo: () {
          Navigator.of(sheetContext).pop();
          widget.onShowToast('Demo recipe loaded: One-pan veggie noodles');
          _open('noodles');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final visible = _filteredRecipes;
    return Column(
      children: [
        ScreenHeader(title: 'Choose a recipe', onBack: widget.onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CookTogetherTheme.gutter,
              4,
              CookTogetherTheme.gutter,
              24,
            ),
            children: [
              TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: textTheme.bodyLarge,
                decoration: const InputDecoration(
                  hintText: 'Search meals or ingredients',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No recipes match "$_searchQuery".',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: CookTogetherTheme.inkMuted,
                    ),
                  ),
                )
              else
                for (final (i, recipe) in visible.indexed) ...[
                  if (i > 0) const Divider(indent: 78),
                  _RecipeRow(recipe: recipe, onTap: () => _open(recipe.id)),
                ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _openVideoImport,
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Import from a video'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecipeRow extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onTap;

  const _RecipeRow({required this.recipe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CookTogetherTheme.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            EmojiTile(emoji: recipe.icon, tone: recipe.tone, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe.name, style: textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${recipe.timeMinutes} min · ${recipe.steps.length} steps',
                    style: textTheme.bodyMedium,
                  ),
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

class _VideoImportSheet extends StatelessWidget {
  final VoidCallback onLoadDemo;

  const _VideoImportSheet({required this.onLoadDemo});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CookTogetherTheme.gutter,
        0,
        CookTogetherTheme.gutter,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Import from a video', style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'This is a demo. Any link loads One-pan veggie noodles.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            style: textTheme.bodyLarge,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'Paste a video link'),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Load demo recipe', onPressed: onLoadDemo),
        ],
      ),
    );
  }
}
