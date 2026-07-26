package com.plink.app.data.models

import kotlinx.serialization.Serializable

@Serializable
data class User(
    val id: String,
    val username: String,
    val email: String,
    val avatarURL: String? = null,
    val avatarData: String? = null,
    val isPremium: Boolean = false,
    val role: String? = null,
)

@Serializable
data class AuthResponse(
    val token: String,
    val refreshToken: String,
    val accessExpiresAt: Long? = null,
    val user: User,
)

@Serializable
data class MediaItem(
    val id: String,
    val title: String,
    val artist: String? = null,
    val thumbnailURL: String? = null,
    val streamURL: String,
    val duration: Double? = null,
    val mediaType: String,
    val source: String,
    val videoId: String? = null,
)

@Serializable
data class Room(
    val id: String,
    val name: String,
    val code: String,
    val hostID: String,
    val hostName: String,
    val maxParticipants: Int = 10,
    val mediaItem: MediaItem? = null,
    val isActive: Boolean = true,
    val participantCount: Int? = null,
)

@Serializable
data class TrendingVideo(
    val id: String,
    val title: String,
    val thumbnailURL: String? = null,
    val channelTitle: String? = null,
)

@Serializable
data class TrendingResponse(
    val results: List<TrendingVideo> = emptyList(),
)

@Serializable
data class ChatMessage(
    val id: String,
    val senderID: String,
    val text: String,
    val createdAt: String,
    val clientMessageId: String? = null,
)

@Serializable
data class MessagesResponse(
    val messages: List<ChatMessage> = emptyList(),
    val nextCursor: String? = null,
)

@Serializable
data class Participant(
    val userId: String,
    val username: String,
    val avatarURL: String? = null,
)

@Serializable
data class ParticipantsResponse(
    val participants: List<Participant> = emptyList(),
)

@Serializable
data class RealtimeTicketResponse(
    val ticket: String,
    val expiresInSec: Int,
    val protocol: List<String> = emptyList(),
)

@Serializable
data class AvatarUploadResponse(
    val avatarData: String,
    val avatarURL: String,
)

@Serializable
data class SignInRequest(
    val email: String,
    val password: String,
)

@Serializable
data class SignUpRequest(
    val email: String,
    val password: String,
    val username: String,
)

@Serializable
data class JoinRoomRequest(
    val code: String,
)

@Serializable
data class CreateRoomRequest(
    val name: String,
    val maxParticipants: Int = 10,
    val mediaItem: MediaItem,
    val privacy: String = "public",
)

@Serializable
data class RealtimeTicketRequest(
    val roomId: String,
)

@Serializable
data class AvatarUploadRequest(
    val avatar: String,
)

@Serializable
data class ApiError(
    val error: String? = null,
    val message: String? = null,
)

fun youtubeMediaItem(videoId: String, title: String, thumbnailURL: String? = null): MediaItem {
    val hosted = "https://plink-backend-production-ef31.up.railway.app/api/media/youtube-player?id=$videoId"
    return MediaItem(
        id = videoId,
        title = title,
        thumbnailURL = thumbnailURL ?: "https://img.youtube.com/vi/$videoId/hqdefault.jpg",
        streamURL = hosted,
        mediaType = "video",
        source = "youtube",
        videoId = videoId,
    )
}