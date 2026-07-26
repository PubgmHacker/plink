package com.plink.app.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plink.app.data.Analytics
import com.plink.app.data.api.PlinkApi
import com.plink.app.data.models.SignInRequest
import com.plink.app.data.models.SignUpRequest
import com.plink.app.data.models.User
import com.plink.app.data.prefs.TokenStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException

data class AuthUiState(
    val loading: Boolean = false,
    val error: String? = null,
    val user: User? = null,
)

class AuthViewModel(
    private val api: PlinkApi,
    private val tokenStore: TokenStore,
) : ViewModel() {

    private val _state = MutableStateFlow(AuthUiState())
    val state: StateFlow<AuthUiState> = _state.asStateFlow()

    init {
        Analytics.appOpen()
        restoreSession()
    }

    fun restoreSession() {
        if (tokenStore.getToken().isNullOrBlank()) return
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = true, error = null)
            try {
                val user = api.getMe()
                _state.value = AuthUiState(user = user)
            } catch (_: Exception) {
                tokenStore.clear()
                _state.value = AuthUiState()
            }
        }
    }

    fun signIn(email: String, password: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = true, error = null)
            try {
                val response = api.signIn(SignInRequest(email.trim(), password))
                tokenStore.setToken(response.token)
                Analytics.login()
                _state.value = AuthUiState(user = response.user)
            } catch (e: Exception) {
                _state.value = AuthUiState(error = parseError(e))
            }
        }
    }

    fun signUp(email: String, password: String, username: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = true, error = null)
            try {
                val response = api.signUp(
                    SignUpRequest(
                        email = email.trim(),
                        password = password,
                        username = username.trim(),
                    ),
                )
                tokenStore.setToken(response.token)
                Analytics.signUp()
                _state.value = AuthUiState(user = response.user)
            } catch (e: Exception) {
                _state.value = AuthUiState(error = parseError(e))
            }
        }
    }

    fun logout() {
        tokenStore.clear()
        _state.value = AuthUiState()
    }

    private fun parseError(e: Exception): String {
        if (e is HttpException) {
            val body = e.response()?.errorBody()?.string()
            if (!body.isNullOrBlank()) {
                return body.substringAfter("\"error\":\"").substringBefore("\"").ifBlank {
                    "HTTP ${e.code()}"
                }
            }
            return "HTTP ${e.code()}"
        }
        return e.message ?: "Request failed"
    }
}