package com.example.tortoiseshare

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.media.projection.MediaProjectionManager
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.tortoiseshare/screen_share"
    private val EVENT_CHANNEL = "com.tortoiseshare/screen_stream"
    private val REQUEST_MEDIA_PROJECTION = 1001

    private var screenCaptureService: ScreenCaptureService? = null
    private var isBound = false
    private var eventSink: EventChannel.EventSink? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(className: ComponentName, service: IBinder) {
            val binder = service as ScreenCaptureService.LocalBinder
            screenCaptureService = binder.getService()
            isBound = true
            
            // Connecter le callback du service au sink Flutter
            screenCaptureService?.onFrameCaptured = { bytes ->
                runOnUiThread {
                    eventSink?.success(bytes)
                }
            }
        }

        override fun onServiceDisconnected(arg0: ComponentName) {
            isBound = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startScreenShare") {
                startMediaProjectionRequest()
                result.success(true)
            } else if (call.method == "stopScreenShare") {
                stopScreenShare()
                result.success(true)
            } else if (call.method == "performClick") {
                val x = call.argument<Double>("x")?.toFloat() ?: 0f
                val y = call.argument<Double>("y")?.toFloat() ?: 0f
                TortoiseAccessibilityService.performClick(x, y)
                result.success(true)
            } else if (call.method == "openAccessibilitySettings") {
                val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                startActivity(intent)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
        
        // Démarrer le service pour qu'il soit prêt
        Intent(this, ScreenCaptureService::class.java).also { intent ->
            bindService(intent, connection, Context.BIND_AUTO_CREATE)
        }
    }

    private fun startMediaProjectionRequest() {
        val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(mediaProjectionManager.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                // Obtenir les dimensions de l'écran
                val metrics = resources.displayMetrics
                screenCaptureService?.startProjection(
                    resultCode, 
                    data, 
                    metrics.widthPixels, 
                    metrics.heightPixels, 
                    metrics.densityDpi
                )
            }
        }
    }

    private fun stopScreenShare() {
        screenCaptureService?.stopProjection()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        if (isBound) {
            unbindService(connection)
            isBound = false
        }
    }
}
