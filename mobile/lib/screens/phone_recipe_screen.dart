import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../services/assistant_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// The user study's phone condition (B): the recipe as a plain list to
/// scroll by hand, like a recipe saved in Notes. No voice, glasses or AI.
/// Start and finish are logged so both conditions are timed the same way.
class PhoneRecipeScreen extends StatefulWidget {
  final Recipe recipe;
  final AssistantService assistantService;
  final VoidCallback onBack;

  /// Called with the cooking time after the cook taps "I've finished".
  final ValueChanged<int> onFinish;

  const PhoneRecipeScreen({
    super.key,
    required this.recipe,
    required this.assistantService,
    required this.onBack,
    required this.onFinish,
  });

  @override
  State<PhoneRecipeScreen> createState() => _PhoneRecipeScreenState();
}

class _PhoneRecipeScreenState extends State<PhoneRecipeScreen> {
  final String _sessionId = 'sess-${DateTime.now().millisecondsSinceEpoch}';
  DateTime? _startedAt;
  bool _finished = false;

  void _start() {
    setState(() => _startedAt = DateTime.now());
    widget.assistantService.logEvent(
      sessionId: _sessionId,
      type: 'session_start',
      data: {'recipeId': widget.recipe.id, 'condition': 'phone_recipe'},
    );
  }

  int get _elapsedSeconds => DateTime.now().difference(_startedAt!).inSeconds;

  void _finish() {
    final seconds = _elapsedSeconds;
    _finished = true;
    widget.assistantService.logEvent(
      sessionId: _sessionId,
      type: 'session_end',
      data: {'completed': true, 'seconds': seconds},
    );
    widget.onFinish(seconds);
  }

  /// Leaving by Back or the system back gesture logs an unfinished session.
  @override
  void dispose() {
    if (_startedAt != null && !_finished) {
      widget.assistantService.logEvent(
        sessionId: _sessionId,
        type: 'session_end',
        data: {'completed': false, 'seconds': _elapsedSeconds},
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final recipe = widget.recipe;
    return Column(
      children: [
        ScreenHeader(title: recipe.name, onBack: widget.onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CookTogetherTheme.gutter,
              4,
              CookTogetherTheme.gutter,
              24,
            ),
            children: [
              Text('Ingredients', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final ingredient in recipe.ingredients)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $ingredient', style: textTheme.bodyLarge),
                ),
              const SizedBox(height: 4),
              Text(
                'Amounts are on your ingredient card.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Text('Steps', style: textTheme.titleMedium),
              for (var i = 0; i < recipe.steps.length; i++) ...[
                const SizedBox(height: 16),
                Text(
                  '${i + 1}. ${recipe.steps[i].title}',
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(recipe.steps[i].instruction, style: textTheme.bodyLarge),
                if (recipe.steps[i].tip.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tip: ${recipe.steps[i].tip}',
                    style: textTheme.bodyMedium,
                  ),
                ],
              ],
            ],
          ),
        ),
        BottomActionBar(
          child: _startedAt == null
              ? PrimaryButton(label: 'Start cooking', onPressed: _start)
              : PrimaryButton(label: "I've finished", onPressed: _finish),
        ),
      ],
    );
  }
}
