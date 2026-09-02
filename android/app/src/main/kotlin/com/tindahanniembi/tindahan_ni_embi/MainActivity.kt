package com.tindahanniembi.tindahan_ni_embi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.StatFs

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tindahan_ni_embi/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "freeBytes") {
                    result.success(StatFs(filesDir.absolutePath).availableBytes)
                } else result.notImplemented()
            }
    }
}
