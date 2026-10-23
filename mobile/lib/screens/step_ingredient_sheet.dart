import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Bottom sheet opened from the cooking screen. Lets the cook see all
/// steps, jump to one, or tick off ingredients without losing their place.
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

enum _Tab { steps, ingredients }

class _StepIngredientSheetState extends State<StepIngredientSheet> {
  _Tab _tab = _Tab.steps;
  late Set<String> _localChecked;

  @override
  void initState() {
    super.initState();
    _localChecked = Set<String>.from(widget.checkedIngredients);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final recipe = widget.recipe;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CookTogetherTheme.gutter,
        0,
        CookTogetherTheme.gutter,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(recipe.name, style: textTheme.headlineSmall),
          const SizedBox(height: 16),
          SegmentedButton<_Tab>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _Tab.steps,
                label: Text('Steps (${recipe.steps.length})'),
              ),
              ButtonSegment(
                value: _Tab.ingredients,
                label: Text('Ingredients (${recipe.ingredients.length})'),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _tab == _Tab.steps
                ? _buildSteps(textTheme)
                : _buildIngredients(),
          ),
        ],
      ),
    );
  }

  Widget _buildSteps(TextTheme textTheme) {
    return ListView.builder(
      itemCount: widget.recipe.steps.length,
      itemBuilder: (context, index) {
        final step = widget.recipe.steps[index];
        final isCurrent = index == widget.currentStepIndex;
        final isDone = index < widget.currentStepIndex;
        return InkWell(
          borderRadius: BorderRadius.circular(CookTogetherTheme.radiusControl),
          onTap: () {
            widget.onSelectStep(index);
            Navigator.of(context).pop();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: isCurrent
                ? BoxDecoration(
                    color: CookTogetherTheme.successSoft,
                    borderRadius: BorderRadius.circular(
                      CookTogetherTheme.radiusControl,
                    ),
                  )
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone || isCurrent
                        ? CookTogetherTheme.success
                        : Colors.transparent,
                    border: Border.all(
                      color: isDone || isCurrent
                          ? CookTogetherTheme.success
                          : CookTogetherTheme.line,
                      width: 1.5,
                    ),
                  ),
                  child: isDone
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Colors.white,
                        )
                      : Text(
                          '${index + 1}',
                          style: textTheme.labelMedium?.copyWith(
                            color: isCurrent
                                ? Colors.white
                                : CookTogetherTheme.ink,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.title, style: textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(step.instruction, style: textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIngredients() {
    return ListView(
      children: [
        for (final ingredient in widget.recipe.ingredients)
          CheckRow(
            label: ingredient[0].toUpperCase() + ingredient.substring(1),
            checked: _localChecked.contains(ingredient),
            onTap: () {
              setState(() {
                if (!_localChecked.remove(ingredient)) {
                  _localChecked.add(ingredient);
                }
              });
              widget.onToggleIngredient(ingredient);
            },
          ),
      ],
    );
  }
}
