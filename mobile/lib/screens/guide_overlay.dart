import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class _GuidePage {
  final String emoji;
  final String title;
  final String body;
  final List<String> examples;

  const _GuidePage({
    required this.emoji,
    required this.title,
    required this.body,
    this.examples = const [],
  });
}

const _pages = [
  _GuidePage(
    emoji: '👋',
    title: 'Meet CookTogether',
    body:
        "I'll talk you through a recipe, one step at a time, so your hands "
        "can stay on the food. I'm an AI guide: I can't tell you if food is "
        'safe to eat or free of allergens.',
  ),
  _GuidePage(
    emoji: '🗣️',
    title: 'Say "Hey Cooky" first',
    body:
        "Then say what you need in the same breath. If I don't hear you, "
        'tap the mic and speak.',
    examples: ['"Hey Cooky, next step"'],
  ),
  _GuidePage(
    emoji: '💬',
    title: 'Things you can say',
    body: 'Or ask anything about the step you\'re on.',
    examples: [
      '"Next step" or "go back"',
      '"Repeat that"',
      '"Start the timer" or "stop the timer"',
      '"How do I know the egg is done?"',
    ],
  ),
  _GuidePage(
    emoji: '👓',
    title: 'Check with your glasses',
    body:
        "Look at your food and say it. The glasses take a photo and I'll "
        'tell you what I see. You decide when it\'s done.',
    examples: ['"Hey Cooky, check this"'],
  ),
  _GuidePage(
    emoji: '📱',
    title: 'The phone is a backup',
    body:
        'Keep it on the counter. The current step and any timer are on the '
        'screen if you want to glance at it, and every button works too.',
  ),
];

/// First-use guide: a few swipeable cards on how to talk to CookTogether.
/// Shown on first open and again from Help on Home and from Profile.
class GuideOverlay extends StatefulWidget {
  final VoidCallback onDone;

  const GuideOverlay({super.key, required this.onDone});

  @override
  State<GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<GuideOverlay> {
  final _controller = PageController();
  int _page = 0;

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: const Color(0x8A263023),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Material(
        color: CookTogetherTheme.surface,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _isLast
                    ? const SizedBox(height: 48)
                    : TextButton(
                        onPressed: widget.onDone,
                        child: const Text('Skip'),
                      ),
              ),
              SizedBox(
                height: 320,
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (final page in _pages)
                      SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              page.emoji,
                              style: const TextStyle(
                                fontSize: 40,
                                fontFamilyFallback: ['Noto Color Emoji'],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(page.title, style: textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            Text(page.body, style: textTheme.bodyLarge),
                            if (page.examples.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              for (final example in page.examples)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    example,
                                    style: textTheme.titleMedium,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: 'Page ${_page + 1} of ${_pages.length}',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page
                              ? CookTogetherTheme.ink
                              : CookTogetherTheme.line,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: _isLast ? "Let's cook" : 'Next',
                onPressed: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
