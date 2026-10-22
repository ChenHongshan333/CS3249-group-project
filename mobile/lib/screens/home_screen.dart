import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../glasses/glasses_service.dart';
import '../models/user_preferences.dart';
import '../theme/app_theme.dart';

/// Home screen of CookTogether, featuring the warm kitchen aesthetic,
/// Orbit overview card, Meta glasses Mock Device Kit status card, and quick start CTA.
class HomeScreen extends StatelessWidget {
  final GlassesService glassesService;
  final List<CookingHistoryItem> history;
  final VoidCallback onStartCooking;
  final VoidCallback onOpenWelcomeOverview;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenProfile;

  const HomeScreen({
    super.key,
    required this.glassesService,
    required this.history,
    required this.onStartCooking,
    required this.onOpenWelcomeOverview,
    required this.onOpenHistory,
    required this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 108),
      children: [
        // Topline: Brand + Profile Avatar
        SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Transform.rotate(
                    angle: -6 * math.pi / 180,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: CookTogetherTheme.terracottaRed,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Transform.rotate(
                        angle: 6 * math.pi / 180,
                        child: const Icon(
                          Icons.restaurant_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'CookTogether',
                    style: CookTogetherTheme.headingStyle(
                      fontSize: 20,
                      letterSpacing: -0.6,
                    ),
                  ),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: onOpenProfile,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5D7AE),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'H',
                    style: CookTogetherTheme.headingStyle(
                      fontSize: 15,
                      color: const Color(0xFF9B5825),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Eyebrow
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: CookTogetherTheme.herbGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'YOUR KITCHEN COMPANION',
              style: CookTogetherTheme.bodyStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: CookTogetherTheme.herbGreen,
                letterSpacing: 1.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Hero Title
        RichText(
          text: TextSpan(
            style: CookTogetherTheme.headingStyle(
              fontSize: 33,
              height: 1.09,
              letterSpacing: -1.1,
            ),
            children: const [
              TextSpan(text: 'Hands-free cooking,\n'),
              TextSpan(
                text: 'step by step.',
                style: TextStyle(color: CookTogetherTheme.terracottaRed),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Conversational voice guidance and Meta glasses vision to walk you through every recipe at your own pace.',
          style: CookTogetherTheme.bodyStyle(
            fontSize: 13,
            color: const Color(0xFF777E72),
          ),
        ),
        const SizedBox(height: 18),
        // Orbit Card
        _buildOrbitCard(),
        const SizedBox(height: 14),
        // Start Cooking Button
        SizedBox(
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CookTogetherTheme.terracottaRed,
              foregroundColor: Colors.white,
              elevation: 3,
              shadowColor: const Color(0x38C44A3A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            onPressed: onStartCooking,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Start cooking',
                  style: CookTogetherTheme.headingStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Text(
                'Meta glasses companion',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CookTogetherTheme.headingStyle(
                  fontSize: 17,
                  letterSpacing: -0.35,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'MOCK DEVICE KIT',
              style: CookTogetherTheme.bodyStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: CookTogetherTheme.muted,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListenableBuilder(
          listenable: glassesService,
          builder: (context, _) {
            final connected = glassesService.isConnected;
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onStartCooking,
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: CookTogetherTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CookTogetherTheme.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: connected
                            ? CookTogetherTheme.toneGreenBg
                            : CookTogetherTheme.toneOrangeBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.visibility_rounded,
                        color: connected
                            ? CookTogetherTheme.deepHerbGreen
                            : CookTogetherTheme.warmOrange,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            glassesService.deviceName,
                            style: CookTogetherTheme.headingStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            connected
                                ? 'Ready · ${glassesService.batteryLevel}% battery · Vision & voice enabled'
                                : 'Tap to pair Mock Device Kit and choose a recipe',
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 11,
                              color: CookTogetherTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFA6AD9F),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpenHistory,
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F2E7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CookTogetherTheme.border),
              ),
              child: Row(
                children: [
                  Text(
                    history.first.recipeIcon,
                    style: const TextStyle(fontSize: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR LATEST LITTLE WIN',
                          style: CookTogetherTheme.bodyStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFA47C49),
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          history.first.recipeName,
                          style: CookTogetherTheme.headingStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFA6AD9F),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: CookTogetherTheme.gentleNoteBg,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.favorite_border_rounded,
                size: 18,
                color: CookTogetherTheme.gentleNoteFg,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Small steps count. Speak naturally during cooking to move between steps, set timers, or ask what your glasses see.',
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 11,
                    color: CookTogetherTheme.gentleNoteFg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrbitCard() {
    return Container(
      height: 236,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF9E8),
            Color(0xFFF8E7CB),
            Color(0xFFF4EBD7),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFF2E5CD)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Decorative orbit rings
          Transform.rotate(
            angle: -14 * math.pi / 180,
            child: Container(
              width: 248,
              height: 175,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(140),
                border: Border.all(
                  color: const Color(0xFFDEB98A).withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: 14 * math.pi / 180,
            child: Container(
              width: 295,
              height: 215,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(160),
                border: Border.all(
                  color: const Color(0xFFDEB98A).withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            bottom: 36,
            child: Text(
              '✦',
              style: TextStyle(
                color: CookTogetherTheme.terracottaRed,
                fontSize: 24,
              ),
            ),
          ),
          Positioned(
            top: 34,
            left: 20,
            child: Transform.rotate(
              angle: -8 * math.pi / 180,
              child: const _OrbitPill(text: '🥕 Prep'),
            ),
          ),
          Positioned(
            top: 38,
            right: 18,
            child: Transform.rotate(
              angle: 7 * math.pi / 180,
              child: const _OrbitPill(text: '🎙️ Voice Guide'),
            ),
          ),
          Positioned(
            bottom: 28,
            right: 24,
            child: Transform.rotate(
              angle: -6 * math.pi / 180,
              child: const _OrbitPill(text: '🕶️ Glasses Vision'),
            ),
          ),
          // Center button
          GestureDetector(
            onTap: onOpenWelcomeOverview,
            child: Container(
              width: 132,
              height: 132,
              decoration: const BoxDecoration(
                color: Color(0xFFFFFEFA),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x40D1B289),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('👩‍🍳', style: TextStyle(fontSize: 42)),
                  const SizedBox(height: 4),
                  Text(
                    'Let\'s cook!',
                    style: CookTogetherTheme.headingStyle(fontSize: 16),
                  ),
                  Text(
                    'Tap for overview',
                    style: CookTogetherTheme.bodyStyle(
                      fontSize: 10,
                      color: CookTogetherTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitPill extends StatelessWidget {
  final String text;

  const _OrbitPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEFA),
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(
            color: Color(0x228F6B39),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        style: CookTogetherTheme.bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: CookTogetherTheme.ink,
        ),
      ),
    );
  }
}
