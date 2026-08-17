package com.plink.app.data

import android.util.Log

/**
 * Analytics stub for Android MVP closed beta.
 * Swap Log for FirebaseAnalytics when google-services.json is configured.
 */
object Analytics {
    private const val TAG = "PlinkAnalytics"

    fun track(event: String, params: Map<String, Any?> = emptyMap()) {
        Log.i(TAG, "$event $params")
    }

    fun appOpen() = track("app_open")
    fun signUp() = track("sign_up")
    fun login() = track("login")
    fun roomCreated() = track("room_created")
    fun roomJoined() = track("room_joined")
    fun roomLeft() = track("room_left")
    fun messageSent() = track("message_sent")
    fun syncDrift(ms: Long) = track("sync_drift", mapOf("drift_ms" to ms))
}
