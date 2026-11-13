package com.example.m3

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        TrialLicenseBridge(this, MethodChannel(messenger, "com.example.m3/licensing",
            StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue()))
    }
}
