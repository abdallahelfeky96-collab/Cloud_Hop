package com.cloudhop.cloud_hop

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var gameAudio: GameAudio? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyGameFullscreen()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        gameAudio?.release()
        gameAudio = GameAudio(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cloud_hop/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "preload" -> { gameAudio?.preload(); result.success(null) }
                    "state" -> { gameAudio?.configure(call.argument<Boolean>("play") == true, call.argument<Boolean>("allowed") == true, call.argument<Boolean>("voice") == true); result.success(null) }
                    "cue" -> { gameAudio?.cue(call.arguments as? String ?: ""); result.success(null) }
                    "release" -> { gameAudio?.release(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cloud_hop/fullscreen")
            .setMethodCallHandler { call, result ->
                if (call.method == "apply") {
                    applyGameFullscreen()
                    result.success(null)
                } else result.notImplemented()
            }
    }

    override fun onPause() {
        gameAudio?.setForeground(false)
        super.onPause()
    }
    override fun onResume() {
        super.onResume()
        gameAudio?.setForeground(true)
    }
    override fun onDestroy() {
        gameAudio?.release()
        gameAudio = null
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyGameFullscreen()
    }

    @Suppress("DEPRECATION")
    private fun applyGameFullscreen() {
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= 29) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= 28) {
            val layout = window.attributes
            layout.layoutInDisplayCutoutMode = if (Build.VERSION.SDK_INT >= 30)
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            else WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = layout
        }
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.apply {
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                hide(WindowInsets.Type.systemBars())
            }
        } else {
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        }
    }
}
