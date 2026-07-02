package com.example.komix

import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
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
}
