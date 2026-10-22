import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';

/// Celebration screen shown when the user completes a recipe.
class FinishScreen extends StatelessWidget {
  final Recipe recipe;
  final int elapsedSeconds;
  final int visualChecksCount;
  final VoidCallback onBackToHome;
  final VoidCallback onViewHistory;

  const FinishScreen({
    super.key,
    required this.recipe,
    required this.elapsedSeconds,
    required this.visualChecksCount,
    required this.onBackToHome,
    required this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = (elapsedSeconds / 60).ceil().clamp(1, 999);

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
                  onTap: onBackToHome,
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
                        'SESSION COMPLETE',
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
                        'A meal well made',
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
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
            children: [
              const Center(
                child: Text(
                  '✦    ✳    ✦',
                  style: TextStyle(
                    fontSize: 22,
                    color: CookTogetherTheme.warmOrange,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  recipe.icon,
                  style: const TextStyle(fontSize: 80),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'You made it!',
                  style: CookTogetherTheme.headingStyle(fontSize: 31),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'One delicious cooking accomplishment, guided step by step with CookTogether.',
                  textAlign: TextAlign.center,
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 12,
                    color: CookTogetherTheme.muted,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Stats Card
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: CookTogetherTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CookTogetherTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatColumn(
                        value: '${recipe.steps.length}',
                        label: 'steps completed',
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color: CookTogetherTheme.border,
                    ),
                    Expanded(
                      child: _StatColumn(
                        value: '$minutes',
                        label: 'minutes cooking',
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color: CookTogetherTheme.border,
                    ),
                    Expanded(
                      child: _StatColumn(
                        value: '$visualChecksCount',
                        label: 'glasses checks',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Finished Plate Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6FAEF),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: const Color(0xFFDFE8D6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'COMPLETED RECIPE',
                              style: CookTogetherTheme.bodyStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: CookTogetherTheme.deepHerbGreen,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              recipe.name,
                              style: CookTogetherTheme.headingStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const Icon(
                          Icons.favorite_rounded,
                          color: CookTogetherTheme.herbGreen,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 112,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFE7ECCF),
                            Color(0xFFF6D99C),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            recipe.icon,
                            style: const TextStyle(fontSize: 48),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your finished plate',
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF5E7058),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: CookTogetherTheme.gentleNoteBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bookmark_added_outlined,
                      size: 20,
                      color: CookTogetherTheme.gentleNoteFg,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saved to your cooking history',
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF334B31),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Celebrate what you made! Your meal and session stats are recorded in History.',
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 10.5,
                              color: CookTogetherTheme.gentleNoteFg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
          color: CookTogetherTheme.cream,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 51,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CookTogetherTheme.terracottaRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: onBackToHome,
                    icon: const Icon(Icons.home_rounded, size: 19),
                    label: Text(
                      'Back to home',
                      style: CookTogetherTheme.headingStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onViewHistory,
                  child: Text(
                    'View cooking history',
                    style: CookTogetherTheme.bodyStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF6F8069),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;

  const _StatColumn({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: CookTogetherTheme.headingStyle(
            fontSize: 23,
            color: CookTogetherTheme.terracottaRed,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: CookTogetherTheme.bodyStyle(
            fontSize: 10,
            color: CookTogetherTheme.muted,
          ),
        ),
      ],
    );
  }
}
