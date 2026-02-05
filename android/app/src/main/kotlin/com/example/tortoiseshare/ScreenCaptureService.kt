package com.example.tortoiseshare

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class ScreenCaptureService : Service() {

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var screenWidth = 720
    private var screenHeight = 1280
    private var screenDensity = 160
    
    // Callback pour envoyer les données à l'activité/Flutter
    var onFrameCaptured: ((ByteArray) -> Unit)? = null

    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): ScreenCaptureService = this@ScreenCaptureService
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    override fun onCreate() {
        super.onCreate()
        startForegroundService()
    }

    private fun startForegroundService() {
        val channelId = "screen_capture_channel"
        val channelName = "Screen Capture"
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, channelName, NotificationManager.IMPORTANCE_DEFAULT
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notificationBuilder = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Partage d'écran actif")
            .setContentText("TortoiseShare partage votre écran...")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)

        // Pour Android 14+, il faut spécifier le type de service
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, notificationBuilder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1, notificationBuilder.build())
        }
    }

    private var isProcessing = false

    fun startProjection(resultCode: Int, data: Intent, width: Int, height: Int, density: Int) {
        val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpManager.getMediaProjection(resultCode, data)

        // Optimisation : Réduire la résolution pour la performance (max 600px de large)
        val targetWidth = 600
        if (width > targetWidth) {
            val ratio = height.toFloat() / width.toFloat()
            this.screenWidth = targetWidth
            this.screenHeight = (targetWidth * ratio).toInt()
            this.screenDensity = (density * (targetWidth.toFloat() / width.toFloat())).toInt()
        } else {
            this.screenWidth = width
            this.screenHeight = height
            this.screenDensity = density
        }
        
        Log.d("TortoiseStream", "Capture resolution: ${this.screenWidth}x${this.screenHeight}")

        createVirtualDisplay()
    }

    private fun createVirtualDisplay() {
        // maxImages = 1 pour forcer le temps réel (on rate des frames si trop lent)
        imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)
        
        mediaProjection?.createVirtualDisplay(
            "ScreenCapture",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null, null
        ).also { virtualDisplay = it }

        imageReader?.setOnImageAvailableListener({ reader ->
            // Mécanisme Anti-Lag : Si on traite déjà une image, on ignore la suivante !
            if (isProcessing) {
                // Important : Il faut quand même acquérir et fermer l'image sinon le buffer se bloque
                val discarded = reader.acquireLatestImage()
                discarded?.close()
                return@setOnImageAvailableListener
            }

            val image = reader.acquireLatestImage()
            if (image != null) {
                isProcessing = true
                processImage(image)
                image.close()
                isProcessing = false
            }
        }, Handler(Looper.getMainLooper())) // Idéalement utiliser un thread background
    }

    private fun processImage(image: Image) {
        val planes = image.planes
        val buffer = planes[0].buffer
        val pixelStride = planes[0].pixelStride
        val rowStride = planes[0].rowStride
        val rowPadding = rowStride - pixelStride * screenWidth

        // Créer un bitmap
        val bitmap = Bitmap.createBitmap(
            screenWidth + rowPadding / pixelStride,
            screenHeight,
            Bitmap.Config.ARGB_8888
        )
        bitmap.copyPixelsFromBuffer(buffer)
        
        // Rogner si padding
        val finalBitmap = if (rowPadding == 0) {
            bitmap
        } else {
            Bitmap.createBitmap(bitmap, 0, 0, screenWidth, screenHeight)
        }

        // Compresser en JPEG
        val stream = ByteArrayOutputStream()
        finalBitmap.compress(Bitmap.CompressFormat.JPEG, 65, stream) // 65 = Bon compromis Vitesse/Qualité
        val byteArray = stream.toByteArray()

        // Envoyer
        onFrameCaptured?.invoke(byteArray)
    }

    fun stopProjection() {
        mediaProjection?.stop()
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection = null
        stopSelf()
    }
}
