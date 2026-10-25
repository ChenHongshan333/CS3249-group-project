import AVFAudio
import AudioToolbox
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var keepHeadsetMic = false
  private var routeObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CookTogetherAudioRoute")
    else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "cooktogether/audio_route",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "playShutter":
        AudioServicesPlaySystemSound(1108)
        result(nil)
      case "useBluetoothMic":
        result(self.useBluetoothMic())
      case "clear":
        self.clearAudioRoute()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Routes audio input and output through a connected Bluetooth headset (such
  /// as Ray-Ban Meta glasses) using HFP so SpeechToText records from the
  /// glasses' microphone instead of the iPhone's built-in mic.
  private func useBluetoothMic() -> String? {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers]
      )
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      guard let btInput = bluetoothInput(in: session) else {
        return nil
      }
      try session.setPreferredInput(btInput)
      startKeepingHeadsetMic()
      return btInput.portName
    } catch {
      return nil
    }
  }

  private func bluetoothInput(in session: AVAudioSession) -> AVAudioSessionPortDescription? {
    let inputs = session.availableInputs ?? []
    return inputs.first {
      $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
    }
  }

  private func startKeepingHeadsetMic() {
    keepHeadsetMic = true
    guard routeObserver == nil else { return }
    routeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] _ in
      guard let self = self, self.keepHeadsetMic else { return }
      let session = AVAudioSession.sharedInstance()
      let currentInput = session.currentRoute.inputs.first
      if currentInput?.portType != .bluetoothHFP && currentInput?.portType != .bluetoothLE {
        if let btInput = self.bluetoothInput(in: session) {
          try? session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers]
          )
          try? session.setPreferredInput(btInput)
        }
      }
    }
  }

  private func clearAudioRoute() {
    keepHeadsetMic = false
    if let observer = routeObserver {
      NotificationCenter.default.removeObserver(observer)
      routeObserver = nil
    }
    let session = AVAudioSession.sharedInstance()
    try? session.setPreferredInput(nil)
  }
}
