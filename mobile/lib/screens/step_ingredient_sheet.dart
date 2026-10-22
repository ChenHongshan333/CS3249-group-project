import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';

/// Expandable bottom sheet triggered from the Pinned Glanceable Step Card
/// on the Cooking screen. Allows the cook to peek at all steps, jump to any
/// step, or check off ingredients without losing their place.
class StepIngredientSheet extends StatefulWidget {
  final Recipe recipe;
  final int currentStepIndex;
  final Set<String> checkedIngredients;
  final ValueChanged<int> onSelectStep;
  final ValueChanged<String> onToggleIngredient;

  const StepIngredientSheet({
    super.key,
    required this.recipe,
    required this.currentStepIndex,
    required this.checkedIngredients,
    required this.onSelectStep,
    required this.onToggleIngredient,
  });

  @override
  State<StepIngredientSheet> createState() => _StepIngredientSheetState();
}

class _StepIngredientSheetState extends State<StepIngredientSheet> {
  int _selectedTab = 0; // 0 = Steps, 1 = Ingredients
  late Set<String> _localChecked;

  @override
  void initState() {
    super.initState();
    _localChecked = Set<String>.from(widget.checkedIngredients);
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (mins > 0 && secs == 0) return '$mins min';
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: CookTogetherTheme.cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: CookTogetherTheme.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  widget.recipe.icon,
                  style: const TextStyle(fontSize: 26),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RECIPE OVERVIEW',
                        style: CookTogetherTheme.bodyStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: CookTogetherTheme.warmOrange,
                          letterSpacing: 1.3,
                        ),
                      ),
                      Text(
                        widget.recipe.name,
                        style: CookTogetherTheme.headingStyle(fontSize: 19),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close overview',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: CookTogetherTheme.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: CookTogetherTheme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TabPill(
                      label: 'Steps (${widget.recipe.steps.length})',
                      selected: _selectedTab == 0,
                      onTap: () => setState(() => _selectedTab = 0),
                    ),
                  ),
                  Expanded(
                    child: _TabPill(
                      label:
                          'Ingredients (${widget.recipe.ingredients.length})',
                      selected: _selectedTab == 1,
                      onTap: () => setState(() => _selectedTab = 1),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: _selectedTab == 0
                  ? ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.recipe.steps.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final step = widget.recipe.steps[index];
                        final isCurrent = index == widget.currentStepIndex;
                        final isCompleted = index < widget.currentStepIndex;
                        return InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap: () {
                            widget.onSelectStep(index);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFFF3F9EE)
                                  : CookTogetherTheme.surface,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: isCurrent
                                    ? CookTogetherTheme.herbGreen
                                    : CookTogetherTheme.border,
                                width: isCurrent ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: isCompleted
                                        ? CookTogetherTheme.herbGreen
                                        : isCurrent
                                        ? CookTogetherTheme.warmOrange
                                        : const Color(0xFFEEF2E9),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: isCompleted
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        )
                                      : Text(
                                          '${index + 1}',
                                          style: CookTogetherTheme.headingStyle(
                                            fontSize: 13,
                                            color: isCurrent
                                                ? Colors.white
                                                : CookTogetherTheme.ink,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              step.title,
                                              style: CookTogetherTheme
                                                  .headingStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          if (isCurrent)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: CookTogetherTheme
                                                    .toneGreenBg,
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                'CURRENT',
                                                style: CookTogetherTheme
                                                    .bodyStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: CookTogetherTheme
                                                          .deepHerbGreen,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        step.instruction,
                                        style: CookTogetherTheme.bodyStyle(
                                          fontSize: 12,
                                          color: CookTogetherTheme.muted,
                                        ),
                                      ),
                                      if (step.suggestedTimerSeconds !=
                                          null) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.timer_outlined,
                                              size: 13,
                                              color:
                                                  CookTogetherTheme.warmOrange,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Suggested timer: ${_formatDuration(step.suggestedTimerSeconds!)}',
                                              style: CookTogetherTheme
                                                  .bodyStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: CookTogetherTheme
                                                        .warmOrange,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.recipe.ingredients.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final ingredient = widget.recipe.ingredients[index];
                        final checked = _localChecked.contains(ingredient);
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() {
                              if (checked) {
                                _localChecked.remove(ingredient);
                              } else {
                                _localChecked.add(ingredient);
                              }
                            });
                            widget.onToggleIngredient(ingredient);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: checked
                                  ? const Color(0xFFF3F9EE)
                                  : CookTogetherTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: checked
                                    ? CookTogetherTheme.herbGreen
                                    : CookTogetherTheme.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: checked
                                        ? CookTogetherTheme.herbGreen
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: checked
                                          ? CookTogetherTheme.herbGreen
                                          : const Color(0xFFB8C3B0),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: checked
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 15,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    ingredient,
                                    style: CookTogetherTheme.bodyStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: CookTogetherTheme.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? CookTogetherTheme.herbGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: CookTogetherTheme.bodyStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : CookTogetherTheme.muted,
          ),
        ),
      ),
    );
  }
}
