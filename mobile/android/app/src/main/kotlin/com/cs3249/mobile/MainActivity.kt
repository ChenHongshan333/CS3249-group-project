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
                        audio.clearCommunicationDevice()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        shutterSound.release()
        super.onDestroy()
    }

    /**
     * Records speech through a Bluetooth headset's mic, such as the glasses,
     * so the user doesn't have to talk to the phone on the counter. Replies
     * with the headset's name once its audio link is up, or null when there is
     * no Bluetooth headset or the link doesn't come up within 3 seconds.
     */
    private fun useBluetoothMic(audio: AudioManager, result: MethodChannel.Result) {
        val headset = audio.availableCommunicationDevices
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
        if (headset == null || !audio.setCommunicationDevice(headset)) {
            result.success(null)
            return
        }
        val handler = Handler(Looper.getMainLooper())
        val deadline = System.currentTimeMillis() + 3000
        fun waitForLink() {
            @Suppress("DEPRECATION")
            val linkUp = audio.communicationDevice?.id == headset.id && audio.isBluetoothScoOn
            when {
                linkUp -> result.success(headset.productName.toString())
                System.currentTimeMillis() > deadline -> {
                    audio.clearCommunicationDevice()
                    result.success(null)
                }
                else -> handler.postDelayed({ waitForLink() }, 100)
            }
        }
        waitForLink()
    }
}
