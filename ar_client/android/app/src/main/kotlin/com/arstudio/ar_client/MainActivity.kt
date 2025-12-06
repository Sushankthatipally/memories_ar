package com.arstudio.ar_client

import android.content.Intent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.arstudio.ar_client/ar"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAR" -> {
                    try {
                        val imagePaths = call.argument<List<String>>("imagePaths")
                        val videoPaths = call.argument<List<String>>("videoPaths")

                        if (imagePaths == null || videoPaths == null) {
                            result.error("INVALID_ARGS", "Missing imagePaths or videoPaths", null)
                            return@setMethodCallHandler
                        }

                        if (imagePaths.size != videoPaths.size) {
                            result.error("INVALID_ARGS", "imagePaths and videoPaths must have same length", null)
                            return@setMethodCallHandler
                        }

                        val intent = Intent(this, ARActivity::class.java).apply {
                            putStringArrayListExtra("IMAGE_PATHS", ArrayList(imagePaths))
                            putStringArrayListExtra("VIDEO_PATHS", ArrayList(videoPaths))
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("START_AR_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
