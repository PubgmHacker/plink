package com.plink.app.services

import android.content.Context
import android.content.SharedPreferences
import com.plink.app.data.api.PlinkApi
import com.plink.app.data.models.ModerationReportRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * User Block Manager — local block list + abuse reporting.
 *
 * Features:
 * - Block/unblock users locally (SharedPreferences)
 * - Report abuse via backend `POST /api/moderation/report`
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

    /**
     * Files a moderation report against a user with the backend.
     *
     * [reason] must be one of [MODERATION_REASONS]; anything else is coerced to
     * "other" so a malformed reason never trips the server's 400 validation.
     * Requires an authenticated [PlinkApi] — the Authorization header is attached
     * by the OkHttp interceptor wired up in AppContainer.
     */
    suspend fun reportUser(
        api: PlinkApi,
        targetUserId: String,
        reason: String,
        details: String = "",
    ): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val safeReason = if (reason in MODERATION_REASONS) reason else "other"
            api.moderationReport(
                ModerationReportRequest(
                    targetType = "user",
                    targetId = targetUserId,
                    reason = safeReason,
                    comment = details.ifBlank { null },
                ),
            )
            Result.success(Unit)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    companion object {
        /** Report reasons accepted by the backend `/moderation/report` endpoint. */
        val MODERATION_REASONS =
            setOf("spam", "harassment", "hate", "sexual", "violence", "illegal", "copyright", "other")

        @Volatile private var instance: UserBlockManager? = null
        fun getInstance(context: Context): UserBlockManager =
            instance ?: synchronized(this) {
                instance ?: UserBlockManager(context.applicationContext).also { instance = it }
            }
    }
}
