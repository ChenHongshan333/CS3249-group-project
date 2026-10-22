import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meta_wearables_dat_flutter/meta_wearables_dat_flutter.dart';

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

  Future<void> initializeAndPairMockDevice({
    MockGlassesModel model = MockGlassesModel.rayBanMeta,
  });
  Future<void> disconnect();
  Future<void> startPreviewStream();
  Future<void> stopPreviewStream();
  Future<void> simulateTouchpadTap();
  Future<VisionCapture> captureFrame({
    required Recipe recipe,
    required int stepIndex,
    String? userPrompt,
  });
}

/// Implementation of [GlassesService] backed by `meta_wearables_dat_flutter`
/// using the Mock Device Kit (`MetaWearablesDat.enableMockDevice`,
/// `MetaWearablesDat.pairMockGlasses`, `mockPowerOn`, `mockUnfold`, `mockDon`,
/// `startStreamSession`, and `capturePhoto`).
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
  Future<void> disconnect() async {
    await stopPreviewStream();
    final uuid = _deviceUuid;
    if (uuid != null) {
      try {
        await MetaWearablesDat.mockFold(uuid);
        await MetaWearablesDat.mockPowerOff(uuid);
        await MetaWearablesDat.unpairMockDevice(uuid);
      } catch (_) {}
    }
    try {
      await MetaWearablesDat.disableMockDevice();
    } catch (_) {}
    _connectionState = GlassesConnectionState.disconnected;
    _deviceUuid = null;
    _donState = DonState.doffed;
    _hingeState = HingeState.closed;
    _lastStatusNote = 'Mock Device Kit disconnected';
    notifyListeners();
  }

  @override
  Future<VisionCapture> captureFrame({
    required Recipe recipe,
    required int stepIndex,
    String? userPrompt,
  }) async {
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

    final step = recipe.steps[stepIndex.clamp(0, recipe.steps.length - 1)];
    _isCapturing = false;
    _lastStatusNote = 'Captured POV snapshot (${step.title})';
    notifyListeners();

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
