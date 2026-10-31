import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'camera/phone_camera.dart';
import 'glasses/glasses_service.dart';
import 'models/conversation.dart';
import 'models/recipe.dart';
import 'models/user_preferences.dart';
import 'screens/cooking_screen.dart';
import 'screens/finish_screen.dart';
import 'screens/guide_overlay.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/phone_recipe_screen.dart';
import 'screens/prep_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/recipes_screen.dart';
import 'services/assistant_service.dart';
import 'services/cue_sounds.dart';
import 'services/tflite_intent_classifier.dart';
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
  phoneRecipe,
  cook,
  finish,
  history,
  profile,
}

class CookTogetherApp extends StatefulWidget {
  final GlassesService? glassesService;
  final AssistantService? assistantService;
  final VoiceController? voiceController;
  final PhoneCamera? phoneCamera;
  final CueSounds? cueSounds;
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
    this.cueSounds,
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

  /// Each dish photo is stored under its own key (this prefix plus the
  /// history item's id), so the history list stays small.
  static const String _kPhotoKeyPrefix = 'cooktogether.photo.';

  late AppScreen _screen = widget.initialScreen;
  bool _welcomeOpen = false;

  /// Where Back from Get ready goes: Recipes, or Home after "Cook again".
  AppScreen _prepReturnScreen = AppScreen.recipes;
  UserPreferences _preferences = const UserPreferences();
  List<CookingHistoryItem> _history = const [];

  /// Photos of finished dishes, by history item id.
  Map<String, Uint8List> _dishPhotos = const {};
  String _selectedRecipeId = kStarterRecipes.first.id;

  /// The recipe of the cooking session, kept while it's paused and left so
  /// it can be resumed from Home. Null when no session is open.
  /// Tests and the screenshot harness can open straight on cooking.
  late Recipe? _sessionRecipe = widget.initialScreen == AppScreen.cook
      ? _selectedRecipe
      : null;

  /// A new key for each session, so starting one never reuses the last.
  Key _sessionKey = UniqueKey();

  Set<String> _sessionCheckedIngredients = {};
  Map<String, MissingOption> _sessionMissingChoices = {};
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
  late final CueSounds _cueSounds = widget.cueSounds ?? AudioCueSounds();

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
    _voiceController.prepareWhisperOnAppStartup();
    unawaited(TfliteIntentClassifier.instance.initialize());
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
      final savedPhotos = <String, Uint8List>{};
      for (final item in savedHistory) {
        final raw = prefs.getString('$_kPhotoKeyPrefix${item.id}');
        if (raw == null) continue;
        try {
          savedPhotos[item.id] = base64Decode(raw);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _welcomeOpen = widget.showInitialWelcome && !seen;
        _preferences = savedPrefs;
        _history = savedHistory;
        _dishPhotos = savedPhotos;
      });
      _voiceController.setVadTuning(
        fixedFloor: savedPrefs.vadFixedFloor,
        noiseMultiplier: savedPrefs.vadNoiseMultiplier,
      );
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
    unawaited(_voiceController.configureVoice(
      voiceName: updated.ttsVoiceName,
      voiceLocale: updated.ttsVoiceLocale,
      pitch: updated.ttsPitch,
      rate: updated.ttsRate,
    ));
    _showToast('Preferences saved');
    _assistantService.warmUp();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, updated.encode());
    } catch (_) {}
  }

  /// Updates user preferences in state and storage without navigating away,
  /// used for in-session tuning during cooking.
  Future<void> _updatePreferences(UserPreferences updated) async {
    setState(() => _preferences = updated);
    _voiceController.setVadTuning(
      fixedFloor: updated.vadFixedFloor,
      noiseMultiplier: updated.vadNoiseMultiplier,
    );
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
    _voiceController.preloadWhisperModel();
  }

  /// The screen the system back gesture goes to, the same as each screen's
  /// own Back button. Null on Home, where back leaves the app, and while
  /// cooking, where the cooking screen asks first.
  AppScreen? get _backTarget => switch (_screen) {
    AppScreen.home || AppScreen.cook => null,
    AppScreen.prep => _prepReturnScreen,
    AppScreen.phoneRecipe => AppScreen.recipes,
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

    final recipe = _sessionRecipe ?? _selectedRecipe;
    final item = CookingHistoryItem(
      id: 'hist-${now.millisecondsSinceEpoch}',
      recipeId: recipe.id,
      recipeName: recipe.name,
      recipeIcon: recipe.icon,
      date: formattedDate,
      durationSeconds: elapsedSeconds,
      stepsCompleted: stepsCompleted,
      visualChecksCount: visualChecksCount,
    );

    final nextHistory = [item, ..._history];
    setState(() {
      _selectedRecipeId = recipe.id;
      _sessionRecipe = null;
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

  /// Saves the photo of the dish just finished with its history item.
  Future<void> _saveDishPhoto(Uint8List photo) async {
    if (_history.isEmpty) return;
    final id = _history.first.id;
    setState(() => _dishPhotos = {..._dishPhotos, id: photo});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_kPhotoKeyPrefix$id', base64Encode(photo));
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
                              Expanded(child: _buildScreens()),
                              if (_showBottomNav) _buildBottomNav(),
                            ],
                          ),
                          if (_welcomeOpen) GuideOverlay(onDone: _dismissWelcome),
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

  /// The current screen, with the cooking session underneath it while it's
  /// paused and left, so it keeps its chat, step and timers.
  Widget _buildScreens() {
    final session = _sessionRecipe;
    final cooking = _screen == AppScreen.cook;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!cooking) _buildCurrentScreen(),
        if (session != null)
          Offstage(
            offstage: !cooking,
            child: TickerMode(
              enabled: cooking,
              child: _buildCookingScreen(session, visible: cooking),
            ),
          ),
      ],
    );
  }

  Widget _buildCookingScreen(Recipe recipe, {required bool visible}) {
    return CookingScreen(
      key: _sessionKey,
      isVisible: visible,
      recipe: recipe,
      preferences: _preferences,
      onSavePreferences: _updatePreferences,
      glassesService: _glassesService,
      assistantService: _assistantService,
      voiceController: _voiceController,
      phoneCamera: _phoneCamera,
      cueSounds: _cueSounds,
      initialCheckedIngredients: _sessionCheckedIngredients,
      missingChoices: _sessionMissingChoices,
      initialListeningMode: _sessionListeningMode,
      acceptedSwapIds: _sessionAcceptedSwapIds,
      onFinishCooking: _recordCompletedSession,
      onExitToHome: () => setState(() {
        _sessionRecipe = null;
        _screen = AppScreen.home;
      }),
      onPauseAndLeave: () => setState(() => _screen = AppScreen.home),
      onShowToast: _showToast,
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
          showSimulatedGlasses: _preferences.simulatedGlassesPhotos,
          onCookAgain: (recipeId) {
            _selectedRecipeId = recipeId;
            _openPrep(returnTo: AppScreen.home);
          },
          pausedRecipe: _sessionRecipe,
          onResumeSession: () => setState(() => _screen = AppScreen.cook),
        );

      case AppScreen.recipes:
        return RecipesScreen(
          recipes: kStarterRecipes,
          selectedRecipeId: _selectedRecipeId,
          onSelectRecipe: (id) => setState(() => _selectedRecipeId = id),
          // In the user study's phone condition a recipe opens as a plain
          // list instead of Get ready and cooking.
          onContinueToPrep: _preferences.phoneRecipeMode
              ? () => setState(() => _screen = AppScreen.phoneRecipe)
              : _openPrep,
          onBack: () => setState(() => _screen = AppScreen.home),
          onShowToast: _showToast,
        );

      case AppScreen.prep:
        return PrepScreen(
          recipe: _selectedRecipe,
          glassesService: _glassesService,
          phoneCamera: _phoneCamera,
          simulatedGlassesPhotos: _preferences.simulatedGlassesPhotos,
          initialListeningMode: _preferences.handsFreeListening
              ? VoiceListeningMode.handsFree
              : VoiceListeningMode.tapToSpeak,
          onStartCookingSession:
              ({
                required Set<String> checkedIngredients,
                required Map<String, MissingOption> missingChoices,
                required VoiceListeningMode listeningMode,
                required Set<String> acceptedSwapIds,
              }) {
                if (_sessionRecipe != null) {
                  _showToast('Your paused session was ended');
                }
                setState(() {
                  _sessionRecipe = _selectedRecipe;
                  _sessionKey = UniqueKey();
                  _sessionCheckedIngredients = checkedIngredients;
                  _sessionMissingChoices = missingChoices;
                  _sessionAcceptedSwapIds = acceptedSwapIds;
                  _sessionListeningMode = listeningMode;
                  _screen = AppScreen.cook;
                });
              },
          onBack: () => setState(() => _screen = _prepReturnScreen),
          onShowToast: _showToast,
        );

      case AppScreen.phoneRecipe:
        return PhoneRecipeScreen(
          recipe: _selectedRecipe,
          assistantService: _assistantService,
          onBack: () => setState(() => _screen = AppScreen.recipes),
          onFinish: (seconds) {
            setState(() => _screen = AppScreen.home);
            _showToast('Finished in ${seconds ~/ 60} min ${seconds % 60} s');
          },
        );

      case AppScreen.cook:
        // Drawn by _buildScreens, so it survives leaving the screen.
        return const SizedBox.shrink();

      case AppScreen.finish:
        return FinishScreen(
          recipe: _selectedRecipe,
          elapsedSeconds: _lastElapsedSeconds,
          visualChecksCount: _lastVisualChecksCount,
          onBackToHome: () => setState(() => _screen = AppScreen.home),
          glassesService: _glassesService,
          phoneCamera: _phoneCamera,
          allowSimulatedGlasses: _preferences.simulatedGlassesPhotos,
          dishPhoto: _history.isEmpty ? null : _dishPhotos[_history.first.id],
          onDishPhoto: _saveDishPhoto,
          onShowToast: _showToast,
        );

      case AppScreen.history:
        return HistoryScreen(
          history: _history,
          dishPhotos: _dishPhotos,
          onChooseRecipe: () => setState(() => _screen = AppScreen.recipes),
          onBack: () => setState(() => _screen = AppScreen.home),
        );

      case AppScreen.profile:
        return ProfileScreen(
          preferences: _preferences,
          history: _history,
          onSavePreferences: _savePreferences,
          onOpenHistory: () => setState(() => _screen = AppScreen.history),
          onOpenGuide: () => setState(() => _welcomeOpen = true),
          voiceController: _voiceController,
          glassesService: _glassesService,
          onShowToast: _showToast,
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
