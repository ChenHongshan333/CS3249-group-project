import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'camera/phone_camera.dart';
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
import 'theme/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CookTogetherApp());
}

enum AppScreen { home, recipes, prep, cook, finish, history, profile }

class CookTogetherApp extends StatefulWidget {
  final GlassesService? glassesService;
  final AssistantService? assistantService;
  final VoiceController? voiceController;
  final PhoneCamera? phoneCamera;
  final bool showInitialWelcome;

  /// Screen to open on launch. Tests and the screenshot harness use it to
  /// jump straight to one screen.
  final AppScreen initialScreen;

  const CookTogetherApp({
    super.key,
    this.glassesService,
    this.assistantService,
    this.voiceController,
    this.phoneCamera,
    this.showInitialWelcome = true,
    this.initialScreen = AppScreen.home,
  });

  @override
  State<CookTogetherApp> createState() => _CookTogetherAppState();
}

class _CookTogetherAppState extends State<CookTogetherApp> {
  static const String _kSeenWelcomeKey = 'cooktogether.seen';
  static const String _kPrefsKey = 'cooktogether.preferences';
  static const String _kHistoryKey = 'cooktogether.history';

  late AppScreen _screen = widget.initialScreen;
  bool _welcomeOpen = false;

  /// Where Back from Get ready goes: Recipes, or Home after "Cook again".
  AppScreen _prepReturnScreen = AppScreen.recipes;
  UserPreferences _preferences = const UserPreferences();
  List<CookingHistoryItem> _history = const [];
  String _selectedRecipeId = kStarterRecipes.first.id;

  Set<String> _sessionCheckedIngredients = {};
  Set<String> _sessionAcceptedSwapIds = {};
  VoiceListeningMode _sessionListeningMode = VoiceListeningMode.handsFree;
  int _lastElapsedSeconds = 0;
  int _lastVisualChecksCount = 0;

  String _toastMessage = '';
  Timer? _toastTimer;

  late final GlassesService _glassesService;
  late final AssistantService _assistantService;
  late final VoiceController _voiceController;
  late final PhoneCamera _phoneCamera =
      widget.phoneCamera ?? SystemPhoneCamera();

  Recipe get _selectedRecipe => kStarterRecipes.firstWhere(
    (r) => r.id == _selectedRecipeId,
    orElse: () => kStarterRecipes.first,
  );

  @override
  void initState() {
    super.initState();
    _glassesService = widget.glassesService ?? MetaWearablesDatGlassesService();
    _voiceController = widget.voiceController ?? VoiceController();
    _assistantService =
        widget.assistantService ??
        HttpAssistantService(baseUrlProvider: () => _preferences.serverBaseUrl);

    // Real glasses if this app is already registered with Meta AI,
    // otherwise the Mock Device Kit.
    _glassesService.start();
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
    // Wake the backend now, so it's ready by the time the cook asks.
    _assistantService.warmUp();
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
    _assistantService.warmUp();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, updated.encode());
    } catch (_) {}
  }

  /// Get ready comes a minute or two before the first question, which is
  /// about how long a sleeping backend takes to wake.
  void _openPrep({AppScreen returnTo = AppScreen.recipes}) {
    setState(() {
      _prepReturnScreen = returnTo;
      _screen = AppScreen.prep;
    });
    _assistantService.warmUp();
  }

  /// The screen the system back gesture goes to, the same as each screen's
  /// own Back button. Null on Home, where back leaves the app, and while
  /// cooking, where the cooking screen asks first.
  AppScreen? get _backTarget => switch (_screen) {
    AppScreen.home || AppScreen.cook => null,
    AppScreen.prep => _prepReturnScreen,
    AppScreen.recipes ||
    AppScreen.finish ||
    AppScreen.history ||
    AppScreen.profile => AppScreen.home,
  };

  void _handleSystemBack() {
    if (_welcomeOpen) {
      setState(() => _welcomeOpen = false);
      return;
    }
    final target = _backTarget;
    if (target != null) setState(() => _screen = target);
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
    final formattedDate = '${now.day} ${months[now.month - 1]} ${now.year}';

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
      // On wide screens (web, tablets) the phone-width column sits on a
      // white page; on phones the column fills the screen.
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: CookTogetherTheme.maxContentWidth,
            ),
            child: SizedBox.expand(
              // Material, not ColoredBox, so ink ripples stay visible.
              child: Material(
                color: CookTogetherTheme.background,
                child: SafeArea(
                  bottom: false,
                  // Builder gives the overlays a context below MaterialApp,
                  // so they pick up the app theme.
                  child: PopScope(
                    canPop: _screen == AppScreen.home && !_welcomeOpen,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) _handleSystemBack();
                    },
                    child: Builder(
                      builder: (context) => Stack(
                        children: [
                          Column(
                            children: [
                              Expanded(child: _buildCurrentScreen()),
                              if (_showBottomNav) _buildBottomNav(),
                            ],
                          ),
                          if (_welcomeOpen) _buildWelcomeModal(context),
                          if (_toastMessage.isNotEmpty)
                            _buildToastBanner(context),
                        ],
                      ),
                    ),
                  ),
                ),
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
          onCookAgain: (recipeId) {
            _selectedRecipeId = recipeId;
            _openPrep(returnTo: AppScreen.home);
          },
        );

      case AppScreen.recipes:
        return RecipesScreen(
          recipes: kStarterRecipes,
          selectedRecipeId: _selectedRecipeId,
          onSelectRecipe: (id) => setState(() => _selectedRecipeId = id),
          onContinueToPrep: _openPrep,
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
          onStartCookingSession:
              ({
                required Set<String> checkedIngredients,
                required VoiceListeningMode listeningMode,
                required Set<String> acceptedSwapIds,
              }) {
                setState(() {
                  _sessionCheckedIngredients = checkedIngredients;
                  _sessionAcceptedSwapIds = acceptedSwapIds;
                  _sessionListeningMode = listeningMode;
                  _screen = AppScreen.cook;
                });
              },
          onBack: () => setState(() => _screen = _prepReturnScreen),
          onShowToast: _showToast,
        );

      case AppScreen.cook:
        return CookingScreen(
          recipe: _selectedRecipe,
          preferences: _preferences,
          glassesService: _glassesService,
          assistantService: _assistantService,
          voiceController: _voiceController,
          phoneCamera: _phoneCamera,
          initialCheckedIngredients: _sessionCheckedIngredients,
          initialListeningMode: _sessionListeningMode,
          acceptedSwapIds: _sessionAcceptedSwapIds,
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
    const tabs = [
      AppScreen.home,
      AppScreen.recipes,
      AppScreen.history,
      AppScreen.profile,
    ];
    return NavigationBar(
      selectedIndex: tabs.indexOf(_screen).clamp(0, tabs.length - 1),
      onDestinationSelected: (i) => setState(() => _screen = tabs[i]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.restaurant_menu_rounded),
          label: 'Recipes',
        ),
        NavigationDestination(
          icon: Icon(Icons.history_rounded),
          label: 'History',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ],
    );
  }

  Widget _buildWelcomeModal(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: const Color(0x8A263023),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Material(
        color: CookTogetherTheme.surface,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '👋',
                style: TextStyle(
                  fontSize: 40,
                  fontFamilyFallback: ['Noto Color Emoji'],
                ),
              ),
              const SizedBox(height: 12),
              Text('Meet CookTogether', style: textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'I\'ll talk you through a recipe, one step at a time. '
                'Say "next step" or "check this" whenever you\'re ready.',
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'I\'m an AI guide. I can\'t tell you if food is safe to eat '
                'or free of allergens.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Let\'s cook', onPressed: _dismissWelcome),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToastBanner(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: _showBottomNav ? 84 : 100,
      child: Material(
        color: CookTogetherTheme.ink,
        elevation: 6,
        borderRadius: BorderRadius.circular(CookTogetherTheme.radiusControl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            _toastMessage,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
