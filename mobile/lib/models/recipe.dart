/// Immutable recipe and step models for CookTogether.
class RecipeStep {
  final String title;
  final String instruction;
  final String tip;
  final String check;
  final int? suggestedTimerSeconds;
  final String? suggestedTimerLabel;

  /// When the timer should start, said as "Tell me when the eggs are in the
  /// pan, and I'll start a 2-minute timer." Null for steps without a timer.
  final String? timerStart;
  final String visionSceneDescription;

  const RecipeStep({
    required this.title,
    required this.instruction,
    required this.tip,
    required this.check,
    this.suggestedTimerSeconds,
    this.suggestedTimerLabel,
    this.timerStart,
    required this.visionSceneDescription,
  });

  RecipeStep copyWith({String? instruction}) => RecipeStep(
    title: title,
    instruction: instruction ?? this.instruction,
    tip: tip,
    check: check,
    suggestedTimerSeconds: suggestedTimerSeconds,
    suggestedTimerLabel: suggestedTimerLabel,
    timerStart: timerStart,
    visionSceneDescription: visionSceneDescription,
  );
}

/// A change to one step for a missing ingredient: written by hand for the
/// choices on Get ready, or sent by CookAlong (adapt_steps). Fields left
/// null stay as they were.
class StepEdit {
  final String? text;
  final String? title;
  final String? tip;
  final String? check;
  final String? timerLabel;
  final String? timerStart;

  /// The new suggested timer; 0 takes the timer away.
  final int? timerSeconds;

  /// Nothing is left to do in the step, so it goes.
  final bool remove;

  const StepEdit({
    this.text,
    this.title,
    this.tip,
    this.check,
    this.timerLabel,
    this.timerStart,
    this.timerSeconds,
  }) : remove = false;

  const StepEdit.remove()
    : text = null,
      title = null,
      tip = null,
      check = null,
      timerLabel = null,
      timerStart = null,
      timerSeconds = null,
      remove = true;

  RecipeStep applyTo(RecipeStep step) {
    final seconds = timerSeconds ?? step.suggestedTimerSeconds;
    final hasTimer = seconds != null && seconds > 0;
    return RecipeStep(
      title: title ?? step.title,
      instruction: text ?? step.instruction,
      tip: tip ?? step.tip,
      check: check ?? step.check,
      suggestedTimerSeconds: hasTimer ? seconds : null,
      suggestedTimerLabel: hasTimer
          ? timerLabel ?? step.suggestedTimerLabel
          : null,
      timerStart: hasTimer ? timerStart ?? step.timerStart : null,
      visionSceneDescription: step.visionSceneDescription,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StepEdit &&
      other.text == text &&
      other.title == title &&
      other.tip == tip &&
      other.check == check &&
      other.timerLabel == timerLabel &&
      other.timerSeconds == timerSeconds &&
      other.remove == remove;

  @override
  int get hashCode =>
      Object.hash(text, title, tip, check, timerLabel, timerSeconds, remove);

  @override
  String toString() => remove ? 'StepEdit.remove()' : 'StepEdit($text)';
}

/// One way to manage without a missing ingredient, picked on Get ready:
/// leave it out, or [use] a substitute. The step changes are written by
/// hand (lib/models/missing_options.dart), so they are the same for every
/// participant and always make sense (#94, #98).
class MissingOption {
  /// The substitute, or null to leave the ingredient out.
  final String? use;

  /// The changes, by step index in the original recipe.
  final Map<int, StepEdit> steps;

  /// Something new to have at hand, said in the opening: "Keep a glass of
  /// water at hand."
  final String? prepare;

  const MissingOption({this.use, this.steps = const {}, this.prepare});

  bool get leavesOut => use == null;

  String get label => use == null ? 'Leave it out' : 'Use $use';
}

/// A healthier choice offered before cooking, such as using less oil.
/// Swaps live in the recipe data so every user sees the same ones.
class HealthySwap {
  final String id;
  final String title;
  final String detail;

  /// Recipe ingredients this swap uses. When one is marked "Don't have" on
  /// Get ready, the swap is greyed out but still listed, so every
  /// participant sees the same swaps.
  final List<String> needs;

  const HealthySwap({
    required this.id,
    required this.title,
    required this.detail,
    this.needs = const [],
  });
}

class Recipe {
  final String id;
  final String name;
  final int timeMinutes;
  final String tone;
  final String icon;
  final String level;
  final List<String> ingredients;
  final List<RecipeStep> steps;
  final List<HealthySwap> swaps;

  const Recipe({
    required this.id,
    required this.name,
    required this.timeMinutes,
    required this.tone,
    required this.icon,
    required this.level,
    required this.ingredients,
    required this.steps,
    this.swaps = const [],
  });

  /// The same recipe with [steps] replaced, for example adapted to a
  /// missing ingredient.
  Recipe copyWith({List<RecipeStep>? steps}) => Recipe(
    id: id,
    name: name,
    timeMinutes: timeMinutes,
    tone: tone,
    icon: icon,
    level: level,
    ingredients: ingredients,
    steps: steps ?? this.steps,
    swaps: swaps,
  );
}

const List<Recipe> kStarterRecipes = [
  Recipe(
    id: 'salad',
    name: 'Rainbow salad bowl',
    timeMinutes: 20,
    tone: 'green',
    icon: '🥗',
    level: 'Beginner',
    ingredients: [
      'mixed greens',
      'cherry tomatoes',
      'cucumber',
      'chickpeas',
      'olive oil',
    ],
    swaps: [
      HealthySwap(
        id: 'salad-lemon-dressing',
        title: 'Lemon instead of extra oil',
        needs: ['olive oil'],
        detail:
            'Dress with one teaspoon of olive oil plus a squeeze of lemon instead of two tablespoons of oil.',
      ),
      HealthySwap(
        id: 'salad-more-chickpeas',
        title: 'Add more chickpeas',
        needs: ['chickpeas'],
        detail:
            'Use the whole can of chickpeas for extra protein and fibre, so the bowl keeps you full for longer.',
      ),
    ],
    steps: [
      RecipeStep(
        title: 'Wash & prepare',
        instruction:
            'Rinse the greens, tomatoes and cucumber. Pat the greens dry before adding them to a large bowl.',
        tip: 'No rush. Give everything a good rinse and pat dry so the dressing sticks later.',
        check: 'The vegetables look clean, dry, and ready to cut.',
        visionSceneDescription:
            'Colander & mixing bowl with rinsed mixed greens, cherry tomatoes, and whole cucumber',
      ),
      RecipeStep(
        title: 'Chop the vegetables',
        instruction:
            'Cut the tomatoes in half and slice the cucumber into bite-sized pieces. Keep your fingers tucked away from the knife.',
        tip: 'Aim for pieces about 1 to 2 cm wide on a stable cutting board.',
        check: 'The tomatoes are halved and the cucumber is sliced into bite-sized pieces.',
        visionSceneDescription:
            'Cutting board with halved cherry tomatoes and 1.5 cm cucumber slices',
      ),
      RecipeStep(
        title: 'Build your bowl',
        instruction:
            'Add the greens, chopped vegetables and drained chickpeas to the bowl. Toss gently for a minute.',
        tip: 'Use two spoons or clean hands to lift the greens from the bottom.',
        check: 'All ingredients are evenly combined in the bowl.',
        suggestedTimerSeconds: 60,
        suggestedTimerLabel: 'Toss salad gently',
        visionSceneDescription:
            'Large bowl filled with greens, halved tomatoes, cucumber, and chickpeas',
      ),
      RecipeStep(
        title: 'Dress & enjoy',
        instruction:
            'Drizzle a little olive oil over the salad and toss once more. Taste, then adjust as you like.',
        tip: 'Start with a small amount of dressing—you can always add more.',
        check: 'The salad has a light gloss of olive oil and is ready to eat.',
        visionSceneDescription:
            'Finished rainbow salad bowl with glossy dressed greens and chickpeas',
      ),
    ],
  ),
  Recipe(
    id: 'noodles',
    name: 'One-pan veggie noodles',
    timeMinutes: 25,
    tone: 'orange',
    icon: '🍜',
    level: 'Beginner',
    ingredients: ['noodles', 'carrot', 'bell pepper', 'garlic', 'soy sauce'],
    swaps: [
      HealthySwap(
        id: 'noodles-less-soy',
        title: 'Half the soy sauce',
        needs: ['soy sauce'],
        detail:
            'Start with half the soy sauce and add a squeeze of lime for flavour, which cuts the salt.',
      ),
      HealthySwap(
        id: 'noodles-extra-veg',
        title: 'Double the vegetables',
        needs: ['carrot', 'bell pepper'],
        detail:
            'Use two carrots and a whole pepper, and slightly fewer noodles, for a lighter bowl.',
      ),
    ],
    steps: [
      RecipeStep(
        title: 'Prepare the vegetables',
        instruction:
            'Wash the carrot and pepper. Peel the carrot, then slice it and half the pepper into thin strips. Peel and finely chop 1 garlic clove.',
        tip: 'Cut slowly into strips about the same size so they cook evenly.',
        check:
            'The carrot and pepper are in thin strips and the garlic is finely chopped.',
        visionSceneDescription:
            'Prep board with julienned carrot strips, sliced red bell pepper, and minced garlic',
      ),
      RecipeStep(
        title: 'Cook the noodles',
        instruction:
            "Fill a pot halfway with water and bring it to a boil. Add the noodles and cook for about 3 minutes, stirring once so they don't stick. Lift them into a bowl with tongs.",
        tip:
            'Steam and boiling water can burn. Keep your face back from the pot.',
        check: 'The noodles are soft and out of the water.',
        suggestedTimerSeconds: 180,
        suggestedTimerLabel: 'Boil noodles',
        timerStart: 'the noodles are in the water',
        visionSceneDescription:
            'Steaming cooked noodles lifted into a bowl next to the pot',
      ),
      RecipeStep(
        title: 'Cook the vegetables',
        instruction:
            'Put a pan on medium heat with a little oil and wait about a minute for it to warm up. Add the carrot, pepper and garlic and stir for about 2 minutes until they soften.',
        tip: 'Lower the heat if the garlic browns too quickly.',
        check: 'The vegetables look bright and soft, not burnt.',
        suggestedTimerSeconds: 120,
        suggestedTimerLabel: 'Cook vegetables',
        timerStart: 'the vegetables are in the pan',
        visionSceneDescription:
            'Skillet with glossy sautéed carrot and bell pepper strips over medium heat',
      ),
      RecipeStep(
        title: 'Toss together',
        instruction:
            'Add the noodles and 1 tablespoon of soy sauce to the pan. Toss with tongs for about a minute until everything is coated, then turn off the heat and serve.',
        tip: 'Taste a strand before adding more soy sauce.',
        check: 'The noodles and vegetables are evenly coated and mixed.',
        suggestedTimerSeconds: 60,
        suggestedTimerLabel: 'Toss noodles & sauce',
        timerStart: 'the noodles are in the pan',
        visionSceneDescription:
            'Pan of golden soy-glazed noodles tossed with colorful vegetable strips',
      ),
    ],
  ),
  Recipe(
    id: 'rice',
    name: 'Chickpea tomato rice',
    timeMinutes: 30,
    tone: 'red',
    icon: '🍅',
    level: 'Beginner',
    ingredients: ['cooked rice', 'chickpeas', 'tomatoes', 'onion', 'paprika'],
    swaps: [
      HealthySwap(
        id: 'rice-less-oil',
        title: 'One teaspoon of oil',
        detail:
            'Soften the onion in one teaspoon of oil with a splash of water instead of a tablespoon of oil.',
      ),
      HealthySwap(
        id: 'rice-brown-rice',
        title: 'Brown rice',
        detail:
            'Use cooked brown rice instead of white for more fibre. The steps stay the same.',
      ),
    ],
    steps: [
      RecipeStep(
        title: 'Prepare ingredients',
        instruction:
            'Dice the onion and tomatoes, then rinse and drain the chickpeas.',
        tip: 'A small, even dice helps the onion and tomatoes cook evenly.',
        check: 'Onion and tomatoes are diced and chickpeas are drained within reach.',
        visionSceneDescription:
            'Diced onion, chopped red tomatoes, and rinsed chickpeas in prep bowls',
      ),
      RecipeStep(
        title: 'Soften the onion',
        instruction:
            'Warm a little oil over medium heat and cook the onion until translucent, about five minutes.',
        tip: 'Stir every minute or so so the edges do not catch.',
        check: 'The onion is softened and translucent with a sweet aroma.',
        suggestedTimerSeconds: 300,
        suggestedTimerLabel: 'Soften onion',
        visionSceneDescription:
            'Pan with translucent, glistening diced onions over medium heat',
      ),
      RecipeStep(
        title: 'Simmer together',
        instruction:
            'Add tomatoes, chickpeas and a pinch of paprika. Simmer for 4 minutes until the tomatoes soften.',
        tip: 'If the pan looks dry, add a small splash of water.',
        check: 'The tomatoes have broken down into a rich sauce around the chickpeas.',
        suggestedTimerSeconds: 240,
        suggestedTimerLabel: 'Simmer tomato sauce',
        visionSceneDescription:
            'Simmering red tomato and chickpea sauce with paprika in a skillet',
      ),
      RecipeStep(
        title: 'Finish the rice',
        instruction:
            'Stir in cooked rice and warm through completely for 2 minutes. Turn off the heat and serve.',
        tip: 'Reheated rice should be steaming hot throughout before serving.',
        check: 'The rice is evenly coated in sauce and steaming hot.',
        suggestedTimerSeconds: 120,
        suggestedTimerLabel: 'Warm rice through',
        visionSceneDescription:
            'Steaming skillet of spiced chickpea tomato rice ready to plate',
      ),
    ],
  ),
  Recipe(
    id: 'wrap',
    name: 'Egg & spinach wraps',
    timeMinutes: 15,
    tone: 'yellow',
    icon: '🌯',
    level: 'Beginner',
    ingredients: ['eggs', 'spinach', 'tortillas', 'tomatoes', 'yogurt'],
    swaps: [
      HealthySwap(
        id: 'wrap-wholemeal',
        title: 'Wholemeal tortillas',
        detail: 'Use wholemeal tortillas instead of white ones for more fibre.',
      ),
      HealthySwap(
        id: 'wrap-more-spinach',
        title: 'Extra spinach, fewer eggs',
        needs: ['spinach'],
        detail:
            'Use one egg instead of two, and add an extra handful of spinach.',
      ),
    ],
    steps: [
      RecipeStep(
        title: 'Get everything ready',
        instruction:
            'Wash the spinach and shake off the water. Dice the tomato. Crack 2 eggs into a bowl and beat them with a fork until smooth.',
        tip: 'Wash your hands after handling raw eggs.',
        check: 'The tomato is diced and the eggs are beaten smooth.',
        visionSceneDescription:
            'Bowl of beaten yellow eggs next to washed spinach leaves and diced tomatoes',
      ),
      RecipeStep(
        title: 'Cook the eggs',
        instruction:
            "Put the pan on medium-low heat with a little oil and wait about a minute for it to warm up. Pour in the eggs and stir gently for about 2 minutes, until there's no runny egg left. Move the eggs onto a plate.",
        tip: 'Keep cooking gently if any egg still looks wet or runny.',
        check: 'The eggs are set, with no wet or runny egg left.',
        suggestedTimerSeconds: 120,
        suggestedTimerLabel: 'Scramble eggs',
        timerStart: 'the eggs are in the pan',
        visionSceneDescription:
            'Non-stick pan with fluffy, fully set scrambled egg curds',
      ),
      RecipeStep(
        title: 'Wilt the spinach',
        instruction:
            "Put the spinach in the same pan, still on the heat. Stir for about a minute until it's soft and dark green, then add it to the plate with the eggs.",
        tip: 'Spinach shrinks a lot, so a big handful is fine.',
        check: 'The spinach is soft and dark green.',
        suggestedTimerSeconds: 60,
        suggestedTimerLabel: 'Wilt spinach',
        timerStart: 'the spinach is in the pan',
        visionSceneDescription: 'Pan with bright wilted spinach leaves',
      ),
      RecipeStep(
        title: 'Warm, fill & fold',
        instruction:
            'Warm the tortilla in the pan for about 15 seconds on each side, then turn off the heat. Lay it flat, spread 1 tablespoon of yogurt down the middle, and add the eggs, spinach and tomato on top. Fold the bottom up, fold in both sides, and roll it closed.',
        tip: 'Leave a little room near the edge so the tortilla folds neatly.',
        check: 'The wrap is folded snugly and ready to eat.',
        visionSceneDescription:
            'Folded tortilla wrap filled with scrambled eggs, spinach, tomatoes, and yogurt',
      ),
    ],
  ),
];
