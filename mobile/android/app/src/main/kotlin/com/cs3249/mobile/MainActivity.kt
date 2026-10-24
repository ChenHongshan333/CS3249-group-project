package com.cs3249.mobile

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaActionSound
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val shutterSound = MediaActionSound()
    private val handler = Handler(Looper.getMainLooper())

    /** True while the app records through the headset's mic and keeps it. */
    private var keepHeadsetMic = false
    private var routeListener: AudioManager.OnCommunicationDeviceChangedListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shutterSound.load(MediaActionSound.SHUTTER_CLICK)
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cooktogether/audio_route")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playShutter" -> {
                        shutterSound.play(MediaActionSound.SHUTTER_CLICK)
                        result.success(null)
                    }
                    "useBluetoothMic" -> useBluetoothMic(audio, result)
                    "clear" -> {
                        stopKeepingHeadsetMic(audio)
                        audio.clearCommunicationDevice()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
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

    private companion object {
        val REOPEN = Any()
    }
}
