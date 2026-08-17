package com.plink.app.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plink.app.data.api.PlinkApi
import com.plink.app.data.models.AvatarUploadRequest
import com.plink.app.data.models.User
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ProfileUiState(
    val user: User,
    val uploading: Boolean = false,
    val error: String? = null,
)

class ProfileViewModel(
    private val api: PlinkApi,
    initialUser: User,
) : ViewModel() {

    private val _state = MutableStateFlow(ProfileUiState(user = initialUser))
    val state: StateFlow<ProfileUiState> = _state.asStateFlow()

    fun uploadAvatar(dataUrl: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(uploading = true, error = null)
            try {
                val response = api.uploadAvatar(AvatarUploadRequest(dataUrl))
                _state.value = ProfileUiState(
                    user = _state.value.user.copy(
                        avatarURL = response.avatarURL,
                        avatarData = response.avatarData,
                    ),
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    uploading = false,
                    error = e.message ?: "Upload failed",
                )
            }
        }
    }
}