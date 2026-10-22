import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';

/// Recipe catalog screen (`Step 01 / The Meal`) with ingredient search
/// and recipe video import preview modal.
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
  bool _videoImportOpen = false;
  final TextEditingController _videoUrlController = TextEditingController();

  Recipe get _selectedRecipe =>
      widget.recipes.firstWhere(
        (r) => r.id == widget.selectedRecipeId,
        orElse: () => widget.recipes.first,
      );

  List<Recipe> get _filteredRecipes {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.recipes;
    return widget.recipes.where((r) {
      final haystack = '${r.name} ${r.ingredients.join(" ")}'.toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _videoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredRecipes;
    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
                children: [
                  RichText(
                    text: TextSpan(
                      style: CookTogetherTheme.headingStyle(
                        fontSize: 30,
                        height: 1.09,
                      ),
                      children: const [
                        TextSpan(text: 'What sounds '),
                        TextSpan(
                          text: 'good?',
                          style: TextStyle(
                            color: CookTogetherTheme.terracottaRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick a beginner-friendly meal. CookTogether will guide you step by step with voice and glasses vision.',
                    style: CookTogetherTheme.bodyStyle(
                      fontSize: 12,
                      color: CookTogetherTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Search Box
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: CookTogetherTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: CookTogetherTheme.muted,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: TextField(
                            onChanged: (value) =>
                                setState(() => _searchQuery = value),
                            style: CookTogetherTheme.bodyStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'Search meals or ingredients',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'No matching recipes. Try another ingredient.',
                          style: CookTogetherTheme.bodyStyle(
                            fontSize: 12,
                            color: CookTogetherTheme.muted,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final item in visible) ...[
                      _RecipeCard(
                        recipe: item,
                        isSelected: item.id == widget.selectedRecipeId,
                        onTap: () => widget.onSelectRecipe(item.id),
                      ),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 4),
                  // Video import concept card
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _videoImportOpen = true),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9EF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE0BF97)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.videocam_outlined,
                            color: Color(0xFFC57528),
                            size: 21,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Have a recipe video?',
                                  style: CookTogetherTheme.bodyStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: CookTogetherTheme.ink,
                                  ),
                                ),
                                Text(
                                  'Explore turning a video link into guided steps',
                                  style: CookTogetherTheme.bodyStyle(
                                    fontSize: 10,
                                    color: const Color(0xFF9D987F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFC57528),
                            size: 19,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom Action
            Container(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
              color: CookTogetherTheme.cream,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 51,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CookTogetherTheme.terracottaRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: widget.onContinueToPrep,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            'Continue with ${_selectedRecipe.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CookTogetherTheme.headingStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 19),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_videoImportOpen) _buildVideoImportModal(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
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
                    'STEP 01 / THE MEAL',
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
                    'Choose a recipe',
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
    );
  }

  Widget _buildVideoImportModal() {
    return Container(
      color: const Color(0x8A263023),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(26),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: CookTogetherTheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: CookTogetherTheme.toneOrangeBg,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.videocam_rounded,
                    color: CookTogetherTheme.warmOrange,
                    size: 26,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _videoImportOpen = false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Recipe video input',
              style: CookTogetherTheme.headingStyle(fontSize: 24),
            ),
            const SizedBox(height: 6),
            Text(
              'Explore how a cooking video could become a voice-guided step-by-step recipe. This demo loads One-pan veggie noodles.',
              style: CookTogetherTheme.bodyStyle(
                fontSize: 12,
                color: CookTogetherTheme.muted,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _videoUrlController,
              decoration: InputDecoration(
                hintText: 'https://example.com/recipe-video',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: CookTogetherTheme.border),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CookTogetherTheme.terracottaRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                onPressed: () {
                  widget.onSelectRecipe('noodles');
                  setState(() => _videoImportOpen = false);
                  widget.onShowToast(
                    'Demo recipe loaded: One-pan veggie noodles',
                  );
                },
                child: Text(
                  'Preview example recipe',
                  style: CookTogetherTheme.headingStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final bool isSelected;
  final VoidCallback onTap;

  const _RecipeCard({
    required this.recipe,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: CookTogetherTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? CookTogetherTheme.herbGreen
                : CookTogetherTheme.border,
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: CookTogetherTheme.toneBackground(recipe.tone),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                recipe.icon,
                style: const TextStyle(fontSize: 35),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.name,
                    style: CookTogetherTheme.headingStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: Color(0xFF6E8266),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${recipe.timeMinutes} min · ${recipe.level} · ${recipe.steps.length} steps',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CookTogetherTheme.bodyStyle(
                            fontSize: 11,
                            color: const Color(0xFF6E8266),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    recipe.ingredients.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CookTogetherTheme.bodyStyle(
                      fontSize: 10,
                      color: const Color(0xFFA1A398),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected
                    ? CookTogetherTheme.herbGreen
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? CookTogetherTheme.herbGreen
                      : const Color(0xFFD2D6CA),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
