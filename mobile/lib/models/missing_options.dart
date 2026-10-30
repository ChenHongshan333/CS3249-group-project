import 'recipe.dart';

/// The ways to manage without each starter recipe ingredient, offered on
/// Get ready when it is marked "Don't have" (#98). "Leave it out" comes
/// first and is the default. Step numbers are indexes into the recipe's
/// steps in lib/models/recipe.dart; test/missing_options_test.dart checks
/// that no changed step still names the missing ingredient.
List<MissingOption> waysWithout(Recipe recipe, String ingredient) =>
    _options[recipe.id]?[ingredient] ?? const [MissingOption()];

const _water = 'Keep a glass of water at hand.';

const Map<String, Map<String, List<MissingOption>>> _options = {
  'salad': {
    'mixed greens': [
      MissingOption(
        steps: {
          0: StepEdit(
            text: 'Rinse the tomatoes and cucumber, then pat them dry.',
          ),
          2: StepEdit(
            text:
                'Add the chopped vegetables and drained chickpeas to a large bowl. Toss gently for a minute.',
            tip: 'Use two spoons or clean hands to lift from the bottom.',
          ),
        },
      ),
      MissingOption(
        use: 'spinach',
        steps: {
          0: StepEdit(
            text:
                'Rinse the spinach, tomatoes and cucumber. Pat the spinach dry before adding it to a large bowl.',
          ),
          2: StepEdit(
            text:
                'Add the spinach, chopped vegetables and drained chickpeas to the bowl. Toss gently for a minute.',
            tip:
                'Use two spoons or clean hands to lift the spinach from the bottom.',
          ),
        },
      ),
    ],
    'cherry tomatoes': [
      MissingOption(
        steps: {
          0: StepEdit(
            text:
                'Rinse the greens and cucumber. Pat the greens dry before adding them to a large bowl.',
          ),
          1: StepEdit(
            text:
                'Slice the cucumber into bite-sized pieces. Keep your fingers tucked away from the knife.',
            check: 'The cucumber is sliced into bite-sized pieces.',
          ),
        },
      ),
      MissingOption(
        use: 'red pepper',
        steps: {
          0: StepEdit(
            text:
                'Rinse the greens, red pepper and cucumber. Pat the greens dry before adding them to a large bowl.',
          ),
          1: StepEdit(
            text:
                'Cut the red pepper into small pieces, leaving out the seeds, and slice the cucumber into bite-sized pieces. Keep your fingers tucked away from the knife.',
            check:
                'The red pepper and cucumber are cut into bite-sized pieces.',
          ),
        },
      ),
    ],
    'cucumber': [
      MissingOption(
        steps: {
          0: StepEdit(
            text:
                'Rinse the greens and tomatoes. Pat the greens dry before adding them to a large bowl.',
          ),
          1: StepEdit(
            text:
                'Cut the tomatoes in half. Keep your fingers tucked away from the knife.',
            check: 'The tomatoes are halved.',
          ),
        },
      ),
      MissingOption(
        use: 'celery',
        steps: {
          0: StepEdit(
            text:
                'Rinse the greens, tomatoes and celery. Pat the greens dry before adding them to a large bowl.',
          ),
          1: StepEdit(
            text:
                'Cut the tomatoes in half and slice the celery thinly. Keep your fingers tucked away from the knife.',
            check: 'The tomatoes are halved and the celery is thinly sliced.',
          ),
        },
      ),
    ],
    'chickpeas': [
      MissingOption(
        steps: {
          2: StepEdit(
            text:
                'Add the greens and chopped vegetables to the bowl. Toss gently for a minute.',
          ),
        },
      ),
      MissingOption(
        use: 'white beans',
        steps: {
          2: StepEdit(
            text:
                'Add the greens, chopped vegetables and drained white beans to the bowl. Toss gently for a minute.',
          ),
        },
      ),
    ],
    'olive oil': [
      MissingOption(
        steps: {
          3: StepEdit(
            title: 'Season & enjoy',
            text:
                'Toss the salad once more. Taste, then add a pinch of salt if you like.',
            tip: 'A pinch of salt brings out the flavour of the vegetables.',
            check: 'The salad is tossed and ready to eat.',
          ),
        },
      ),
      MissingOption(
        use: 'lemon juice',
        steps: {
          3: StepEdit(
            text:
                'Squeeze a little lemon juice over the salad and toss once more. Taste, then adjust as you like.',
            tip: 'Start with a small squeeze; you can always add more.',
            check: 'The salad is lightly dressed and ready to eat.',
          ),
        },
      ),
    ],
  },
  'noodles': {
    'noodles': [
      MissingOption(
        steps: {
          1: StepEdit.remove(),
          3: StepEdit(
            title: 'Season & serve',
            text:
                'Add 1 tablespoon of soy sauce to the vegetables. Toss for about a minute until they\'re coated, then turn off the heat and serve.',
            tip: 'Taste before adding more soy sauce.',
            check: 'The vegetables are evenly coated in sauce.',
            timerLabel: 'Toss with sauce',
            timerStart: 'the soy sauce is in',
          ),
        },
      ),
      MissingOption(
        use: 'spaghetti',
        steps: {
          1: StepEdit(
            title: 'Cook the spaghetti',
            text:
                'Fill a pot halfway with water and bring it to a boil. Add the spaghetti and cook for about 9 minutes, or as the packet says, stirring now and then. Lift it into a bowl with tongs.',
            check: 'The spaghetti is soft and out of the water.',
            timerSeconds: 540,
            timerLabel: 'Boil spaghetti',
            timerStart: 'the spaghetti is in the water',
          ),
          3: StepEdit(
            text:
                'Add the spaghetti and 1 tablespoon of soy sauce to the pan. Toss with tongs for about a minute until everything is coated, then turn off the heat and serve.',
            check: 'The spaghetti and vegetables are evenly coated and mixed.',
            timerLabel: 'Toss spaghetti & sauce',
            timerStart: 'the spaghetti is in the pan',
          ),
        },
      ),
    ],
    'carrot': [
      MissingOption(
        steps: {
          0: StepEdit(
            text:
                'Wash the pepper and slice half of it into thin strips. Peel and finely chop 1 garlic clove.',
            check:
                'The pepper is in thin strips and the garlic is finely chopped.',
          ),
          2: StepEdit(
            text:
                'Put a pan on medium heat with a little oil and wait about a minute for it to warm up. Add the pepper and garlic and stir for about 2 minutes until they soften.',
          ),
        },
      ),
      MissingOption(
        use: 'courgette',
        steps: {
          0: StepEdit(
            text:
                'Wash the courgette and pepper. Slice the courgette and half the pepper into thin strips. Peel and finely chop 1 garlic clove.',
            check:
                'The courgette and pepper are in thin strips and the garlic is finely chopped.',
          ),
          2: StepEdit(
            text:
                'Put a pan on medium heat with a little oil and wait about a minute for it to warm up. Add the courgette, pepper and garlic and stir for about 2 minutes until they soften.',
          ),
        },
      ),
    ],
    'bell pepper': [
      MissingOption(
        steps: {
          0: StepEdit(
            text:
                'Wash and peel the carrot, then slice it into thin strips. Peel and finely chop 1 garlic clove.',
            check:
                'The carrot is in thin strips and the garlic is finely chopped.',
          ),
          2: StepEdit(
            text:
                'Put a pan on medium heat with a little oil and wait about a minute for it to warm up. Add the carrot and garlic and stir for about 2 minutes until they soften.',
          ),
        },
      ),
      MissingOption(
        use: 'courgette',
        steps: {
          0: StepEdit(
            text:
                'Wash the carrot and courgette. Peel the carrot, then slice it and the courgette into thin strips. Peel and finely chop 1 garlic clove.',
            check:
                'The carrot and courgette are in thin strips and the garlic is finely chopped.',
          ),
          2: StepEdit(
            text:
                'Put a pan on medium heat with a little oil and wait about a minute for it to warm up. Add the carrot, courgette and garlic and stir for about 2 minutes until they soften.',
          ),
        },
      ),
    ],
    'garlic': [
      MissingOption(
        steps: {
          0: StepEdit(
            text:
                'Wash the carrot and pepper. Peel the carrot, then slice it and half the pepper into thin strips.',
            check: 'The carrot and pepper are in thin strips.',
          ),
          2: StepEdit(
            text:
                'Put a pan on medium heat with a little oil and wait about a minute for it to warm up. Add the carrot and pepper and stir for about 2 minutes until they soften.',
            tip: 'Lower the heat if the vegetables brown too quickly.',
          ),
        },
      ),
      MissingOption(
        use: 'shallot',
        steps: {
          0: StepEdit(
            text:
                'Wash the carrot and pepper. Peel the carrot, then slice it and half the pepper into thin strips. Peel and finely chop 1 small shallot.',
            check:
                'The carrot and pepper are in thin strips and the shallot is finely chopped.',
          ),
          2: StepEdit(
            text:
                'Put a pan on medium heat with a little oil and wait about a minute for it to warm up. Add the carrot, pepper and shallot and stir for about 2 minutes until they soften.',
            tip: 'Lower the heat if the shallot browns too quickly.',
          ),
        },
      ),
    ],
    'soy sauce': [
      MissingOption(
        steps: {
          3: StepEdit(
            text:
                'Add the noodles and a pinch of salt to the pan. Toss with tongs for about a minute until everything is coated, then turn off the heat and serve.',
            tip: 'Taste a strand before adding more salt.',
            check: 'The noodles and vegetables are evenly mixed.',
            timerLabel: 'Toss noodles',
          ),
        },
      ),
      MissingOption(
        use: 'oyster sauce',
        steps: {
          3: StepEdit(
            text:
                'Add the noodles and 1 tablespoon of oyster sauce to the pan. Toss with tongs for about a minute until everything is coated, then turn off the heat and serve.',
            tip: 'Taste a strand before adding more oyster sauce.',
            timerLabel: 'Toss noodles',
          ),
        },
      ),
    ],
  },
  'rice': {
    'cooked rice': [
      MissingOption(
        steps: {
          3: StepEdit(
            title: 'Serve',
            text:
                'Turn off the heat and spoon the chickpeas and sauce into bowls.',
            tip: 'Bread on the side is nice for the sauce, if you have some.',
            check: 'The chickpeas and sauce are in bowls, ready to eat.',
            timerSeconds: 0,
          ),
        },
      ),
      MissingOption(
        use: 'couscous',
        prepare: 'Have your couscous cooked and ready.',
        steps: {
          3: StepEdit(
            title: 'Finish the couscous',
            text:
                'Stir in the cooked couscous and warm it through for 2 minutes. Turn off the heat and serve.',
            tip: 'Stir gently so the couscous stays fluffy.',
            check: 'The couscous is evenly coated in sauce and hot.',
            timerLabel: 'Warm couscous through',
          ),
        },
      ),
    ],
    'chickpeas': [
      MissingOption(
        steps: {
          0: StepEdit(
            text: 'Dice the onion and tomatoes.',
            check: 'Onion and tomatoes are diced.',
          ),
          2: StepEdit(
            text:
                'Add the tomatoes and a pinch of paprika. Simmer for 4 minutes until the tomatoes soften.',
            check: 'The tomatoes have broken down into a rich sauce.',
          ),
        },
      ),
      MissingOption(
        use: 'white beans',
        steps: {
          0: StepEdit(
            text:
                'Dice the onion and tomatoes, then rinse and drain the white beans.',
            check:
                'Onion and tomatoes are diced and white beans are drained within reach.',
          ),
          2: StepEdit(
            text:
                'Add tomatoes, white beans and a pinch of paprika. Simmer for 4 minutes until the tomatoes soften.',
            check:
                'The tomatoes have broken down into a rich sauce around the white beans.',
          ),
        },
      ),
    ],
    'tomatoes': [
      MissingOption(
        prepare: _water,
        steps: {
          0: StepEdit(
            text: 'Dice the onion, then rinse and drain the chickpeas.',
            tip: 'A small, even dice helps the onion cook evenly.',
            check: 'The onion is diced and chickpeas are drained within reach.',
          ),
          2: StepEdit(
            title: 'Simmer the chickpeas',
            text:
                'Add the chickpeas, a pinch of paprika and a splash of water. Simmer for 4 minutes, stirring now and then.',
            tip: 'Add a little more water if the pan looks dry.',
            check: 'The chickpeas are hot and coated in the paprika.',
            timerLabel: 'Simmer chickpeas',
          ),
          3: StepEdit(
            check:
                'The rice is evenly mixed with the chickpeas and steaming hot.',
          ),
        },
      ),
      MissingOption(
        use: 'passata',
        steps: {
          0: StepEdit(
            text: 'Dice the onion, then rinse and drain the chickpeas.',
            tip: 'A small, even dice helps the onion cook evenly.',
            check: 'The onion is diced and chickpeas are drained within reach.',
          ),
          2: StepEdit(
            text:
                'Add half a cup of passata, the chickpeas and a pinch of paprika. Simmer for 4 minutes until the sauce thickens.',
            check:
                'The passata has thickened into a rich sauce around the chickpeas.',
            timerLabel: 'Simmer the sauce',
          ),
        },
      ),
      MissingOption(
        use: 'tomato paste',
        prepare: _water,
        steps: {
          0: StepEdit(
            text: 'Dice the onion, then rinse and drain the chickpeas.',
            tip: 'A small, even dice helps the onion cook evenly.',
            check: 'The onion is diced and chickpeas are drained within reach.',
          ),
          2: StepEdit(
            text:
                'Stir in two tablespoons of tomato paste with a splash of water, then add the chickpeas and a pinch of paprika. Simmer for 4 minutes until the sauce thickens.',
            check: 'The sauce has thickened around the chickpeas.',
            timerLabel: 'Simmer the sauce',
          ),
        },
      ),
    ],
    'onion': [
      MissingOption(
        steps: {
          0: StepEdit(
            text: 'Dice the tomatoes, then rinse and drain the chickpeas.',
            tip: 'A small, even dice helps the tomatoes cook evenly.',
            check: 'Tomatoes are diced and chickpeas are drained within reach.',
          ),
          // Only the onion cooks here; warming the oil moves to the next step.
          1: StepEdit.remove(),
          2: StepEdit(
            text:
                'Warm a little oil over medium heat. Add the tomatoes, chickpeas and a pinch of paprika, and simmer for 4 minutes until the tomatoes soften.',
          ),
        },
      ),
      MissingOption(
        use: 'leek',
        steps: {
          0: StepEdit(
            text:
                'Slice the leek thinly and dice the tomatoes, then rinse and drain the chickpeas.',
            tip: 'Thin, even pieces help the leek and tomatoes cook evenly.',
            check:
                'The leek is sliced, tomatoes are diced and chickpeas are drained within reach.',
          ),
          1: StepEdit(
            title: 'Soften the leek',
            text:
                'Warm a little oil over medium heat and cook the leek until soft, about five minutes.',
            check: 'The leek is soft and glossy.',
            timerLabel: 'Soften leek',
          ),
        },
      ),
    ],
    'paprika': [
      MissingOption(
        steps: {
          2: StepEdit(
            text:
                'Add tomatoes and chickpeas. Simmer for 4 minutes until the tomatoes soften.',
          ),
        },
      ),
      MissingOption(
        use: 'cumin',
        steps: {
          2: StepEdit(
            text:
                'Add tomatoes, chickpeas and a pinch of cumin. Simmer for 4 minutes until the tomatoes soften.',
          ),
        },
      ),
    ],
  },
  'wrap': {
    'eggs': [
      MissingOption(
        steps: {
          0: StepEdit(
            text: 'Wash the spinach and shake off the water. Dice the tomato.',
            tip: 'Pat the spinach dry so the wraps don\'t go soggy.',
            check: 'The tomato is diced.',
          ),
          1: StepEdit.remove(),
          2: StepEdit(
            text:
                'Put the pan on medium heat with a little oil. Add the spinach and a pinch of salt and stir for about a minute until it\'s soft and dark green, then move it to a plate.',
            tip: 'Spinach wilts quickly, so keep it moving.',
          ),
          3: StepEdit(
            text:
                'Warm the tortilla in the pan for about 15 seconds on each side, then turn off the heat. Lay it flat, spread 1 tablespoon of yogurt down the middle, and add the spinach and tomato on top. Fold the bottom up, fold in both sides, and roll it closed.',
          ),
        },
      ),
      MissingOption(
        use: 'tofu',
        steps: {
          0: StepEdit(
            text:
                'Wash the spinach and shake off the water. Dice the tomato. Drain the tofu and crumble it into a bowl with a fork.',
            tip: 'Pat the tofu dry with a paper towel so it browns in the pan.',
            check: 'The tomato is diced and the tofu is crumbled.',
          ),
          1: StepEdit(
            title: 'Cook the tofu',
            text:
                'Put the pan on medium heat with a little oil and wait about a minute for it to warm up. Add the tofu and cook for about 3 minutes, stirring now and then, until hot and lightly golden. Move it onto a plate.',
            tip: 'Add a pinch of salt, since tofu needs seasoning.',
            check: 'The tofu is hot and lightly golden.',
            timerSeconds: 180,
            timerLabel: 'Cook tofu',
            timerStart: 'the tofu is in the pan',
          ),
          2: StepEdit(
            text:
                'Put the spinach in the same pan, still on the heat. Stir for about a minute until it\'s soft and dark green, then add it to the plate with the tofu.',
          ),
          3: StepEdit(
            text:
                'Warm the tortilla in the pan for about 15 seconds on each side, then turn off the heat. Lay it flat, spread 1 tablespoon of yogurt down the middle, and add the tofu, spinach and tomato on top. Fold the bottom up, fold in both sides, and roll it closed.',
          ),
        },
      ),
    ],
    'spinach': [
      MissingOption(
        steps: {
          0: StepEdit(
            text:
                'Dice the tomato. Crack 2 eggs into a bowl and beat them with a fork until smooth.',
          ),
          2: StepEdit.remove(),
          3: StepEdit(
            text:
                'Warm the tortilla in the pan for about 15 seconds on each side, then turn off the heat. Lay it flat, spread 1 tablespoon of yogurt down the middle, and add the eggs and tomato on top. Fold the bottom up, fold in both sides, and roll it closed.',
          ),
        },
      ),
      MissingOption(
        use: 'kale',
        steps: {
          0: StepEdit(
            text:
                'Wash the kale, pull off the tough stems and chop it small. Dice the tomato. Crack 2 eggs into a bowl and beat them with a fork until smooth.',
          ),
          2: StepEdit(
            title: 'Soften the kale',
            text:
                'Put the kale in the same pan, still on the heat. Stir for about 2 minutes until it\'s soft, then add it to the plate with the eggs.',
            tip: 'Keep stirring so the kale softens evenly.',
            check: 'The kale is soft and dark green.',
            timerSeconds: 120,
            timerLabel: 'Soften kale',
            timerStart: 'the kale is in the pan',
          ),
          3: StepEdit(
            text:
                'Warm the tortilla in the pan for about 15 seconds on each side, then turn off the heat. Lay it flat, spread 1 tablespoon of yogurt down the middle, and add the eggs, kale and tomato on top. Fold the bottom up, fold in both sides, and roll it closed.',
          ),
        },
      ),
    ],
    'tortillas': [
      MissingOption(
        steps: {
          3: StepEdit(
            title: 'Serve',
            text:
                'Turn off the heat. Spoon the eggs and spinach into a bowl, top with the tomato and 1 tablespoon of yogurt, and serve.',
            tip: 'Toast on the side works well, if you have bread.',
            check:
                'The eggs and spinach are in a bowl, topped with tomato and yogurt.',
          ),
        },
      ),
      MissingOption(
        use: 'pitta bread',
        steps: {
          3: StepEdit(
            title: 'Warm & fill',
            text:
                'Warm the pitta bread in the pan for about 30 seconds on each side, then turn off the heat. Open it gently along one edge into a pocket. Spoon in the eggs and spinach, then add the tomato and 1 tablespoon of yogurt.',
            tip: 'Open the pitta gently so it doesn\'t tear.',
            check: 'The pitta is filled and ready to eat.',
          ),
        },
      ),
    ],
    'tomatoes': [
      MissingOption(
        steps: {
          0: StepEdit(
            text:
                'Wash the spinach and shake off the water. Crack 2 eggs into a bowl and beat them with a fork until smooth.',
            check: 'The eggs are beaten smooth.',
          ),
          3: StepEdit(
            text:
                'Warm the tortilla in the pan for about 15 seconds on each side, then turn off the heat. Lay it flat, spread 1 tablespoon of yogurt down the middle, and add the eggs and spinach on top. Fold the bottom up, fold in both sides, and roll it closed.',
          ),
        },
      ),
      MissingOption(
        use: 'cucumber',
        steps: {
          0: StepEdit(
            text:
                'Wash the spinach and shake off the water. Dice a little cucumber. Crack 2 eggs into a bowl and beat them with a fork until smooth.',
            check: 'The cucumber is diced and the eggs are beaten smooth.',
          ),
          3: StepEdit(
            text:
                'Warm the tortilla in the pan for about 15 seconds on each side, then turn off the heat. Lay it flat, spread 1 tablespoon of yogurt down the middle, and add the eggs, spinach and cucumber on top. Fold the bottom up, fold in both sides, and roll it closed.',
          ),
        },
      ),
    ],
    'yogurt': [
      MissingOption(
        steps: {
          3: StepEdit(
            text:
                'Warm the tortilla in the pan for about 15 seconds on each side, then turn off the heat. Lay it flat, add the eggs, spinach and tomato on top. Fold the bottom up, fold in both sides, and roll it closed.',
          ),
        },
      ),
      MissingOption(
        use: 'sour cream',
        steps: {
          3: StepEdit(
            text:
                'Warm the tortilla in the pan for about 15 seconds on each side, then turn off the heat. Lay it flat, spread 1 tablespoon of sour cream down the middle, and add the eggs, spinach and tomato on top. Fold the bottom up, fold in both sides, and roll it closed.',
          ),
        },
      ),
    ],
  },
};
