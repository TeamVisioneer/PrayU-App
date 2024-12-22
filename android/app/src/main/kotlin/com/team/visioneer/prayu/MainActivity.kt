package com.team.visioneer.prayu

import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.team.visioneer.prayu/intent"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "handleIntent") {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.success(false)
                }
                try {
                    val intent = Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
                    startActivity(intent)
                    result.success(true)
                    return@setMethodCallHandler
                } catch (e: Exception) {
                    result.success(false)
                    return@setMethodCallHandler
                }
            } else {
                result.notImplemented()
                return@setMethodCallHandler
            }
        }
    }
}