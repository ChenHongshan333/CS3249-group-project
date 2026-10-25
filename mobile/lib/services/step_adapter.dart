import '../models/recipe.dart';

/// The recipe after adapting it, with the steps that changed and the
/// titles of those that went. [moved] maps each kept step's old index to
/// its new one.
typedef AdaptedRecipe = ({
  Recipe recipe,
  Set<int> changed,
  List<String> removed,
  Map<int, int> moved,
});

/// Adapts recipe steps to missing ingredients. The choices on Get ready
/// come with hand-written changes (lib/models/missing_options.dart); the
/// rule-based rewrites here are the fallback, and serve the built-in demo
/// assistant. The real backend asks the AI instead (adapt_steps in
/// docs/api.md).
class StepAdapter {
  const StepAdapter._();

  /// Applies [edits], by step index, and removes the steps they say to.
  static AdaptedRecipe apply(Recipe recipe, Map<int, StepEdit> edits) {
    final steps = [...recipe.steps];
    final changed = <int>{};
    final removed = <int>{};
    for (final MapEntry(key: i, value: edit) in edits.entries) {
      if (i < 0 || i >= steps.length) continue;
      if (edit.remove) {
        removed.add(i);
      } else {
        steps[i] = edit.applyTo(steps[i]);
        changed.add(i);
      }
    }
    return _rebuild(recipe, steps, changed, removed);
  }

  /// Adapts [recipe] for the ingredients the cook doesn't have, in recipe
  /// order. The hand-written changes are each written against the original
  /// step, so when a step was already changed for another ingredient, the
  /// rule-based rewrite is used on it instead.
  static AdaptedRecipe forChoices(
    Recipe recipe,
    Map<String, MissingOption> choices,
  ) {
    final steps = [...recipe.steps];
    final changed = <int>{};
    final removed = <int>{};
    for (final ingredient in recipe.ingredients) {
      final option = choices[ingredient];
      if (option == null) continue;
      final current = recipe.copyWith(steps: steps);
      final rewritten = option.leavesOut
          ? leaveOut(current, ingredient)
          : substitute(current, ingredient, option.use!);
      final edits = option.steps.isNotEmpty
          ? option.steps
          : {for (final e in rewritten.entries) e.key: StepEdit(text: e.value)};
      for (final MapEntry(key: i, value: edit) in edits.entries) {
        if (i < 0 || i >= steps.length) continue;
        if (edit.remove) {
          removed.add(i);
        } else if (changed.contains(i)) {
          final text = rewritten[i];
          if (text != null) steps[i] = steps[i].copyWith(instruction: text);
        } else {
          steps[i] = edit.applyTo(steps[i]);
          changed.add(i);
        }
      }
    }
    return _rebuild(recipe, steps, changed, removed);
  }

  static AdaptedRecipe _rebuild(
    Recipe recipe,
    List<RecipeStep> steps,
    Set<int> changed,
    Set<int> removed,
  ) {
    // A recipe needs at least one step.
    final gone = removed.length < steps.length ? removed : const <int>{};
    final moved = <int, int>{};
    final kept = <RecipeStep>[];
    for (final (i, step) in steps.indexed) {
      if (gone.contains(i)) continue;
      moved[i] = kept.length;
      kept.add(step);
    }
    return (
      recipe: recipe.copyWith(steps: kept),
      changed: {for (final i in changed) ?moved[i]},
      removed: [for (final i in gone.toList()..sort()) recipe.steps[i].title],
      moved: moved,
    );
  }

  /// How steps may name [ingredient]: "cherry tomatoes", or just
  /// "tomatoes"; "tortillas", or "tortilla".
  static List<String> _names(String ingredient) {
    final words = ingredient.trim().split(RegExp(r'\s+'));
    final names = {ingredient.trim(), if (words.length > 1) words.last};
    return {
      ...names,
      for (final n in names)
        if (n.endsWith('s') && !n.endsWith('ss')) n.substring(0, n.length - 1),
    }.toList();
  }

  static RegExp _word(String name) =>
      RegExp('\\b${RegExp.escape(name)}\\b', caseSensitive: false);

  /// Uses [replacement] wherever a step names [ingredient].
  static Map<int, String> substitute(
    Recipe recipe,
    String ingredient,
    String replacement,
  ) {
    final changes = <int, String>{};
    for (final (i, step) in recipe.steps.indexed) {
      for (final name in _names(ingredient)) {
        final pattern = _word(name);
        if (!pattern.hasMatch(step.instruction)) continue;
        changes[i] = step.instruction.replaceAll(pattern, replacement);
        break;
      }
    }
    return changes;
  }

  /// Takes [ingredient] out of every step that names it: out of a list
  /// ("the greens, tomatoes and cucumber"), or else the part of the
  /// sentence about it.
  static Map<int, String> leaveOut(Recipe recipe, String ingredient) {
    final changes = <int, String>{};
    for (final (i, step) in recipe.steps.indexed) {
      final names = _names(ingredient);
      bool mentions(String text) => names.any((n) => _word(n).hasMatch(text));
      if (!mentions(step.instruction)) continue;
      final sentences = step.instruction.split(RegExp(r'(?<=[.!?])\s+'));
      final kept = [
        for (final sentence in sentences)
          ?(mentions(sentence) ? _withoutItem(sentence, names) : sentence),
      ];
      changes[i] = kept.isNotEmpty
          ? kept.join(' ')
          : "Skip this step, since you're leaving out the $ingredient.";
    }
    return changes;
  }

  /// Verbs that start a new instruction within a sentence ("cut …, then
  /// slice …").
  static const _verbs =
      'add|beat|bring|chop|cook|cut|dice|drain|drizzle|fold|mince|pat|'
      'rinse|serve|simmer|slice|spoon|stir|taste|toss|turn|warm|wash';

  /// The sentence without the ingredient, or null when nothing is left.
  static String? _withoutItem(String sentence, List<String> names) {
    final end = RegExp(r'[.!?]$').firstMatch(sentence)?[0] ?? '.';
    final body = sentence.substring(0, sentence.length - (end.length));
    // Split into instructions at "and"/"then" before a verb, keeping the
    // joining words. A lone verb ("rinse and drain …") stays with the next.
    final separator = RegExp(
      r'(,?\s+(?:and|then)\s+)(?=(?:' + _verbs + r')\b)',
      caseSensitive: false,
    );
    final parts = <(String, String)>[]; // (joining words, instruction)
    var last = 0;
    var joiner = '';
    for (final m in separator.allMatches(body)) {
      parts.add((joiner, body.substring(last, m.start)));
      joiner = m[1]!;
      last = m.end;
    }
    parts.add((joiner, body.substring(last)));
    for (var i = parts.length - 2; i >= 0; i--) {
      if (!parts[i].$2.trim().contains(' ')) {
        parts[i] = (
          parts[i].$1,
          parts[i].$2 + parts[i + 1].$1 + parts[i + 1].$2,
        );
        parts.removeAt(i + 1);
      }
    }

    final kept = <(String, String)>[];
    for (final (joiner, part) in parts) {
      final name = names.firstWhere(
        (n) => _word(n).hasMatch(part),
        orElse: () => '',
      );
      if (name.isEmpty) {
        kept.add((joiner, part));
      } else if (_fromList(part, name) case final rest?) {
        kept.add((joiner, rest));
      }
    }
    if (kept.isEmpty) return null;
    final text = [
      for (final (i, (joiner, part)) in kept.indexed)
        i == 0 ? part : '$joiner$part',
    ].join();
    return _tidy('$text$end');
  }

  /// The instruction with [name] taken out of a list in it, or null when it
  /// isn't in a list.
  static String? _fromList(String text, String name) {
    final x = RegExp.escape(name);
    RegExp re(String pattern) => RegExp(pattern, caseSensitive: false);
    final patterns = <RegExp, String Function(Match)>{
      // "A, X and B" -> "A and B"
      re(r',\s+(?:the\s+)?' + x + r'\b(?=\s+and\b)'): (_) => '',
      // "A, B and (drained) X" -> "A and B"
      re(r',\s+([^,]+?)\s+and\s+(?:the\s+)?(?:\w+\s+)?' + x + r'\b'): (m) =>
          ' and ${m[1]}',
      // "A and (drained) X" -> "A"
      re(r'\s+and\s+(?:the\s+)?(?:\w+\s+)?' + x + r'\b'): (_) => '',
      // "the X and a B" -> "a B"
      re(r'\b(?:the\s+)?' + x + r'\s+and\s+(?=(?:a|an|the|some)\b)'): (_) => '',
      // "the X and B" or "X, B" -> "the B"
      re(r'\b(the\s+)?' + x + r'(?:\s+and\s+|,\s+)'): (m) => m[1] ?? '',
    };
    for (final MapEntry(key: pattern, value: replace) in patterns.entries) {
      if (pattern.hasMatch(text)) {
        return text.replaceFirstMapped(pattern, replace);
      }
    }
    return null;
  }

  /// Tidies a list after taking an item out: "Add the  and" and leftover
  /// lowercase sentence starts.
  static String _tidy(String text) {
    var out = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    out = out.replaceAllMapped(
      RegExp(r'(^|[.!?]\s+)([a-z])'),
      (m) => '${m[1]}${m[2]!.toUpperCase()}',
    );
    return out;
  }
}
