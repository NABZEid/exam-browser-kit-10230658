package com.examsafe.exam_browser

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "exam_guard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        // Blok screenshot & screen recording
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        // Kunci aplikasi (screen pinning)
                        try { startLockTask() } catch (e: Exception) {}
                        result.success(true)
                    }
                    "disable" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        try { stopLockTask() } catch (e: Exception) {}
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
