package com.example.tortoiseshare

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class TortoiseAccessibilityService : AccessibilityService() {

    companion object {
        var instance: TortoiseAccessibilityService? = null
        
        fun performClick(x: Float, y: Float) {
            instance?.click(x, y)
        }
        
        fun performScroll(x1: Float, y1: Float, x2: Float, y2: Float) {
            instance?.scroll(x1, y1, x2, y2)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d("TortoiseAccessibility", "Service Connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // On n'a pas besoin de lire les événements pour l'instant
    }

    override fun onInterrupt() {
        instance = null
        Log.d("TortoiseAccessibility", "Service Interrupted")
    }
    
    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    fun click(x: Float, y: Float) {
        val path = Path()
        path.moveTo(x, y)
        
        val builder = GestureDescription.Builder()
        val gesture = builder
            .addStroke(GestureDescription.StrokeDescription(path, 0, 50))
            .build()
            
        dispatchGesture(gesture, null, null)
        Log.d("TortoiseAccessibility", "Click dispatched at $x, $y")
    }

    fun scroll(x1: Float, y1: Float, x2: Float, y2: Float) {
        val path = Path()
        path.moveTo(x1, y1)
        path.lineTo(x2, y2)
        
        val builder = GestureDescription.Builder()
        val gesture = builder
            .addStroke(GestureDescription.StrokeDescription(path, 0, 300)) // 300ms swipe
            .build()
            
        dispatchGesture(gesture, null, null)
    }
}
