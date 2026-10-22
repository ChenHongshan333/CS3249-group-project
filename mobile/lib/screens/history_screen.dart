import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../theme/app_theme.dart';

/// Displays completed cooking sessions ("Your Little Wins").
class HistoryScreen extends StatelessWidget {
  final List<CookingHistoryItem> history;
  final VoidCallback onChooseRecipe;
  final VoidCallback onBack;

  const HistoryScreen({
    super.key,
    required this.history,
    required this.onChooseRecipe,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 6),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: onBack,
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
                        'YOUR LITTLE WINS',
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
                        'Cooking history',
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
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 108),
            children: [
              RichText(
                text: TextSpan(
                  style: CookTogetherTheme.headingStyle(
                    fontSize: 30,
                    height: 1.09,
                  ),
                  children: const [
                    TextSpan(text: 'Look what you\'ve '),
                    TextSpan(
                      text: 'made.',
                      style: TextStyle(color: CookTogetherTheme.terracottaRed),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Every meal is a step forward.',
                style: CookTogetherTheme.bodyStyle(
                  fontSize: 12,
                  color: CookTogetherTheme.muted,
                ),
              ),
              const SizedBox(height: 16),
              if (history.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAEF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD8DFCB)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.menu_book_rounded,
                        size: 36,
                        color: Color(0xFF5F8950),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your story starts here.',
                        style: CookTogetherTheme.headingStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Cook a meal with CookTogether and it will appear in your history.',
                        textAlign: TextAlign.center,
                        style: CookTogetherTheme.bodyStyle(
                          fontSize: 11.5,
                          color: CookTogetherTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CookTogetherTheme.terracottaRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: onChooseRecipe,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: Text(
                          'Choose a recipe',
                          style: CookTogetherTheme.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final item in history)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CookTogetherTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: CookTogetherTheme.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF3E6),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            item.recipeIcon,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.recipeName,
                                style: CookTogetherTheme.headingStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${item.date} · ${item.durationMinutes} min · ${item.visualChecksCount} glasses checks',
                                style: CookTogetherTheme.bodyStyle(
                                  fontSize: 10.5,
                                  color: CookTogetherTheme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: CookTogetherTheme.herbGreen,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
