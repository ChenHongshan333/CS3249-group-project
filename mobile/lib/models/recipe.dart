/// Immutable recipe and step models for CookTogether.
class RecipeStep {
  final String title;
  final String instruction;
  final String tip;
  final String check;
  final int? suggestedTimerSeconds;
  final String? suggestedTimerLabel;
  final String visionSceneDescription;

  const RecipeStep({
    required this.title,
    required this.instruction,
    required this.tip,
    required this.check,
    this.suggestedTimerSeconds,
    this.suggestedTimerLabel,
    required this.visionSceneDescription,
  });
}

/// A healthier choice offered before cooking, such as using less oil.
/// Swaps live in the recipe data so every user sees the same ones.
class HealthySwap {
  final String id;
  final String title;
  final String detail;

  const HealthySwap({
    required this.id,
    required this.title,
    required this.detail,
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
        detail:
            'Dress with one teaspoon of olive oil plus a squeeze of lemon instead of two tablespoons of oil.',
      ),
      HealthySwap(
        id: 'salad-more-chickpeas',
        title: 'Add more chickpeas',
        detail:
            'Use the whole can of chickpeas for extra protein and fibre, so the bowl keeps you full for longer.',
      ),
    ],
    steps: [
      RecipeStep(
        title: 'Wash & prepare',
        instruction:
            'Rinse the greens, tomatoes and cucumber. Pat the greens dry before adding them to a large bowl.',
        tip:
            'No rush. Give everything a good rinse and pat dry so the dressing sticks later.',
        check: 'The vegetables look clean, dry, and ready to cut.',
        visionSceneDescription:
            'Colander & mixing bowl with rinsed mixed greens, cherry tomatoes, and whole cucumber',
      ),
      RecipeStep(
        title: 'Chop the vegetables',
        instruction:
            'Cut the tomatoes in half and slice the cucumber into bite-sized pieces. Keep your fingers tucked away from the knife.',
        tip: 'Aim for pieces about 1 to 2 cm wide on a stable cutting board.',
        check:
            'The tomatoes are halved and the cucumber is sliced into bite-sized pieces.',
        visionSceneDescription:
            'Cutting board with halved cherry tomatoes and 1.5 cm cucumber slices',
      ),
      RecipeStep(
        title: 'Build your bowl',
        instruction:
            'Add the greens, chopped vegetables and drained chickpeas to the bowl. Toss gently for a minute.',
        tip:
            'Use two spoons or clean hands to lift the greens from the bottom.',
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
        detail:
            'Start with half the soy sauce and add a squeeze of lime for flavour, which cuts the salt.',
      ),
      HealthySwap(
        id: 'noodles-extra-veg',
        title: 'Double the vegetables',
        detail:
            'Use two carrots and a whole pepper, and slightly fewer noodles, for a lighter bowl.',
      ),
    ],
    steps: [
      RecipeStep(
        title: 'Prepare the vegetables',
        instruction:
            'Wash and slice the carrot and bell pepper into thin strips. Mince one clove of garlic.',
        tip:
            'Cut slowly into uniform thin strips so they soften at the same pace.',
        check:
            'The carrot and pepper are thinly sliced and garlic is finely minced.',
        visionSceneDescription:
            'Prep board with julienned carrot strips, sliced red bell pepper, and minced garlic',
      ),
      RecipeStep(
        title: 'Cook the noodles',
        instruction:
            'Bring water to a boil and cook the noodles for about 3 minutes according to the packet. Drain carefully.',
        tip:
            'Steam and boiling water can burn. Pour away from yourself when draining.',
        check: 'The noodles are tender, loosened, and drained in a colander.',
        suggestedTimerSeconds: 180,
        suggestedTimerLabel: 'Boil noodles',
        visionSceneDescription:
            'Steaming cooked noodles drained in a colander over the sink',
      ),
      RecipeStep(
        title: 'Sauté the vegetables',
        instruction:
            'On medium heat, add a little oil, then cook the carrot, pepper and garlic for 2 minutes until softened.',
        tip: 'Lower the heat if the garlic browns too quickly.',
        check: 'The vegetables look bright and tender, not burnt.',
        suggestedTimerSeconds: 120,
        suggestedTimerLabel: 'Sauté vegetables',
        visionSceneDescription:
            'Skillet with glossy sautéed carrot and bell pepper strips over medium heat',
      ),
      RecipeStep(
        title: 'Toss together',
        instruction:
            'Add the noodles and a splash of soy sauce. Toss for a minute, turn off the heat and serve.',
        tip: 'Taste a strand before adding more soy sauce.',
        check: 'The noodles and vegetables are evenly coated and mixed.',
        suggestedTimerSeconds: 60,
        suggestedTimerLabel: 'Toss noodles & sauce',
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
        check:
            'Onion and tomatoes are diced and chickpeas are drained within reach.',
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
        check:
            'The tomatoes have broken down into a rich sauce around the chickpeas.',
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
        detail:
            'Use two eggs per two wraps instead of three, and add an extra handful of spinach.',
      ),
    ],
    steps: [
      RecipeStep(
        title: 'Get everything ready',
        instruction:
            'Wash the spinach and dice the tomatoes. Beat the eggs in a bowl with a fork until smooth.',
        tip: 'Wash your hands after handling raw eggs.',
        check: 'The spinach is clean, tomatoes are diced, and eggs are beaten.',
        visionSceneDescription:
            'Bowl of beaten yellow eggs next to washed spinach leaves and diced tomatoes',
      ),
      RecipeStep(
        title: 'Cook the eggs',
        instruction:
            'Warm a pan on medium-low heat and cook the eggs for 2 minutes, stirring gently until fully set.',
        tip: 'Keep cooking gently if any egg still looks liquid or runny.',
        check:
            'The scrambled eggs are soft, curded, and fully set with no runny spots.',
        suggestedTimerSeconds: 120,
        suggestedTimerLabel: 'Scramble eggs',
        visionSceneDescription:
            'Non-stick pan with fluffy, fully set scrambled egg curds',
      ),
      RecipeStep(
        title: 'Add the greens',
        instruction:
            'Add spinach to the pan for a minute, just until it wilts. Turn off the heat.',
        tip: 'Spinach wilts quickly from the residual warmth of the pan.',
        check: 'The spinach leaves have wilted into the warm eggs.',
        suggestedTimerSeconds: 60,
        suggestedTimerLabel: 'Wilt spinach',
        visionSceneDescription:
            'Scrambled eggs folded with bright wilted spinach leaves in the pan',
      ),
      RecipeStep(
        title: 'Assemble & serve',
        instruction:
            'Spoon eggs and spinach onto a tortilla. Add tomatoes and yogurt, then fold into a wrap.',
        tip: 'Leave a little room near the edge so the tortilla folds neatly.',
        check: 'The wrap is folded snugly and ready to eat.',
        visionSceneDescription:
            'Folded tortilla wrap filled with scrambled eggs, spinach, tomatoes, and yogurt',
      ),
    ],
  ),
];
