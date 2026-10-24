import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Back button plus a plain title. Every inner screen uses this.
class ScreenHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final IconData backIcon;
  final String backTooltip;
  final List<Widget> actions;

  const ScreenHeader({
    super.key,
    required this.title,
    this.onBack,
    this.backIcon = Icons.arrow_back_rounded,
    this.backTooltip = 'Back',
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      // At least 56 tall; a long title on large text wraps to a second line.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            if (onBack != null)
              IconButton(
                tooltip: backTooltip,
                onPressed: onBack,
                icon: Icon(backIcon),
              )
            else
              const SizedBox(width: 12),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// The single accent button on a screen.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Shrink a long label to fit rather than cut it off.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1),
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sticky footer that holds the primary action and an optional hint.
class BottomActionBar extends StatelessWidget {
  final Widget child;
  final String? hint;

  const BottomActionBar({super.key, required this.child, this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CookTogetherTheme.gutter,
        12,
        CookTogetherTheme.gutter,
        16,
      ),
      decoration: const BoxDecoration(
        color: CookTogetherTheme.background,
        border: Border(top: BorderSide(color: CookTogetherTheme.line)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hint != null) ...[
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Recipe emoji on a soft tone square.
class EmojiTile extends StatelessWidget {
  final String emoji;
  final String tone;
  final double size;

  const EmojiTile({
    super.key,
    required this.emoji,
    required this.tone,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CookTogetherTheme.toneBackground(tone),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        emoji,
        style: TextStyle(
          fontSize: size * 0.52,
          fontFamilyFallback: const ['Noto Color Emoji'],
        ),
      ),
    );
  }
}

/// Section title with an optional trailing widget (count, link).
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Large tappable checklist row. A [missing] row shows a cross instead of
/// a tick, for something the user doesn't have.
class CheckRow extends StatelessWidget {
  final String label;
  final String? detail;
  final bool checked;
  final bool missing;
  final Widget? trailing;
  final VoidCallback onTap;

  const CheckRow({
    super.key,
    required this.label,
    this.detail,
    required this.checked,
    this.missing = false,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      checked: checked,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CookTogetherTheme.radiusControl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            // A trailing button brings its own 48 px tap height.
            padding: EdgeInsets.symmetric(
              vertical: trailing == null ? 10 : 2,
              horizontal: 4,
            ),
            child: Row(
              crossAxisAlignment: detail == null
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: checked
                        ? CookTogetherTheme.success
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: checked
                          ? CookTogetherTheme.success
                          : const Color(0xFFB4BBAE),
                      width: 1.6,
                    ),
                  ),
                  child: checked
                      ? const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.white,
                        )
                      : missing
                      ? const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: CookTogetherTheme.inkMuted,
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: textTheme.bodyLarge?.copyWith(
                          color: checked || missing
                              ? CookTogetherTheme.inkMuted
                              : CookTogetherTheme.ink,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 2),
                        Text(detail!, style: textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small coloured dot with a short label, for connection states. Long
/// labels wrap rather than being cut off, with the dot beside the first line.
class StatusDot extends StatelessWidget {
  final String label;
  final Color color;

  const StatusDot({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!;
    // Centre the dot on the first line, whatever the text scale.
    final lineHeight = MediaQuery.textScalerOf(
      context,
    ).scale(style.fontSize! * (style.height ?? 1.2));
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: lineHeight,
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: style)),
      ],
    );
  }
}
