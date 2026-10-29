package com.cs3249.mobile

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaActionSound
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class MainActivity : FlutterFragmentActivity() {
    private val shutterSound = MediaActionSound()
    private val handler = Handler(Looper.getMainLooper())
    private var audioRouteChannel: MethodChannel? = null

    /** True while the app records through the headset's mic and keeps it. */
    private var keepHeadsetMic = false
    private var routeListener: AudioManager.OnCommunicationDeviceChangedListener? = null

    // Native 16 kHz mono PCM Voice Activity Detection (VAD) state for Whisper.
    private val vadLock = Any()
    @Volatile private var vadListening = false
    private var vadThread: Thread? = null
    private var vadSilenceDurationMs = 850
    private var vadMaxUtteranceSamples = 16000 * 12
    private var vadPreRollMaxSamples = 5600 // 350 ms at 16 kHz
    private val vadPreRollSamples = ArrayList<Short>(12000)
    private val vadSpeechSamples = ArrayList<Short>(16000 * 12)
    private var vadInSpeech = false
    private var vadOnsetFrames = 0
    private var vadActiveSpeechFrames = 0
    private var vadSilenceFrames = 0
    private var vadPeakRms = 0f
    private var vadNoiseFloor = 0.006f

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shutterSound.load(MediaActionSound.SHUTTER_CLICK)
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cooktogether/audio_route")
        audioRouteChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "playShutter" -> {
                    shutterSound.play(MediaActionSound.SHUTTER_CLICK)
                    result.success(null)
                }
                "useBluetoothMic" -> useBluetoothMic(audio, result)
                "clear" -> {
                    stopVadListening(flush = false)
                    stopKeepingHeadsetMic(audio)
                    audio.clearCommunicationDevice()
                    result.success(null)
                }
                "startVadListening" -> {
                    val args = call.arguments as? Map<*, *>
                    val silenceMs = (args?.get("silenceDurationMs") as? Number)?.toInt() ?: 850
                    val maxMs = (args?.get("maxUtteranceMs") as? Number)?.toInt() ?: 12000
                    val preRollMs = (args?.get("preRollMs") as? Number)?.toInt() ?: 350
                    result.success(startVadListening(silenceMs, maxMs, preRollMs))
                }
                "stopVadListening" -> {
                    val args = call.arguments as? Map<*, *>
                    val flush = (args?.get("flush") as? Boolean) ?: false
                    result.success(stopVadListening(flush))
                }
                "getWhisperModelDir" -> {
                    result.success(filesDir.absolutePath)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopVadListening(flush = false)
        stopKeepingHeadsetMic(getSystemService(Context.AUDIO_SERVICE) as AudioManager)
        shutterSound.release()
        super.onDestroy()
    }

    /**
     * Records speech through a Bluetooth headset's mic, such as the glasses,
     * so the user doesn't have to talk to the phone on the counter. Replies
     * with the headset's name once its audio link is up, or null when there is
     * no Bluetooth headset or the link doesn't come up within 3 seconds.
     *
     * The app calls this again before each listen and each spoken reply, so
     * it replies at once when the link is already up.
     */
    private fun useBluetoothMic(audio: AudioManager, result: MethodChannel.Result) {
        val headset = bluetoothHeadset(audio)
        if (headset == null) {
            result.success(null)
            return
        }
        if (linkUp(audio, headset)) {
            result.success(headset.productName.toString())
            return
        }
        if (!audio.setCommunicationDevice(headset)) {
            result.success(null)
            return
        }
        val deadline = System.currentTimeMillis() + 3000
        fun waitForLink() {
            when {
                linkUp(audio, headset) -> {
                    startKeepingHeadsetMic(audio)
                    result.success(headset.productName.toString())
                }
                System.currentTimeMillis() > deadline -> {
                    // Once kept, leave the request in place: the link may
                    // still come back for the next turn.
                    if (!keepHeadsetMic) audio.clearCommunicationDevice()
                    result.success(null)
                }
                else -> handler.postDelayed({ waitForLink() }, 100)
            }
        }
        waitForLink()
    }

    private fun bluetoothHeadset(audio: AudioManager): AudioDeviceInfo? =
        audio.availableCommunicationDevices
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }

    @Suppress("DEPRECATION")
    private fun linkUp(audio: AudioManager, headset: AudioDeviceInfo): Boolean =
        audio.communicationDevice?.id == headset.id && audio.isBluetoothScoOn

    /**
     * The glasses end call mode by themselves every few seconds (#40), which
     * moves recording back to the phone's mic. While the app uses their mic,
     * ask for it again as soon as that happens.
     */
    private fun startKeepingHeadsetMic(audio: AudioManager) {
        keepHeadsetMic = true
        if (routeListener != null) return
        val listener = AudioManager.OnCommunicationDeviceChangedListener { device ->
            if (device?.type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO) reopenHeadsetMic(audio)
        }
        audio.addOnCommunicationDeviceChangedListener(mainExecutor, listener)
        routeListener = listener
    }

    /** Waits a moment first, so a link that keeps failing isn't hammered. */
    private fun reopenHeadsetMic(audio: AudioManager) {
        handler.removeCallbacksAndMessages(REOPEN)
        handler.postDelayed({
            if (!keepHeadsetMic) return@postDelayed
            val headset = bluetoothHeadset(audio) ?: return@postDelayed
            if (audio.communicationDevice?.id != headset.id) {
                audio.setCommunicationDevice(headset)
            }
        }, REOPEN, 500)
    }

    private fun stopKeepingHeadsetMic(audio: AudioManager) {
        keepHeadsetMic = false
        handler.removeCallbacksAndMessages(REOPEN)
        routeListener?.let { audio.removeOnCommunicationDeviceChangedListener(it) }
        routeListener = null
    }

    @SuppressLint("MissingPermission")
    private fun startVadListening(
        silenceDurationMs: Int,
        maxUtteranceMs: Int,
        preRollMs: Int
    ): Boolean {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        synchronized(vadLock) {
            vadSilenceDurationMs = max(400, silenceDurationMs)
            vadMaxUtteranceSamples = max(16000 * 3, maxUtteranceMs * 16)
            vadPreRollMaxSamples = max(3200, preRollMs * 16)
            if (vadListening && vadThread?.isAlive == true) {
                return true
            }
            resetVadStateLocked(keepPreRoll = true)
        }
        stopVadListening(flush = false)

        val minBuf = AudioRecord.getMinBufferSize(
            16000,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuf <= 0) return false

        val recorder = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                16000,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                max(minBuf * 2, 6400)
            )
        } catch (_: Exception) {
            return false
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return false
        }

        try {
            recorder.startRecording()
        } catch (_: Exception) {
            recorder.release()
            return false
        }

        vadListening = true
        val thread = Thread({
            val frame = ShortArray(320) // 20 ms at 16,000 Hz
            try {
                while (vadListening) {
                    val read = recorder.read(frame, 0, frame.size)
                    if (read == frame.size) {
                        processVadFrame(frame)
                    }
                }
            } catch (_: Exception) {
            } finally {
                try {
                    recorder.stop()
                } catch (_: Exception) {
                }
                recorder.release()
            }
        }, "CookTogetherVadThread")
        vadThread = thread
        thread.start()
        return true
    }

    private fun stopVadListening(flush: Boolean): String? {
        vadListening = false
        vadThread?.let {
            try {
                it.join(400)
            } catch (_: InterruptedException) {
            }
        }
        vadThread = null
        synchronized(vadLock) {
            var path: String? = null
            if (flush && vadInSpeech && vadActiveSpeechFrames >= 5) {
                path = writeWavFileLocked(vadSpeechSamples.toShortArray())
            }
            resetVadStateLocked(keepPreRoll = false)
            return path
        }
    }

    private fun resetVadStateLocked(keepPreRoll: Boolean) {
        if (!keepPreRoll) {
            vadPreRollSamples.clear()
        }
        vadSpeechSamples.clear()
        vadInSpeech = false
        vadOnsetFrames = 0
        vadActiveSpeechFrames = 0
        vadSilenceFrames = 0
        vadPeakRms = 0f
    }

    private fun processVadFrame(frame: ShortArray) {
        var notifyStart = false
        var finishedWavPath: String? = null

        synchronized(vadLock) {
            if (!vadListening) return
            var sumSq = 0f
            for (s in frame) {
                val norm = s.toFloat() / 32768f
                sumSq += norm * norm
            }
            val rms = sqrt(sumSq / frame.size.toFloat())
            val startThreshold = max(0.012f, vadNoiseFloor * 2.2f)
            val continueThreshold = max(0.008f, vadNoiseFloor * 1.5f)

            if (!vadInSpeech) {
                for (s in frame) vadPreRollSamples.add(s)
                if (vadPreRollSamples.size > vadPreRollMaxSamples) {
                    vadPreRollSamples.subList(0, vadPreRollSamples.size - vadPreRollMaxSamples).clear()
                }
                if (rms >= startThreshold) {
                    vadOnsetFrames += 1
                    if (vadOnsetFrames >= 3) {
                        vadInSpeech = true
                        vadSpeechSamples.clear()
                        vadSpeechSamples.addAll(vadPreRollSamples)
                        vadPreRollSamples.clear()
                        vadActiveSpeechFrames = vadOnsetFrames
                        vadSilenceFrames = 0
                        vadPeakRms = rms
                        vadOnsetFrames = 0
                        notifyStart = true
                    }
                } else {
                    vadOnsetFrames = 0
                    vadNoiseFloor = min(0.030f, max(0.003f, 0.98f * vadNoiseFloor + 0.02f * rms))
                }
            } else {
                for (s in frame) vadSpeechSamples.add(s)
                if (rms > vadPeakRms) vadPeakRms = rms
                if (rms >= continueThreshold) {
                    vadActiveSpeechFrames += 1
                    vadSilenceFrames = 0
                } else {
                    vadSilenceFrames += 1
                }
                val silenceMs = vadSilenceFrames * 20
                if (silenceMs >= vadSilenceDurationMs || vadSpeechSamples.size >= vadMaxUtteranceSamples) {
                    val isValid = vadActiveSpeechFrames >= 4 && vadPeakRms >= 0.013f
                    val captured = if (isValid) vadSpeechSamples.toShortArray() else null
                    resetVadStateLocked(keepPreRoll = false)
                    if (captured != null) {
                        finishedWavPath = writeWavFileLocked(captured)
                    }
                }
            }
        }

        if (notifyStart) {
            handler.post { audioRouteChannel?.invokeMethod("onVadSpeechStart", null) }
        }
        finishedWavPath?.let { path ->
            handler.post { audioRouteChannel?.invokeMethod("onVadUtterance", mapOf("path" to path)) }
        }
    }

    private fun writeWavFileLocked(samples: ShortArray): String? {
        if (samples.isEmpty()) return null
        var maxAbs = 0
        for (s in samples) {
            val a = if (s == Short.MIN_VALUE) Int.MAX_VALUE else abs(s.toInt())
            if (a > maxAbs) maxAbs = a
        }
        val gain = if (maxAbs > 200) min(8.0f, 27850.0f / maxAbs.toFloat()) else 1.0f
        val minSamples = 24000 // 1.5 s at 16 kHz
        val totalSamples = max(samples.size, minSamples)
        val dataByteCount = totalSamples * 2
        val buf = ByteBuffer.allocate(44 + dataByteCount).order(ByteOrder.LITTLE_ENDIAN)

        buf.put("RIFF".toByteArray(Charsets.US_ASCII))
        buf.putInt(36 + dataByteCount)
        buf.put("WAVE".toByteArray(Charsets.US_ASCII))
        buf.put("fmt ".toByteArray(Charsets.US_ASCII))
        buf.putInt(16)
        buf.putShort(1)
        buf.putShort(1)
        buf.putInt(16000)
        buf.putInt(32000)
        buf.putShort(2)
        buf.putShort(16)
        buf.put("data".toByteArray(Charsets.US_ASCII))
        buf.putInt(dataByteCount)

        for (i in 0 until totalSamples) {
            if (i < samples.size) {
                val scaled = (samples[i].toFloat() * gain).toInt().coerceIn(-32767, 32767)
                buf.putShort(scaled.toShort())
            } else {
                buf.putShort(0)
            }
        }

        return try {
            val file = File(cacheDir, "ct_vad_${UUID.randomUUID()}.wav")
            FileOutputStream(file).use { it.write(buf.array()) }
            file.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private companion object {
        val REOPEN = Any()
    }
}
