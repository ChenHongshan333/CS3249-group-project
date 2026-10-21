export type Recipe = {
  id: string
  name: string
  time: number
  tone: string
  icon: string
  level: string
  ingredients: string[]
  steps: { title: string; instruction: string; tip: string; check: string }[]
}

export const recipes: Recipe[] = [
  {
    id: 'salad', name: 'Rainbow salad bowl', time: 20, tone: 'green', icon: '🥗', level: 'Beginner',
    ingredients: ['mixed greens', 'cherry tomatoes', 'cucumber', 'chickpeas', 'olive oil'],
    steps: [
      { title: 'Wash & prepare', instruction: 'Rinse the greens, tomatoes and cucumber. Pat the greens dry before adding them to a large bowl.', tip: 'No rush. Give everything a good rinse.', check: 'The vegetables look clean and ready to cut.' },
      { title: 'Chop the vegetables', instruction: 'Cut the tomatoes in half and slice the cucumber into bite-sized pieces. Keep your fingers tucked away from the knife.', tip: 'A stable cutting board makes this much easier.', check: 'The tomatoes and cucumber are chopped.' },
      { title: 'Build your bowl', instruction: 'Add the greens, chopped vegetables and drained chickpeas to the bowl. Toss gently.', tip: 'You and your partner can compare your colorful bowls.', check: 'All ingredients are combined in the bowl.' },
      { title: 'Dress & enjoy', instruction: 'Drizzle a little olive oil over the salad and toss once more. Taste, then adjust as you like.', tip: 'Start with a small amount of dressing.', check: 'The salad is dressed and ready to eat.' },
    ],
  },
  {
    id: 'noodles', name: 'One-pan veggie noodles', time: 25, tone: 'orange', icon: '🍜', level: 'Beginner',
    ingredients: ['noodles', 'carrot', 'bell pepper', 'garlic', 'soy sauce'],
    steps: [
      { title: 'Prepare the vegetables', instruction: 'Wash and slice the carrot and bell pepper into thin strips. Mince one clove of garlic.', tip: 'Cut slowly and use a stable board.', check: 'The vegetables are sliced and garlic is minced.' },
      { title: 'Cook the noodles', instruction: 'Bring water to a boil and cook the noodles according to the packet. Drain carefully.', tip: 'Steam and boiling water can burn. Ask for help if needed.', check: 'The noodles are soft and drained.' },
      { title: 'Sauté the vegetables', instruction: 'On medium heat, add a little oil, then cook the carrot, pepper and garlic until softened.', tip: 'Lower the heat if the garlic browns quickly.', check: 'The vegetables look tender, not burnt.' },
      { title: 'Toss together', instruction: 'Add the noodles and a splash of soy sauce. Toss for a minute, turn off the heat and serve.', tip: 'Taste before adding more sauce.', check: 'The noodles and vegetables are evenly mixed.' },
    ],
  },
  {
    id: 'rice', name: 'Chickpea tomato rice', time: 30, tone: 'red', icon: '🍅', level: 'Beginner',
    ingredients: ['cooked rice', 'chickpeas', 'tomatoes', 'onion', 'paprika'],
    steps: [
      { title: 'Prepare ingredients', instruction: 'Dice the onion and tomatoes, then rinse and drain the chickpeas.', tip: 'A small dice cooks evenly.', check: 'Everything is prepped and within reach.' },
      { title: 'Soften the onion', instruction: 'Warm a little oil over medium heat and cook the onion until translucent, about five minutes.', tip: 'Stir now and then so it does not catch.', check: 'The onion is softened and translucent.' },
      { title: 'Simmer together', instruction: 'Add tomatoes, chickpeas and a pinch of paprika. Simmer until the tomatoes soften.', tip: 'If the pan looks dry, add a splash of water.', check: 'The tomatoes have broken down into a sauce.' },
      { title: 'Finish the rice', instruction: 'Stir in cooked rice and warm through completely. Turn off the heat and serve.', tip: 'Reheated rice should be steaming hot throughout.', check: 'The rice is steaming hot and ready.' },
    ],
  },
  {
    id: 'wrap', name: 'Egg & spinach wraps', time: 15, tone: 'yellow', icon: '🌯', level: 'Beginner',
    ingredients: ['eggs', 'spinach', 'tortillas', 'tomatoes', 'yogurt'],
    steps: [
      { title: 'Get everything ready', instruction: 'Wash the spinach and tomatoes. Beat the eggs in a bowl with a fork.', tip: 'Wash your hands after handling raw eggs.', check: 'The spinach is clean and the eggs are beaten.' },
      { title: 'Cook the eggs', instruction: 'Warm a pan on medium-low heat and cook the eggs, stirring gently until fully set.', tip: 'Keep cooking if any egg still looks runny.', check: 'The eggs are fully set, with no runny spots.' },
      { title: 'Add the greens', instruction: 'Add spinach to the pan for a minute, just until it wilts. Turn off the heat.', tip: 'The greens cook quickly.', check: 'The spinach has wilted.' },
      { title: 'Assemble & serve', instruction: 'Spoon eggs and spinach onto a tortilla. Add tomatoes and yogurt, then fold into a wrap.', tip: 'Leave room near the edge so it folds easily.', check: 'The wrap is folded and ready to eat.' },
    ],
  },
]

export type Mode = 'solo' | 'offline' | 'online'
export type Screen = 'home' | 'friends' | 'preferences' | 'recipes' | 'mode' | 'pair' | 'cook' | 'finish' | 'history' | 'community' | 'profile'
