import AVFAudio
import AudioToolbox
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var keepHeadsetMic = false
  private var routeObserver: NSObjectProtocol?
  private var audioRouteChannel: FlutterMethodChannel?

  // Native 16 kHz mono PCM Voice Activity Detection (VAD) state for Whisper.
  private var vadEngine: AVAudioEngine?
  private let vadQueue = DispatchQueue(label: "cooktogether.vad.queue", qos: .userInitiated)
  private var vadListening = false
  private var vadSilenceDurationMs = 850
  private var vadMaxUtteranceSamples = 16000 * 12
  private var vadPreRollMaxSamples = 5600 // 350 ms at 16 kHz
  private var vadFixedFloor: Float = 0.012
  private var vadNoiseMultiplier: Float = 2.2
  private var vadPendingSamples: [Int16] = []
  private var vadPreRollSamples: [Int16] = []
  private var vadSpeechSamples: [Int16] = []
  private var vadInSpeech = false
  private var vadOnsetFrames = 0
  private var vadActiveSpeechFrames = 0
  private var vadSilenceFrames = 0
  private var vadPeakRms: Float = 0.0
  private var vadNoiseFloor: Float = 0.006

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    if let frameworksPath = Bundle.main.privateFrameworksPath {
      _ = dlopen("\(frameworksPath)/whisper_kit.framework/whisper_kit", RTLD_LAZY | RTLD_GLOBAL)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CookTogetherAudioRoute")
    else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "cooktogether/audio_route",
      binaryMessenger: registrar.messenger()
    )
    self.audioRouteChannel = channel
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
        self.stopVadListening(flush: false)
        self.clearAudioRoute()
        result(nil)
      case "setVadThresholds":
        let args = call.arguments as? [String: Any]
        let floor = args?["fixedFloor"] as? Double
        let mult = args?["noiseMultiplier"] as? Double
        self.vadQueue.sync {
          if let f = floor, f > 0.0 {
            self.vadFixedFloor = Float(f)
          }
          if let m = mult, m > 0.0 {
            self.vadNoiseMultiplier = Float(m)
          }
        }
        result(nil)
      case "startVadListening":
        let args = call.arguments as? [String: Any]
        let silenceMs = args?["silenceDurationMs"] as? Int ?? 850
        let maxMs = args?["maxUtteranceMs"] as? Int ?? 12000
        let preRollMs = args?["preRollMs"] as? Int ?? 350
        let floor = args?["fixedFloor"] as? Double
        let mult = args?["noiseMultiplier"] as? Double
        self.startVadListening(
          silenceDurationMs: silenceMs,
          maxUtteranceMs: maxMs,
          preRollMs: preRollMs,
          fixedFloor: floor.map { Float($0) },
          noiseMultiplier: mult.map { Float($0) },
          result: result
        )
      case "stopVadListening":
        let args = call.arguments as? [String: Any]
        let flush = args?["flush"] as? Bool ?? false
        result(self.stopVadListening(flush: flush))
      case "getWhisperModelDir":
        let dir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first
          ?? NSTemporaryDirectory()
        result(dir)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Routes audio input and output through a connected Bluetooth headset (such
  /// as Ray-Ban Meta glasses) using HFP so SpeechToText and Whisper VAD record
  /// from the glasses' microphone instead of the iPhone's built-in mic.
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

  // MARK: - 16 kHz Mono PCM Ring-Buffer + VAD Recorder for Whisper

  private func startVadListening(
    silenceDurationMs: Int,
    maxUtteranceMs: Int,
    preRollMs: Int,
    fixedFloor: Float? = nil,
    noiseMultiplier: Float? = nil,
    result: @escaping FlutterResult
  ) {
    let session = AVAudioSession.sharedInstance()
    switch session.recordPermission {
    case .granted:
      let ok = startVadEngine(
        silenceDurationMs: silenceDurationMs,
        maxUtteranceMs: maxUtteranceMs,
        preRollMs: preRollMs,
        fixedFloor: fixedFloor,
        noiseMultiplier: noiseMultiplier
      )
      result(ok)
    case .undetermined:
      session.requestRecordPermission { [weak self] granted in
        DispatchQueue.main.async {
          guard let self = self, granted else {
            result(false)
            return
          }
          let ok = self.startVadEngine(
            silenceDurationMs: silenceDurationMs,
            maxUtteranceMs: maxUtteranceMs,
            preRollMs: preRollMs,
            fixedFloor: fixedFloor,
            noiseMultiplier: noiseMultiplier
          )
          result(ok)
        }
      }
    case .denied:
      result(false)
    @unknown default:
      result(false)
    }
  }

  private func startVadEngine(
    silenceDurationMs: Int,
    maxUtteranceMs: Int,
    preRollMs: Int,
    fixedFloor: Float? = nil,
    noiseMultiplier: Float? = nil
  ) -> Bool {
    if let existing = vadEngine, existing.isRunning {
      vadQueue.sync {
        self.vadSilenceDurationMs = max(400, silenceDurationMs)
        self.vadMaxUtteranceSamples = max(16000 * 3, (maxUtteranceMs * 16))
        self.vadPreRollMaxSamples = max(3200, (preRollMs * 16))
        if let f = fixedFloor, f > 0.0 { self.vadFixedFloor = f }
        if let m = noiseMultiplier, m > 0.0 { self.vadNoiseMultiplier = m }
      }
      vadListening = true
      return true
    }

    vadQueue.sync {
      self.vadSilenceDurationMs = max(400, silenceDurationMs)
      self.vadMaxUtteranceSamples = max(16000 * 3, (maxUtteranceMs * 16))
      self.vadPreRollMaxSamples = max(3200, (preRollMs * 16))
      if let f = fixedFloor, f > 0.0 { self.vadFixedFloor = f }
      if let m = noiseMultiplier, m > 0.0 { self.vadNoiseMultiplier = m }
      self.resetVadStateLocked(keepPreRoll: true)
    }

    stopVadEngineOnly()

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers]
      )
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      if keepHeadsetMic, let btInput = bluetoothInput(in: session) {
        try? session.setPreferredInput(btInput)
      }

      let engine = AVAudioEngine()
      let inputNode = engine.inputNode
      let inputFormat = inputNode.outputFormat(forBus: 0)
      guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
        return false
      }

      guard
        let targetFormat = AVAudioFormat(
          commonFormat: .pcmFormatInt16,
          sampleRate: 16000,
          channels: 1,
          interleaved: true
        ),
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
      else {
        return false
      }

      let ratio = 16000.0 / inputFormat.sampleRate
      inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
        [weak self] buffer, _ in
        guard let self = self, self.vadListening else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard
          let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
          )
        else {
          return
        }

        var error: NSError?
        var provided = false
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
          if provided {
            outStatus.pointee = .noDataNow
            return nil
          }
          provided = true
          outStatus.pointee = .haveData
          return buffer
        }

        guard status != .error,
          let channelData = convertedBuffer.int16ChannelData
        else {
          return
        }
        let frameCount = Int(convertedBuffer.frameLength)
        guard frameCount > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        self.vadQueue.async {
          self.processVadSamplesLocked(samples)
        }
      }

      engine.prepare()
      try engine.start()
      vadEngine = engine
      vadListening = true
      return true
    } catch {
      stopVadEngineOnly()
      return false
    }
  }

  private func stopVadEngineOnly() {
    vadListening = false
    if let engine = vadEngine {
      if engine.isRunning {
        engine.stop()
      }
      engine.inputNode.removeTap(onBus: 0)
      vadEngine = nil
    }
  }

  private func stopVadListening(flush: Bool) -> String? {
    stopVadEngineOnly()
    var flushedPath: String?
    vadQueue.sync {
      if flush && self.vadInSpeech && self.vadActiveSpeechFrames >= 5 {
        flushedPath = self.writeWavFileLocked(samples: self.vadSpeechSamples)
      }
      self.resetVadStateLocked(keepPreRoll: false)
    }
    return flushedPath
  }

  private func resetVadStateLocked(keepPreRoll: Bool) {
    vadPendingSamples.removeAll(keepingCapacity: true)
    if !keepPreRoll {
      vadPreRollSamples.removeAll(keepingCapacity: true)
    }
    vadSpeechSamples.removeAll(keepingCapacity: true)
    vadInSpeech = false
    vadOnsetFrames = 0
    vadActiveSpeechFrames = 0
    vadSilenceFrames = 0
    vadPeakRms = 0.0
  }

  private func processVadSamplesLocked(_ samples: [Int16]) {
    guard vadListening else { return }
    vadPendingSamples.append(contentsOf: samples)

    let frameSize = 320 // 20 ms at 16,000 Hz
    while vadPendingSamples.count >= frameSize {
      let frame = Array(vadPendingSamples[0..<frameSize])
      vadPendingSamples.removeFirst(frameSize)

      var sumSq: Float = 0.0
      for s in frame {
        let normalized = Float(s) / 32768.0
        sumSq += normalized * normalized
      }
      let rms = sqrt(sumSq / Float(frameSize))

      let startThreshold = max(vadFixedFloor, vadNoiseFloor * vadNoiseMultiplier)
      let continueFloor = max(Float(0.003), vadFixedFloor * (0.008 / 0.012))
      let continueMult = max(Float(1.1), vadNoiseMultiplier * (1.5 / 2.2))
      let continueThreshold = max(continueFloor, vadNoiseFloor * continueMult)

      if !vadInSpeech {
        vadPreRollSamples.append(contentsOf: frame)
        if vadPreRollSamples.count > vadPreRollMaxSamples {
          vadPreRollSamples.removeFirst(vadPreRollSamples.count - vadPreRollMaxSamples)
        }

        if rms >= startThreshold {
          vadOnsetFrames += 1
          if vadOnsetFrames >= 3 {
            vadInSpeech = true
            vadSpeechSamples.removeAll(keepingCapacity: true)
            vadSpeechSamples.append(contentsOf: vadPreRollSamples)
            vadPreRollSamples.removeAll(keepingCapacity: true)
            vadActiveSpeechFrames = vadOnsetFrames
            vadSilenceFrames = 0
            vadPeakRms = rms
            vadOnsetFrames = 0
            DispatchQueue.main.async { [weak self] in
              self?.audioRouteChannel?.invokeMethod("onVadSpeechStart", arguments: nil)
            }
          }
        } else {
          vadOnsetFrames = 0
          vadNoiseFloor = min(0.030, max(0.003, 0.98 * vadNoiseFloor + 0.02 * rms))
        }
      } else {
        vadSpeechSamples.append(contentsOf: frame)
        if rms > vadPeakRms {
          vadPeakRms = rms
        }
        if rms >= continueThreshold {
          vadActiveSpeechFrames += 1
          vadSilenceFrames = 0
        } else {
          vadSilenceFrames += 1
        }

        let silenceMs = vadSilenceFrames * 20
        if silenceMs >= vadSilenceDurationMs || vadSpeechSamples.count >= vadMaxUtteranceSamples {
          let minPeak = max(Float(0.004), vadFixedFloor * (0.013 / 0.012))
          let isValidSpeech = vadActiveSpeechFrames >= 4 && vadPeakRms >= minPeak
          let captured = vadSpeechSamples
          resetVadStateLocked(keepPreRoll: false)
          if isValidSpeech, let wavPath = writeWavFileLocked(samples: captured) {
            DispatchQueue.main.async { [weak self] in
              self?.audioRouteChannel?.invokeMethod(
                "onVadUtterance",
                arguments: ["path": wavPath]
              )
            }
          }
        }
      }
    }
  }

  /// Writes 16 kHz mono 16-bit PCM samples to a temporary `.wav` file with peak
  /// normalization and minimum-length padding (`1.25 s`) for `whisper.cpp`.
  private func writeWavFileLocked(samples: [Int16]) -> String? {
    guard !samples.isEmpty else { return nil }

    var maxAbs: Int16 = 0
    for s in samples {
      let a = s == Int16.min ? Int16.max : abs(s)
      if a > maxAbs { maxAbs = a }
    }
    let gain: Float = maxAbs > 200 ? min(8.0, 27850.0 / Float(maxAbs)) : 1.0

    let minSamples = 24000 // 1.5 s at 16 kHz so whisper.cpp always has >= 1.5 s
    let totalSamples = max(samples.count, minSamples)
    var normalized = [Int16](repeating: 0, count: totalSamples)
    for i in 0..<samples.count {
      let scaled = Float(samples[i]) * gain
      let clamped = max(-32767.0, min(32767.0, scaled))
      normalized[i] = Int16(clamped)
    }

    let dataByteCount = UInt32(totalSamples * 2)
    let riffChunkSize = UInt32(36) + dataByteCount
    let sampleRate: UInt32 = 16000
    let byteRate: UInt32 = 32000
    let blockAlign: UInt16 = 2
    let bitsPerSample: UInt16 = 16
    let fmtChunkSize: UInt32 = 16
    let audioFormat: UInt16 = 1
    let numChannels: UInt16 = 1

    var header = Data(capacity: 44 + Int(dataByteCount))
    header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
    withUnsafeBytes(of: riffChunkSize.littleEndian) { header.append(contentsOf: $0) }
    header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
    header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
    withUnsafeBytes(of: fmtChunkSize.littleEndian) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: audioFormat.littleEndian) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: numChannels.littleEndian) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: sampleRate.littleEndian) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: byteRate.littleEndian) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: blockAlign.littleEndian) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: bitsPerSample.littleEndian) { header.append(contentsOf: $0) }
    header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
    withUnsafeBytes(of: dataByteCount.littleEndian) { header.append(contentsOf: $0) }

    normalized.withUnsafeBufferPointer { bufferPointer in
      header.append(UnsafeBufferPointer(
        start: UnsafeRawPointer(bufferPointer.baseAddress!)
          .assumingMemoryBound(to: UInt8.self),
        count: Int(dataByteCount)
      ))
    }

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ct_vad_\(UUID().uuidString).wav")
    do {
      try header.write(to: url, options: .atomic)
      return url.path
    } catch {
      return nil
    }
  }
}
