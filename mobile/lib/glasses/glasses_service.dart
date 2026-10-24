import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meta_wearables_dat_flutter/meta_wearables_dat_flutter.dart';

import 'upright_photo.dart';
import '../models/conversation.dart';
import '../models/recipe.dart';

/// Connection state of the Meta glasses layer in `lib/glasses/`.
enum GlassesConnectionState {
  disconnected,
  connecting,
  connectedMockKit,
  connectedHardware,
}

/// Clean interface boundary in `lib/glasses/` between the UI screens and
/// the Meta Wearables Device Access Toolkit (`meta_wearables_dat_flutter`).
abstract class GlassesService extends ChangeNotifier {
  GlassesConnectionState get connectionState;
  bool get isConnected;
  bool get isCapturing;
  bool get isStreaming;
  int? get streamTextureId;
  String get deviceName;
  String? get deviceUuid;
  int get batteryLevel;
  DonState get donState;
  HingeState get hingeState;
  MockGlassesModel get mockModel;
  String? get lastStatusNote;

  /// True when photos come from the user's own glasses, not the Mock Kit.
  bool get usingRealGlasses;

  /// Uses the real glasses if this app is already registered with Meta AI,
  /// otherwise the Mock Device Kit. Never throws.
  Future<void> start();

  /// Registers with the Meta AI app (opening it if needed), asks for camera
  /// permission, and switches to the real glasses. Sets [lastStatusNote] to
  /// a short, user-facing reason when it fails.
  Future<bool> connectRealGlasses();

  Future<void> initializeAndPairMockDevice({
    MockGlassesModel model = MockGlassesModel.rayBanMeta,
  });
  Future<void> disconnect();
  Future<void> startPreviewStream();
  Future<void> stopPreviewStream();
  Future<void> simulateTouchpadTap();

  /// Throws [GlassesCaptureException] when the real glasses can't take a
  /// photo, so the caller never sends a blank image to the assistant.
  Future<VisionCapture> captureFrame({
    required Recipe recipe,
    required int stepIndex,
    String? userPrompt,
  });
}

/// Whether to show the glasses as connected: the user's own glasses when
/// they are connected, or the Mock Device Kit only when Profile → Developer
/// allows simulated glasses, so a real user never sees them.
bool glassesReady(GlassesService glasses, {required bool allowSimulated}) =>
    glasses.usingRealGlasses
    ? glasses.connectionState == GlassesConnectionState.connectedHardware
    : allowSimulated && glasses.isConnected;

/// A photo could not be taken. [message] is safe to show or speak.
class GlassesCaptureException implements Exception {
  final String message;
  const GlassesCaptureException(this.message);

  @override
  String toString() => message;
}

/// Implementation of [GlassesService] backed by `meta_wearables_dat_flutter`.
///
/// Two modes:
/// - Real glasses: registered with the Meta AI app in Developer Mode. The
///   camera stream starts only for a photo and stops right after, so the
///   glasses' capture light is on only while a photo is being taken.
/// - Mock Device Kit: simulated glasses for the web build, tests, and
///   phones without glasses.
class MetaWearablesDatGlassesService extends GlassesService {
  GlassesConnectionState _connectionState =
      GlassesConnectionState.connectedMockKit;
  bool _isCapturing = false;
  bool _isStreaming = false;
  int? _streamTextureId;
  String _deviceName = 'Ray-Ban Meta (Mock Kit)';
  String? _deviceUuid = 'mock-rayban-meta-01';
  int _batteryLevel = 92;
  DonState _donState = DonState.donned;
  HingeState _hingeState = HingeState.open;
  MockGlassesModel _mockModel = MockGlassesModel.rayBanMeta;
  String? _lastStatusNote = 'Mock Device Kit active · Donned & Ready';
  bool _usingRealGlasses = false;
  StreamSubscription<DeviceInfo?>? _deviceSub;
  StreamSubscription<RegistrationRequest>? _requestSub;

  // Minimal valid 1x1 JPEG bytes used when the native platform channel is
  // running in a headless test VM or before a camera feed file is seeded.
  static final Uint8List _fallbackJpegBytes = base64Decode(
    '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=',
  );

  @override
  GlassesConnectionState get connectionState => _connectionState;

  @override
  bool get isConnected =>
      _connectionState == GlassesConnectionState.connectedMockKit ||
      _connectionState == GlassesConnectionState.connectedHardware;

  @override
  bool get isCapturing => _isCapturing;

  @override
  bool get isStreaming => _isStreaming;

  @override
  int? get streamTextureId => _streamTextureId;

  @override
  String get deviceName => _deviceName;

  @override
  String? get deviceUuid => _deviceUuid;

  @override
  int get batteryLevel => _batteryLevel;

  @override
  DonState get donState => _donState;

  @override
  HingeState get hingeState => _hingeState;

  @override
  MockGlassesModel get mockModel => _mockModel;

  @override
  String? get lastStatusNote => _lastStatusNote;

  @override
  bool get usingRealGlasses => _usingRealGlasses;

  @override
  Future<void> start() async {
    try {
      // Throws straight away on web and in tests, where there is no native
      // plugin, so nothing below runs there.
      final state = await MetaWearablesDat.getRegistrationState();
      // The user can also start the connection from the Meta AI app.
      _requestSub ??= MetaWearablesDat.registrationRequestStream().listen((
        request,
      ) async {
        try {
          await request.continueRegistration();
        } catch (_) {}
      }, onError: (_) {});
      if (state == RegistrationState.registered && await connectRealGlasses()) {
        return;
      }
    } catch (_) {
      // Web, tests, or a phone without the Meta AI app.
    }
    await initializeAndPairMockDevice(model: _mockModel);
  }

  @override
  Future<bool> connectRealGlasses() async {
    _connectionState = GlassesConnectionState.connecting;
    _lastStatusNote = 'Connecting to your glasses…';
    notifyListeners();

    try {
      if (await MetaWearablesDat.isMockDeviceEnabled()) {
        await MetaWearablesDat.disableMockDevice();
      }
      if (!await MetaWearablesDat.requestAndroidPermissions()) {
        return _fail(
          'Allow Bluetooth for CookTogether in your phone settings.',
        );
      }

      if (await MetaWearablesDat.getRegistrationState() !=
          RegistrationState.registered) {
        // Opens the Meta AI app; the user approves, and Meta AI opens this
        // app again through the cookalong:// link.
        await MetaWearablesDat.startRegistration();
        await MetaWearablesDat.registrationStateStream()
            .firstWhere((s) => s == RegistrationState.registered)
            .timeout(const Duration(minutes: 2));
      }

      final permission = await MetaWearablesDat.requestPermission(
        Permission.camera,
      );
      if (!permission.isGranted) {
        return _fail(
          'Allow camera access for CookTogether in the Meta AI app.',
        );
      }

      final device = await MetaWearablesDat.activeDeviceStream()
          .firstWhere((d) => d != null)
          .timeout(const Duration(seconds: 15));
      _usingRealGlasses = true;
      _applyDevice(device!);
      await _deviceSub?.cancel();
      _deviceSub = MetaWearablesDat.activeDeviceStream().listen((d) {
        if (d == null) {
          _connectionState = GlassesConnectionState.disconnected;
          _lastStatusNote =
              'Glasses disconnected. Check they are on and nearby.';
          notifyListeners();
        } else {
          _applyDevice(d);
        }
      }, onError: (_) {});
      return true;
    } on TimeoutException {
      return _fail(
        'No glasses found. Open the Meta AI app, check your glasses are '
        'connected, then try again.',
      );
    } on RegistrationError catch (e) {
      return _fail(switch (e.reason) {
        RegistrationErrorCase.metaAINotInstalled =>
          'Install the Meta AI app first.',
        RegistrationErrorCase.configurationInvalid =>
          'This build is not set up for Meta glasses. See mobile/README.md.',
        _ => 'Meta AI could not connect: ${e.message}',
      });
    } on DatError catch (e) {
      return _fail('Glasses error: ${e.message}');
    } catch (_) {
      // MissingPluginException on web and in tests.
      return _fail('Real glasses only work in the Android or iPhone app.');
    }
  }

  bool _fail(String reason) {
    _usingRealGlasses = false;
    _connectionState = GlassesConnectionState.disconnected;
    _lastStatusNote = reason;
    notifyListeners();
    return false;
  }

  void _applyDevice(DeviceInfo device) {
    _deviceUuid = device.uuid;
    _deviceName = device.name.isNotEmpty ? device.name : 'Your glasses';
    _batteryLevel = device.batteryLevel ?? _batteryLevel;
    _donState = device.donState;
    _hingeState = device.hingeState;
    _connectionState = device.isConnected
        ? GlassesConnectionState.connectedHardware
        : GlassesConnectionState.connecting;
    _lastStatusNote = device.isConnected
        ? 'Connected to $_deviceName'
        : 'Waiting for $_deviceName to connect…';
    notifyListeners();
  }

  String _modelDisplayName(MockGlassesModel model) {
    return switch (model) {
      MockGlassesModel.rayBanMeta => 'Ray-Ban Meta (Mock Kit)',
      MockGlassesModel.rayBanMetaOptics => 'Ray-Ban Meta Optics (Mock Kit)',
      MockGlassesModel.oakleyMetaHSTN => 'Oakley Meta HSTN (Mock Kit)',
      MockGlassesModel.oakleyMetaVanguard => 'Oakley Meta Vanguard (Mock Kit)',
      MockGlassesModel.metaGlasses => 'Meta Glasses (Mock Kit)',
      MockGlassesModel.metaRayBanDisplay => 'Meta Ray-Ban Display (Mock Kit)',
    };
  }

  @override
  Future<void> initializeAndPairMockDevice({
    MockGlassesModel model = MockGlassesModel.rayBanMeta,
  }) async {
    await _deviceSub?.cancel();
    _deviceSub = null;
    _usingRealGlasses = false;
    _mockModel = model;
    _deviceName = _modelDisplayName(model);
    _deviceUuid ??= 'mock-dat-${model.name}';
    _connectionState = GlassesConnectionState.connectedMockKit;
    _donState = DonState.donned;
    _hingeState = HingeState.open;
    _lastStatusNote = 'Paired via MetaWearablesDat Mock Device Kit · Ready';
    notifyListeners();

    try {
      await MetaWearablesDat.enableMockDevice(
        initiallyRegistered: true,
        initialPermissionsGranted: true,
      ).timeout(const Duration(milliseconds: 250));

      final DeviceInfo deviceInfo = await MetaWearablesDat.pairMockGlasses(
        model,
      ).timeout(const Duration(milliseconds: 250));
      final uuid = deviceInfo.uuid.isNotEmpty
          ? deviceInfo.uuid
          : 'mock-rayban-meta-01';

      await MetaWearablesDat.mockPowerOn(uuid);
      await MetaWearablesDat.mockUnfold(uuid);
      await MetaWearablesDat.mockDon(uuid);
      await MetaWearablesDat.setMockBatteryLevel(uuid, 92);
      await MetaWearablesDat.setMockChargingState(
        uuid,
        ChargingState.notCharging,
      );
      await MetaWearablesDat.setMockThermalLevel(uuid, ThermalLevel.none);
      await MetaWearablesDat.setMockCameraFacing(uuid, CameraFacing.back);

      _deviceUuid = uuid;
      _deviceName = deviceInfo.name.isNotEmpty
          ? '${deviceInfo.name} (Mock Kit)'
          : _modelDisplayName(model);
      _batteryLevel = deviceInfo.batteryLevel ?? 92;
      _connectionState = GlassesConnectionState.connectedMockKit;
      _lastStatusNote =
          'Paired via MetaWearablesDat Mock Device Kit · Donned & Ready';
      notifyListeners();
    } catch (_) {
      // Running in unit/widget test VM or target without native DAT bridge:
      // keep the Mock Device Kit state active for UI & test parity.
    }
  }

  @override
  Future<void> startPreviewStream() async {
    if (!isConnected) {
      await initializeAndPairMockDevice(model: _mockModel);
    }
    try {
      final textureId = await MetaWearablesDat.startStreamSession(
        deviceUUID: _deviceUuid,
        config: const StreamSessionConfig(
          frameRate: StreamFrameRate.fps24,
          quality: StreamQuality.medium,
        ),
      ).timeout(const Duration(milliseconds: 250));
      _streamTextureId = textureId >= 0 ? textureId : null;
      _isStreaming = true;
      _lastStatusNote = 'Live POV stream active via MetaWearablesDat';
    } catch (_) {
      // In simulator or test mode without a registered native texture source,
      // mark streaming active with simulated POV frames.
      _streamTextureId = null;
      _isStreaming = true;
      _lastStatusNote = 'Mock Device Kit POV stream active';
    }
    notifyListeners();
  }

  @override
  Future<void> stopPreviewStream() async {
    try {
      await MetaWearablesDat.stopStreamSession();
    } catch (_) {
      // Ignore if stream was not open on native channel.
    }
    _streamTextureId = null;
    _isStreaming = false;
    notifyListeners();
  }

  @override
  Future<void> simulateTouchpadTap() async {
    final uuid = _deviceUuid;
    if (uuid != null) {
      try {
        await MetaWearablesDat.mockTap(uuid);
        _lastStatusNote = 'Simulated temple touchpad tap on $_deviceName';
      } catch (_) {
        _lastStatusNote = 'Temple touchpad tap simulated on $_deviceName';
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _requestSub?.cancel();
    super.dispose();
  }

  @override
  Future<void> disconnect() async {
    await stopPreviewStream();
    await _deviceSub?.cancel();
    _deviceSub = null;
    final uuid = _deviceUuid;
    if (uuid != null && !_usingRealGlasses) {
      try {
        await MetaWearablesDat.mockFold(uuid);
        await MetaWearablesDat.mockPowerOff(uuid);
        await MetaWearablesDat.unpairMockDevice(uuid);
      } catch (_) {}
    }
    try {
      await MetaWearablesDat.disableMockDevice();
    } catch (_) {}
    _usingRealGlasses = false;
    _connectionState = GlassesConnectionState.disconnected;
    _deviceUuid = null;
    _donState = DonState.doffed;
    _hingeState = HingeState.closed;
    _lastStatusNote = 'Glasses disconnected';
    notifyListeners();
  }

  @override
  Future<VisionCapture> captureFrame({
    required Recipe recipe,
    required int stepIndex,
    String? userPrompt,
  }) async {
    if (_usingRealGlasses) {
      return _captureFromRealGlasses(recipe, stepIndex, userPrompt);
    }
    if (!isConnected) {
      await initializeAndPairMockDevice(model: _mockModel);
    }

    _isCapturing = true;
    _lastStatusNote = 'Capturing POV photo from $_deviceName…';
    notifyListeners();

    Uint8List photoBytes = _fallbackJpegBytes;

    try {
      if (!_isStreaming) {
        await startPreviewStream();
      }
      final PhotoResult result = await MetaWearablesDat.capturePhoto(
        format: PhotoFormat.jpeg,
      ).timeout(const Duration(milliseconds: 250));
      if (result.bytes.isNotEmpty) {
        photoBytes = result.bytes;
      }
    } catch (_) {
      // Brief pause to mimic glasses shutter & transfer latency in mock mode
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    _isCapturing = false;
    final capture = _buildCapture(recipe, stepIndex, userPrompt, photoBytes);
    notifyListeners();
    return capture;
  }

  Future<VisionCapture> _captureFromRealGlasses(
    Recipe recipe,
    int stepIndex,
    String? userPrompt,
  ) async {
    if (_connectionState != GlassesConnectionState.connectedHardware) {
      throw const GlassesCaptureException(
        'Your glasses are not connected. Check they are on and nearby.',
      );
    }
    if (_hingeState == HingeState.closed) {
      throw const GlassesCaptureException(
        'Unfold your glasses to take a photo.',
      );
    }

    try {
      return await _takeGlassesPhoto(recipe, stepIndex, userPrompt);
    } on DatError catch (e) {
      // Meta's recommended fix for a missing camera permission: ask for it
      // (Meta AI shows the prompt), then try once more.
      if (e.recoveryAction == DatRecoveryAction.grantPermission &&
          await _askForCameraPermission()) {
        try {
          return await _takeGlassesPhoto(recipe, stepIndex, userPrompt);
        } on DatError catch (retryError) {
          throw GlassesCaptureException(explainGlassesError(retryError));
        }
      }
      throw GlassesCaptureException(explainGlassesError(e));
    }
  }

  /// Starts the camera stream only for one photo, then stops it, so the
  /// glasses' capture light is on only while the photo is taken.
  Future<VisionCapture> _takeGlassesPhoto(
    Recipe recipe,
    int stepIndex,
    String? userPrompt,
  ) async {
    _isCapturing = true;
    _lastStatusNote = 'Taking a photo with $_deviceName…';
    notifyListeners();
    try {
      // Listen before starting so the "streaming" state isn't missed.
      final streaming = MetaWearablesDat.streamSessionStateStream()
          .firstWhere((s) => s == StreamSessionState.streaming)
          .timeout(const Duration(seconds: 8));
      await MetaWearablesDat.startStreamSession(
        deviceUUID: _deviceUuid,
        config: const StreamSessionConfig(
          frameRate: StreamFrameRate.fps15,
          quality: StreamQuality.high,
        ),
      );
      await streaming;
      final photo = await MetaWearablesDat.capturePhoto(
        format: PhotoFormat.jpeg,
      ).timeout(const Duration(seconds: 6));
      if (photo.bytes.isEmpty) {
        throw const GlassesCaptureException('The glasses sent an empty photo.');
      }
      final upright = await uprightGlassesPhoto(photo.bytes);
      return _buildCapture(recipe, stepIndex, userPrompt, upright);
    } on TimeoutException {
      throw const GlassesCaptureException(
        'The glasses took too long to take a photo. Try again.',
      );
    } finally {
      try {
        await MetaWearablesDat.stopStreamSession();
      } catch (_) {}
      _isCapturing = false;
      notifyListeners();
    }
  }

  Future<bool> _askForCameraPermission() async {
    try {
      final status = await MetaWearablesDat.requestPermission(
        Permission.camera,
      );
      return status.isGranted;
    } on DatError {
      return false;
    }
  }

  VisionCapture _buildCapture(
    Recipe recipe,
    int stepIndex,
    String? userPrompt,
    Uint8List photoBytes,
  ) {
    final step = recipe.steps[stepIndex.clamp(0, recipe.steps.length - 1)];
    _lastStatusNote = 'Captured POV snapshot (${step.title})';
    return VisionCapture(
      id: 'snap-${DateTime.now().millisecondsSinceEpoch}',
      recipeId: recipe.id,
      stepIndex: stepIndex,
      source: 'glasses',
      deviceName: _deviceName,
      sceneDescription: step.visionSceneDescription,
      recipeIcon: recipe.icon,
      recipeTone: recipe.tone,
      jpegBytes: photoBytes.length > 200 ? photoBytes : null,
      base64Jpeg: base64Encode(photoBytes),
      capturedAt: DateTime.now(),
      userQuestion: userPrompt,
    );
  }
}

/// A short instruction for a glasses error that a user can act on. Meta's own
/// message is only logged: it can name screens that don't exist in the
/// user's version of the Meta AI app.
String explainGlassesError(DatError error) {
  debugPrint('Glasses photo failed: $error');
  if (error is StreamError) {
    switch (error.reason) {
      case StreamErrorCase.hingesClosed:
        return 'Unfold your glasses to take a photo.';
      case StreamErrorCase.thermalHot:
        return 'Your glasses are too warm. Let them cool down, then try again.';
      case StreamErrorCase.batteryLow:
        return 'Your glasses are low on battery. Charge them, then try again.';
      default:
        break;
    }
  }
  return switch (error.recoveryAction) {
    DatRecoveryAction.grantPermission =>
      'CookTogether needs camera access on your glasses. Allow it in the '
          'Meta AI app, then try again.',
    DatRecoveryAction.openDatGlassesAppUpdate =>
      'Your glasses need an update for CookTogether. Open the Meta AI app, '
          'go to your glasses and install it, then try again.',
    DatRecoveryAction.openFirmwareUpdate =>
      'Your glasses need a software update. Update them in the Meta AI app, '
          'then try again.',
    DatRecoveryAction.updateHostApp =>
      'This version of CookTogether is too old for your glasses. Install the '
          'latest build.',
    DatRecoveryAction.checkMetaAiAndRetry =>
      'Check your glasses in the Meta AI app, then try again.',
    DatRecoveryAction.connectGlasses =>
      'Turn on, unfold and wear your glasses, then try again.',
    DatRecoveryAction.suggestUpdate ||
    DatRecoveryAction.none => "Your glasses couldn't take a photo. Try again.",
  };
}
