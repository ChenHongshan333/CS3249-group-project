import 'package:flutter/material.dart';
import 'package:meta_wearables_dat_flutter/meta_wearables_dat_flutter.dart';

import '../glasses/glasses_service.dart';
import '../models/conversation.dart';
import '../models/recipe.dart';
import '../theme/app_theme.dart';

/// Step 02 / Get Ready: Pre-cooking screen for verifying Meta Glasses Mock Device Kit
/// connection, checking off ingredients, and choosing the initial voice listening mode.
class PrepScreen extends StatefulWidget {
  final Recipe recipe;
  final GlassesService glassesService;
  final VoiceListeningMode initialListeningMode;
  final void Function({
    required Set<String> checkedIngredients,
    required VoiceListeningMode listeningMode,
    required Set<String> acceptedSwapIds,
  }) onStartCookingSession;
  final VoidCallback onBack;
  final ValueChanged<String> onShowToast;

  const PrepScreen({
    super.key,
    required this.recipe,
    required this.glassesService,
    required this.initialListeningMode,
    required this.onStartCookingSession,
    required this.onBack,
    required this.onShowToast,
  });

  @override
  State<PrepScreen> createState() => _PrepScreenState();
}

class _PrepScreenState extends State<PrepScreen> {
  final Set<String> _checkedIngredients = {};
  final Set<String> _acceptedSwapIds = {};
  late VoiceListeningMode _listeningMode;

  bool get _allIngredientsReady =>
      _checkedIngredients.length == widget.recipe.ingredients.length;

  @override
  void initState() {
    super.initState();
    _listeningMode = widget.initialListeningMode;
    if (!widget.glassesService.isConnected) {
      widget.glassesService.initializeAndPairMockDevice();
    }
  }

  void _toggleAllIngredients() {
    setState(() {
      if (_allIngredientsReady) {
        _checkedIngredients.clear();
      } else {
        _checkedIngredients.addAll(widget.recipe.ingredients);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
            children: [
              RichText(
                text: TextSpan(
                  style: CookTogetherTheme.headingStyle(
                    fontSize: 30,
                    height: 1.09,
                  ),
                  children: const [
                    TextSpan(text: 'Your kitchen,\n'),
                    TextSpan(
                      text: 'your pace.',
                      style: TextStyle(color: CookTogetherTheme.terracottaRed),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Verify your Meta glasses connection, gather your ingredients, and start whenever you are ready.',
                style: CookTogetherTheme.bodyStyle(
                  fontSize: 12,
                  color: CookTogetherTheme.muted,
                ),
              ),
              const SizedBox(height: 15),
              // Selected Meal Mini Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4EDDD),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Text(
                      widget.recipe.icon,
                      style: const TextStyle(fontSize: 28),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ON THE MENU',
                            style: CookTogetherTheme.bodyStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFA98353),
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            widget.recipe.name,
                            style: CookTogetherTheme.headingStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${widget.recipe.timeMinutes} min',
                      style: CookTogetherTheme.bodyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFA98353),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Meta Glasses Mock Device Kit Card
              _buildGlassesMockKitCard(),
              const SizedBox(height: 12),
              // Interactive Ingredient Checklist Card
              _buildIngredientsCard(),
              const SizedBox(height: 12),
              if (widget.recipe.swaps.isNotEmpty) ...[
                // Optional healthier swaps, saved for the session
                _buildSwapsCard(),
                const SizedBox(height: 12),
              ],
              // Voice Navigation Mode Selector Card
              _buildVoiceModeCard(),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CookTogetherTheme.gentleNoteBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 19,
                      color: CookTogetherTheme.gentleNoteFg,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You remain in control of the camera and microphone throughout the cooking session.',
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
          ),
        ),
        // Bottom CTA
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
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CookTogetherTheme.terracottaRed,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          CookTogetherTheme.terracottaRed.withValues(
                            alpha: 0.45,
                          ),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: _allIngredientsReady
                        ? () => widget.onStartCookingSession(
                              checkedIngredients: _checkedIngredients,
                              listeningMode: _listeningMode,
                              acceptedSwapIds: _acceptedSwapIds,
                            )
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Start cooking',
                          style: CookTogetherTheme.headingStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 19),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _allIngredientsReady
                      ? 'Everything is ready — voice & glasses vision active'
                      : 'Check off your ingredients above to begin',
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 10.5,
                    color: CookTogetherTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 6),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: widget.onBack,
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
                    'STEP 02 / GET READY',
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
                    'Prep & Meta glasses check',
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
    );
  }

  Widget _buildGlassesMockKitCard() {
    return ListenableBuilder(
      listenable: widget.glassesService,
      builder: (context, _) {
        final connected = widget.glassesService.isConnected;
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: CookTogetherTheme.surface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: CookTogetherTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.visibility_rounded,
                    size: 19,
                    color: CookTogetherTheme.herbGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Meta Glasses (Mock Device Kit)',
                      style: CookTogetherTheme.headingStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: connected
                          ? CookTogetherTheme.toneGreenBg
                          : CookTogetherTheme.toneOrangeBg,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      connected ? 'PAIRED · MOCK KIT' : 'DISCONNECTED',
                      style: CookTogetherTheme.bodyStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: connected
                            ? CookTogetherTheme.deepHerbGreen
                            : CookTogetherTheme.warmOrange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.glassesService.lastStatusNote ??
                    'Simulated via meta_wearables_dat_flutter Mock Device Kit.',
                style: CookTogetherTheme.bodyStyle(
                  fontSize: 11.5,
                  color: CookTogetherTheme.muted,
                ),
              ),
              const SizedBox(height: 11),
              // Model selector chips
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final entry in const [
                    (MockGlassesModel.rayBanMeta, 'Ray-Ban Meta'),
                    (MockGlassesModel.oakleyMetaHSTN, 'Oakley Meta HSTN'),
                    (
                      MockGlassesModel.metaRayBanDisplay,
                      'Ray-Ban Display',
                    ),
                  ])
                    GestureDetector(
                      onTap: () async {
                        await widget.glassesService.initializeAndPairMockDevice(
                          model: entry.$1,
                        );
                        widget.onShowToast(
                          'Mock Device Kit switched to ${entry.$2}',
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: widget.glassesService.mockModel == entry.$1
                              ? const Color(0xFFE6F0DD)
                              : const Color(0xFFFBFAF6),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: widget.glassesService.mockModel == entry.$1
                                ? CookTogetherTheme.herbGreen
                                : const Color(0xFFE7E5DB),
                          ),
                        ),
                        child: Text(
                          entry.$2,
                          style: CookTogetherTheme.bodyStyle(
                            fontSize: 11,
                            fontWeight:
                                widget.glassesService.mockModel == entry.$1
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                            color: widget.glassesService.mockModel == entry.$1
                                ? CookTogetherTheme.deepHerbGreen
                                : const Color(0xFF5F675F),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Battery: ${widget.glassesService.batteryLevel}% · Donned · Hinge Open',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CookTogetherTheme.bodyStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF536C4B),
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () async {
                      await widget.glassesService.simulateTouchpadTap();
                      widget.onShowToast(
                        'Simulated temple touchpad tap via Mock Device Kit',
                      );
                    },
                    child: Text(
                      'Test Touchpad Tap',
                      style: CookTogetherTheme.bodyStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: CookTogetherTheme.deepHerbGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIngredientsCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: CookTogetherTheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: CookTogetherTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Before we begin',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CookTogetherTheme.headingStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_checkedIngredients.length}/${widget.recipe.ingredients.length} ready',
                style: CookTogetherTheme.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: CookTogetherTheme.herbGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tap each ingredient as you place it on your counter, or mark all ready below.',
            style: CookTogetherTheme.bodyStyle(
              fontSize: 11,
              color: CookTogetherTheme.muted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ingredient in widget.recipe.ingredients)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_checkedIngredients.contains(ingredient)) {
                        _checkedIngredients.remove(ingredient);
                      } else {
                        _checkedIngredients.add(ingredient);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _checkedIngredients.contains(ingredient)
                          ? const Color(0xFFF3F9EE)
                          : const Color(0xFFFAF9F3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _checkedIngredients.contains(ingredient)
                            ? CookTogetherTheme.herbGreen
                            : const Color(0xFFE8E8DE),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _checkedIngredients.contains(ingredient)
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 16,
                          color: _checkedIngredients.contains(ingredient)
                              ? CookTogetherTheme.herbGreen
                              : const Color(0xFFB8C3B0),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          ingredient,
                          style: CookTogetherTheme.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CookTogetherTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _toggleAllIngredients,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: _allIngredientsReady
                    ? const Color(0xFFF3F9EE)
                    : const Color(0xFFFAF9F3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _allIngredientsReady
                      ? CookTogetherTheme.herbGreen
                      : const Color(0xFFE8E8DE),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 19,
                    height: 19,
                    decoration: BoxDecoration(
                      color: _allIngredientsReady
                          ? CookTogetherTheme.herbGreen
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: _allIngredientsReady
                            ? CookTogetherTheme.herbGreen
                            : const Color(0xFFB8C3B0),
                        width: 1.5,
                      ),
                    ),
                    child: _allIngredientsReady
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'I have my ingredients ready',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CookTogetherTheme.bodyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: CookTogetherTheme.ink,
                      ),
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

  Widget _buildSwapsCard() {
    final swaps = widget.recipe.swaps;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: CookTogetherTheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: CookTogetherTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.eco_rounded,
                size: 18,
                color: CookTogetherTheme.herbGreen,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Healthier swaps',
                  style: CookTogetherTheme.headingStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'Optional',
                style: CookTogetherTheme.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: CookTogetherTheme.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Pick any you would like to try. CookTogether will guide you with them.',
            style: CookTogetherTheme.bodyStyle(
              fontSize: 11,
              color: CookTogetherTheme.muted,
            ),
          ),
          for (final swap in swaps) ...[
            const SizedBox(height: 10),
            _SwapOptionRow(
              swap: swap,
              accepted: _acceptedSwapIds.contains(swap.id),
              onChanged: (accepted) {
                setState(() {
                  if (accepted) {
                    _acceptedSwapIds.add(swap.id);
                  } else {
                    _acceptedSwapIds.remove(swap.id);
                  }
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceModeCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: CookTogetherTheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: CookTogetherTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.mic_none_rounded,
                size: 19,
                color: CookTogetherTheme.herbGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Voice navigation during cooking',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CookTogetherTheme.headingStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _VoiceModeOptionRow(
            title: 'Hands-Free Continuous Listening',
            subtitle:
                'Speak commands anytime ("next step", "set a timer", "does this look right?")',
            selected: _listeningMode == VoiceListeningMode.handsFree,
            onTap: () =>
                setState(() => _listeningMode = VoiceListeningMode.handsFree),
          ),
          const SizedBox(height: 8),
          _VoiceModeOptionRow(
            title: 'Tap-to-Speak on Voice Orb',
            subtitle: 'Only listen when you tap the microphone orb',
            selected: _listeningMode == VoiceListeningMode.tapToSpeak,
            onTap: () =>
                setState(() => _listeningMode = VoiceListeningMode.tapToSpeak),
          ),
        ],
      ),
    );
  }
}

/// One healthier swap with a toggle: tap to use it, tap again to skip it.
class _SwapOptionRow extends StatelessWidget {
  final HealthySwap swap;
  final bool accepted;
  final ValueChanged<bool> onChanged;

  const _SwapOptionRow({
    required this.swap,
    required this.accepted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!accepted),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: accepted ? const Color(0xFFF3F9EE) : const Color(0xFFFAF9F3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accepted
                ? CookTogetherTheme.herbGreen
                : const Color(0xFFE8E8DE),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    swap.title,
                    style: CookTogetherTheme.bodyStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: CookTogetherTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    swap.detail,
                    style: CookTogetherTheme.bodyStyle(
                      fontSize: 11,
                      color: CookTogetherTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accepted ? CookTogetherTheme.herbGreen : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: accepted
                      ? CookTogetherTheme.herbGreen
                      : const Color(0xFFE8E8DE),
                ),
              ),
              child: Text(
                accepted ? 'Using' : 'Use it',
                style: CookTogetherTheme.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accepted ? Colors.white : CookTogetherTheme.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceModeOptionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _VoiceModeOptionRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF5FAEF) : const Color(0xFFFBFAF5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? CookTogetherTheme.herbGreen
                : const Color(0xFFEEECE3),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: CookTogetherTheme.bodyStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: CookTogetherTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: CookTogetherTheme.bodyStyle(
                      fontSize: 10.5,
                      color: CookTogetherTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: selected
                      ? CookTogetherTheme.herbGreen
                      : const Color(0xFFC0C7BB),
                  width: selected ? 5 : 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
