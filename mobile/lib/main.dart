import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glasses/glasses_service.dart';
import 'models/conversation.dart';
import 'models/recipe.dart';
import 'models/user_preferences.dart';
import 'screens/cooking_screen.dart';
import 'screens/finish_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/prep_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/recipes_screen.dart';
import 'services/assistant_service.dart';
import 'services/voice_controller.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CookTogetherApp());
}

enum AppScreen {
  home,
  recipes,
  prep,
  cook,
  finish,
  history,
  profile,
}

class CookTogetherApp extends StatefulWidget {
  final GlassesService? glassesService;
  final AssistantService? assistantService;
  final VoiceController? voiceController;
  final bool showInitialWelcome;

  const CookTogetherApp({
    super.key,
    this.glassesService,
    this.assistantService,
    this.voiceController,
    this.showInitialWelcome = true,
  });

  @override
  State<CookTogetherApp> createState() => _CookTogetherAppState();
}

class _CookTogetherAppState extends State<CookTogetherApp> {
  static const String _kSeenWelcomeKey = 'cooktogether.seen';
  static const String _kPrefsKey = 'cooktogether.preferences';
  static const String _kHistoryKey = 'cooktogether.history';

  AppScreen _screen = AppScreen.home;
  bool _welcomeOpen = false;
  UserPreferences _preferences = const UserPreferences();
  List<CookingHistoryItem> _history = const [];
  String _selectedRecipeId = kStarterRecipes.first.id;

  Set<String> _sessionCheckedIngredients = {};
  VoiceListeningMode _sessionListeningMode = VoiceListeningMode.handsFree;
  int _lastElapsedSeconds = 0;
  int _lastVisualChecksCount = 0;

  String _toastMessage = '';
  Timer? _toastTimer;

  late final GlassesService _glassesService;
  late final AssistantService _assistantService;
  late final VoiceController _voiceController;

  Recipe get _selectedRecipe => kStarterRecipes.firstWhere(
    (r) => r.id == _selectedRecipeId,
    orElse: () => kStarterRecipes.first,
  );

  @override
  void initState() {
    super.initState();
    _glassesService =
        widget.glassesService ?? MetaWearablesDatGlassesService();
    _voiceController = widget.voiceController ?? VoiceController();
    _assistantService =
        widget.assistantService ??
        HttpAssistantService(
          baseUrlProvider: () => _preferences.serverBaseUrl,
        );

    // Pair Mock Device Kit on launch so Meta glasses status is ready
    _glassesService.initializeAndPairMockDevice();
    _loadPersistedState();
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_kSeenWelcomeKey) ?? false;
      final savedPrefs = UserPreferences.decode(prefs.getString(_kPrefsKey));
      final savedHistory = CookingHistoryItem.decodeList(
        prefs.getString(_kHistoryKey),
      );
      if (!mounted) return;
      setState(() {
        _welcomeOpen = widget.showInitialWelcome && !seen;
        _preferences = savedPrefs;
        _history = savedHistory;
      });
    } catch (_) {}
  }

  Future<void> _dismissWelcome() async {
    setState(() => _welcomeOpen = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSeenWelcomeKey, true);
    } catch (_) {}
  }

  Future<void> _savePreferences(UserPreferences updated) async {
    setState(() {
      _preferences = updated;
      _screen = AppScreen.home;
    });
    _showToast('Preferences saved');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, updated.encode());
    } catch (_) {}
  }

  Future<void> _recordCompletedSession({
    required int elapsedSeconds,
    required int stepsCompleted,
    required int visualChecksCount,
  }) async {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final formattedDate =
        '${now.day} ${months[now.month - 1]} ${now.year}';

    final item = CookingHistoryItem(
      id: 'hist-${now.millisecondsSinceEpoch}',
      recipeId: _selectedRecipe.id,
      recipeName: _selectedRecipe.name,
      recipeIcon: _selectedRecipe.icon,
      date: formattedDate,
      durationSeconds: elapsedSeconds,
      stepsCompleted: stepsCompleted,
      visualChecksCount: visualChecksCount,
    );

    final nextHistory = [item, ..._history];
    setState(() {
      _lastElapsedSeconds = elapsedSeconds;
      _lastVisualChecksCount = visualChecksCount;
      _history = nextHistory;
      _screen = AppScreen.finish;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kHistoryKey,
        CookingHistoryItem.encodeList(nextHistory),
      );
    } catch (_) {}
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    if (!mounted) return;
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(milliseconds: 3000), () {
      if (mounted) {
        setState(() => _toastMessage = '');
      }
    });
  }

  bool get _showBottomNav =>
      _screen == AppScreen.home ||
      _screen == AppScreen.history ||
      _screen == AppScreen.profile;

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CookTogether',
      debugShowCheckedModeBanner: false,
      theme: CookTogetherTheme.buildTheme(),
      home: Scaffold(
        backgroundColor: CookTogetherTheme.cream,
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Stack(
                children: [
                  _buildCurrentScreen(),
                  if (_showBottomNav)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildBottomNav(),
                    ),
                  if (_welcomeOpen) _buildWelcomeModal(),
                  if (_toastMessage.isNotEmpty) _buildToastBanner(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_screen) {
      case AppScreen.home:
        return HomeScreen(
          glassesService: _glassesService,
          history: _history,
          onStartCooking: () => setState(() => _screen = AppScreen.recipes),
          onOpenWelcomeOverview: () => setState(() => _welcomeOpen = true),
          onOpenHistory: () => setState(() => _screen = AppScreen.history),
          onOpenProfile: () => setState(() => _screen = AppScreen.profile),
        );

      case AppScreen.recipes:
        return RecipesScreen(
          recipes: kStarterRecipes,
          selectedRecipeId: _selectedRecipeId,
          onSelectRecipe: (id) => setState(() => _selectedRecipeId = id),
          onContinueToPrep: () => setState(() => _screen = AppScreen.prep),
          onBack: () => setState(() => _screen = AppScreen.home),
          onShowToast: _showToast,
        );

      case AppScreen.prep:
        return PrepScreen(
          recipe: _selectedRecipe,
          glassesService: _glassesService,
          initialListeningMode: _preferences.handsFreeListening
              ? VoiceListeningMode.handsFree
              : VoiceListeningMode.tapToSpeak,
          onStartCookingSession: ({
            required Set<String> checkedIngredients,
            required VoiceListeningMode listeningMode,
          }) {
            setState(() {
              _sessionCheckedIngredients = checkedIngredients;
              _sessionListeningMode = listeningMode;
              _screen = AppScreen.cook;
            });
          },
          onBack: () => setState(() => _screen = AppScreen.recipes),
          onShowToast: _showToast,
        );

      case AppScreen.cook:
        return CookingScreen(
          recipe: _selectedRecipe,
          preferences: _preferences,
          glassesService: _glassesService,
          assistantService: _assistantService,
          voiceController: _voiceController,
          initialCheckedIngredients: _sessionCheckedIngredients,
          initialListeningMode: _sessionListeningMode,
          onFinishCooking: _recordCompletedSession,
          onExitToHome: () => setState(() => _screen = AppScreen.home),
          onShowToast: _showToast,
        );

      case AppScreen.finish:
        return FinishScreen(
          recipe: _selectedRecipe,
          elapsedSeconds: _lastElapsedSeconds,
          visualChecksCount: _lastVisualChecksCount,
          onBackToHome: () => setState(() => _screen = AppScreen.home),
          onViewHistory: () => setState(() => _screen = AppScreen.history),
        );

      case AppScreen.history:
        return HistoryScreen(
          history: _history,
          onChooseRecipe: () => setState(() => _screen = AppScreen.recipes),
          onBack: () => setState(() => _screen = AppScreen.home),
        );

      case AppScreen.profile:
        return ProfileScreen(
          preferences: _preferences,
          history: _history,
          onSavePreferences: _savePreferences,
          onOpenHistory: () => setState(() => _screen = AppScreen.history),
          onBack: () => setState(() => _screen = AppScreen.home),
        );
    }
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFEFB),
        border: Border(top: BorderSide(color: Color(0xFFF0EBE1))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BottomNavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              active: _screen == AppScreen.home,
              onTap: () => setState(() => _screen = AppScreen.home),
            ),
            _BottomNavItem(
              icon: Icons.restaurant_menu_rounded,
              label: 'Recipes',
              active: _screen == AppScreen.recipes,
              onTap: () => setState(() => _screen = AppScreen.recipes),
            ),
            _BottomNavItem(
              icon: Icons.schedule_rounded,
              label: 'History',
              active: _screen == AppScreen.history,
              onTap: () => setState(() => _screen = AppScreen.history),
            ),
            _BottomNavItem(
              icon: Icons.person_outline_rounded,
              label: 'Profile',
              active: _screen == AppScreen.profile,
              onTap: () => setState(() => _screen = AppScreen.profile),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeModal() {
    return Container(
      color: const Color(0x8A263023),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(26),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: CookTogetherTheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 36,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8EAD0),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: const Text('👋', style: TextStyle(fontSize: 32)),
                ),
                IconButton(
                  tooltip: 'Close welcome',
                  onPressed: _dismissWelcome,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
                  'HELLO, HOME COOK',
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: CookTogetherTheme.herbGreen,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Meet CookTogether.',
              style: CookTogetherTheme.headingStyle(fontSize: 26),
            ),
            const SizedBox(height: 8),
            Text(
              'Your conversational AI cooking companion. Navigate recipes with your voice, set contextual timers, and let CookTogether look through your Meta glasses to answer questions about your food.',
              style: CookTogetherTheme.bodyStyle(
                fontSize: 12.5,
                color: const Color(0xFF798175),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECF3E5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 19,
                    color: Color(0xFF5F8054),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'I\'m an AI guide. I can help you through a recipe, but I can\'t guarantee food is safe or diagnose an allergy.',
                      style: CookTogetherTheme.bodyStyle(
                        fontSize: 10.5,
                        color: const Color(0xFF5F8054),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CookTogetherTheme.terracottaRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: _dismissWelcome,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Let\'s get started',
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
          ],
        ),
      ),
    );
  }

  Widget _buildToastBanner() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: _showBottomNav ? 88 : 98,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF293C28),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _toastMessage,
                  style: CookTogetherTheme.bodyStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? CookTogetherTheme.terracottaRed
        : const Color(0xFF93998E);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: CookTogetherTheme.bodyStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
