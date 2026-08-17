package com.plink.app.data.api

import com.plink.app.data.models.AuthResponse
import com.plink.app.data.models.AvatarUploadRequest
import com.plink.app.data.models.AvatarUploadResponse
import com.plink.app.data.models.CreateRoomRequest
import com.plink.app.data.models.JoinRoomRequest
import com.plink.app.data.models.MessagesResponse
import com.plink.app.data.models.ParticipantsResponse
import com.plink.app.data.models.RealtimeTicketRequest
import com.plink.app.data.models.RealtimeTicketResponse
import com.plink.app.data.models.Room
import com.plink.app.data.models.SignInRequest
import com.plink.app.data.models.SignUpRequest
import com.plink.app.data.models.TrendingResponse
import com.plink.app.data.models.User
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

interface PlinkApi {
    @POST("auth/signin")
    suspend fun signIn(@Body body: SignInRequest): AuthResponse

    @POST("auth/signup")
    suspend fun signUp(@Body body: SignUpRequest): AuthResponse

    @GET("users/me")
    suspend fun getMe(): User

    @GET("media/trending")
    suspend fun getTrending(@Query("maxResults") maxResults: Int = 10): TrendingResponse

    @GET("rooms")
    suspend fun getRooms(): List<Room>

    @POST("rooms")
    suspend fun createRoom(@Body body: CreateRoomRequest): Room

    @POST("rooms/join")
    suspend fun joinRoom(@Body body: JoinRoomRequest): Room

    @POST("rooms/{roomId}/leave")
    suspend fun leaveRoom(@Path("roomId") roomId: String): Map<String, Boolean>

    @GET("rooms/{roomId}/participants")
    suspend fun getParticipants(@Path("roomId") roomId: String): ParticipantsResponse

    @GET("rooms/{roomId}/messages")
    suspend fun getMessages(
        @Path("roomId") roomId: String,
        @Query("limit") limit: Int = 50,
    ): MessagesResponse

    @POST("realtime/ticket")
    suspend fun getRealtimeTicket(@Body body: RealtimeTicketRequest): RealtimeTicketResponse

    @POST("users/me/avatar")
    suspend fun uploadAvatar(@Body body: AvatarUploadRequest): AvatarUploadResponse
}