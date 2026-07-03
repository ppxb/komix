package com.example.komix

import android.content.Context
import android.os.Bundle
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val VOLUME_CHANNEL = "volume_key_handler"
        private const val VOLUME_EVENT_CHANNEL = "volume_key_events"

        init {
            System.loadLibrary("komix_core")
        }

        @JvmStatic
        private external fun initRustlsPlatformVerifier(context: Context)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        initRustlsPlatformVerifier(applicationContext)
        super.onCreate(savedInstanceState)
    }

    private var volumeKeyInterceptionEnabled = false
    private var volumeEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableInterception" -> {
                        volumeKeyInterceptionEnabled = true
                        result.success(null)
                    }
                    "disableInterception" -> {
                        volumeKeyInterceptionEnabled = false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_EVENT_CHANNEL)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        volumeEventSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        volumeEventSink = null
                    }
                }
            )
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeyInterceptionEnabled) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    volumeEventSink?.success("volume_down")
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    volumeEventSink?.success("volume_up")
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}
