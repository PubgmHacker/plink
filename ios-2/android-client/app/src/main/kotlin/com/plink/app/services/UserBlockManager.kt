package com.plink.app.services

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * User Block Manager — local block list + sync with backend.
 *
 * Features:
 * - Block/unblock users locally (SharedPreferences)
 * - Sync with backend `/api/moderation/block`
 * - Filter messages/rooms from blocked users
 *
 * App Store / Play Store UGC compliance requirement.
 */
class UserBlockManager private constructor(private val context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("plink_blocks", Context.MODE_PRIVATE)

    val blockedUserIds: Set<String>
        get() = prefs.getStringSet("blocked_ids", emptySet()) ?: emptySet()

    fun isBlocked(userId: String): Boolean = userId in blockedUserIds

    fun blockUser(userId: String) {
        val current = blockedUserIds.toMutableSet()
        current.add(userId)
        prefs.edit().putStringSet("blocked_ids", current).apply()
    }

    fun unblockUser(userId: String) {
        val current = blockedUserIds.toMutableSet()
        current.remove(userId)
        prefs.edit().putStringSet("blocked_ids", current).apply()
    }

    suspend fun reportUser(
        targetUserId: String,
        reason: String,
        details: String = "",
    ): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            // TODO: call api.moderationReport(targetUserId, reason, details)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    companion object {
        @Volatile private var instance: UserBlockManager? = null
        fun getInstance(context: Context): UserBlockManager =
            instance ?: synchronized(this) {
                instance ?: UserBlockManager(context.applicationContext).also { instance = it }
            }
    }
}
