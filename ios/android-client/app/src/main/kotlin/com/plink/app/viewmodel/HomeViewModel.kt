package com.plink.app.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plink.app.data.Analytics
import com.plink.app.data.api.PlinkApi
import com.plink.app.data.models.CreateRoomRequest
import com.plink.app.data.models.JoinRoomRequest
import com.plink.app.data.models.Room
import com.plink.app.data.models.TrendingVideo
import com.plink.app.data.models.youtubeMediaItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class HomeUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val trending: List<TrendingVideo> = emptyList(),
    val rooms: List<Room> = emptyList(),
    val joinCode: String = "",
    val actionLoading: Boolean = false,
)

class HomeViewModel(
    private val api: PlinkApi,
) : ViewModel() {

    private val _state = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = true, error = null)
            try {
                val trending = api.getTrending()
                val rooms = api.getRooms()
                _state.value = _state.value.copy(
                    loading = false,
                    trending = trending.results,
                    rooms = rooms,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    loading = false,
                    error = e.message ?: "Failed to load",
                )
            }
        }
    }

    fun setJoinCode(code: String) {
        _state.value = _state.value.copy(joinCode = code.uppercase())
    }

    fun createFromVideo(video: TrendingVideo, onSuccess: (Room) -> Unit) {
        viewModelScope.launch {
            _state.value = _state.value.copy(actionLoading = true, error = null)
            try {
                val mediaItem = youtubeMediaItem(video.id, video.title, video.thumbnailURL)
                val room = api.createRoom(
                    CreateRoomRequest(
                        name = video.title,
                        mediaItem = mediaItem,
                    ),
                )
                val joined = api.joinRoom(JoinRoomRequest(room.code))
                Analytics.roomCreated()
                Analytics.roomJoined()
                _state.value = _state.value.copy(actionLoading = false)
                onSuccess(joined)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    actionLoading = false,
                    error = e.message ?: "Create failed",
                )
            }
        }
    }

    fun joinByCode(onSuccess: (Room) -> Unit) {
        val code = _state.value.joinCode.trim()
        if (code.isBlank()) return
        viewModelScope.launch {
            _state.value = _state.value.copy(actionLoading = true, error = null)
            try {
                val room = api.joinRoom(JoinRoomRequest(code))
                Analytics.roomJoined()
                _state.value = _state.value.copy(actionLoading = false)
                onSuccess(room)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    actionLoading = false,
                    error = e.message ?: "Join failed",
                )
            }
        }
    }
}