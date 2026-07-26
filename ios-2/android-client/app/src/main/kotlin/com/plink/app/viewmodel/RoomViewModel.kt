package com.plink.app.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plink.app.data.Analytics
import com.plink.app.data.api.PlinkApi
import com.plink.app.data.models.ChatMessage
import com.plink.app.data.models.JoinRoomRequest
import com.plink.app.data.models.Participant
import com.plink.app.data.models.Room
import com.plink.app.data.sync.ClockSynchronizer
import com.plink.app.data.sync.OrderedSyncController
import com.plink.app.data.sync.PlayerSyncAdapter
import com.plink.app.data.ws.PlinkRealtimeClient
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class RoomUiState(
    val room: Room,
    val messages: List<ChatMessage> = emptyList(),
    val participants: List<Participant> = emptyList(),
    val connected: Boolean = false,
    val draft: String = "",
    val error: String? = null,
    val loading: Boolean = true,
    val role: String = "viewer",
    val playing: Boolean = false,
    val positionSec: Double = 0.0,
    val durationSec: Double = 0.0,
    val driftMs: Double = 0.0,
    val playerReady: Boolean = false,
    /** Player commands consumed by RoomScreen WebView (cmd + optional seconds). */
    val playerCommand: PlayerCommand? = null,
)

data class PlayerCommand(
    val id: Long,
    val cmd: String,
    val seconds: Double? = null,
)

class RoomViewModel(
    private val api: PlinkApi,
    private val realtimeClient: PlinkRealtimeClient,
    initialRoom: Room,
    private val userId: String,
) : ViewModel() {

    private val _state = MutableStateFlow(
        RoomUiState(
            room = initialRoom,
            role = if (initialRoom.hostID == userId) "host" else "viewer",
        ),
    )
    val state: StateFlow<RoomUiState> = _state.asStateFlow()

    private val clock = ClockSynchronizer()
    private var syncController: OrderedSyncController? = null
    private var hostPushJob: Job? = null
    private var lastHostPushMs = 0L
    private var applyingRemote = false
    private var cmdSeq = 0L

    private val playerAdapter = object : PlayerSyncAdapter {
        override fun getPositionSec() = _state.value.positionSec
        override fun getDurationSec() = _state.value.durationSec
        override fun isPlaying() = _state.value.playing
        override fun play() {
            applyingRemote = true
            emitPlayerCmd("play")
            _state.update { it.copy(playing = true) }
            viewModelScope.launch {
                delay(300)
                applyingRemote = false
            }
        }

        override fun pause() {
            applyingRemote = true
            emitPlayerCmd("pause")
            _state.update { it.copy(playing = false) }
            viewModelScope.launch {
                delay(300)
                applyingRemote = false
            }
        }

        override fun seek(sec: Double) {
            applyingRemote = true
            emitPlayerCmd("seek", sec)
            _state.update { it.copy(positionSec = sec) }
            viewModelScope.launch {
                delay(300)
                applyingRemote = false
            }
        }
    }

    init {
        connect()
        observeRealtime()
    }

    private fun emitPlayerCmd(cmd: String, seconds: Double? = null) {
        cmdSeq += 1
        _state.update {
            it.copy(playerCommand = PlayerCommand(id = cmdSeq, cmd = cmd, seconds = seconds))
        }
    }

    private fun ensureSync(): OrderedSyncController {
        val existing = syncController
        if (existing != null) return existing
        val created = OrderedSyncController(clock, playerAdapter)
        syncController = created
        return created
    }

    private fun isHost(): Boolean = _state.value.role == "host"

    private fun observeRealtime() {
        viewModelScope.launch {
            realtimeClient.connected.collect { connected ->
                _state.update { it.copy(connected = connected) }
            }
        }
        viewModelScope.launch {
            realtimeClient.messages.collect { message ->
                _state.update { it.copy(messages = it.messages + message) }
            }
        }
        viewModelScope.launch {
            realtimeClient.errors.collect { error ->
                _state.update { it.copy(error = error) }
            }
        }
        viewModelScope.launch {
            realtimeClient.sessionReady.collect { ready ->
                if (ready.role == "host" || ready.role == "viewer") {
                    _state.update { it.copy(role = ready.role) }
                    if (ready.role == "host") startHostPushLoop() else hostPushJob?.cancel()
                }
            }
        }
        viewModelScope.launch {
            realtimeClient.clockReplies.collect { reply ->
                clock.ingest(reply.clientSentMs, reply.serverMs, System.currentTimeMillis())
            }
        }
        viewModelScope.launch {
            realtimeClient.syncStates.collect { state ->
                // Host ignores own echoes after first apply
                if (isHost() && syncController?.hasAppliedAnyState == true) {
                    _state.update { it.copy(driftMs = syncController?.lastDriftMs ?: 0.0) }
                    return@collect
                }
                val ctrl = ensureSync()
                ctrl.apply(state)
                _state.update {
                    it.copy(
                        playing = state.playing,
                        positionSec = state.positionMs / 1000.0,
                        driftMs = ctrl.lastDriftMs,
                    )
                }
            }
        }
    }

    private fun connect() {
        val room = _state.value.room
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            try {
                if (!room.code.isNullOrBlank()) {
                    runCatching { api.joinRoom(JoinRoomRequest(room.code)) }
                }
                val history = api.getMessages(room.id)
                val parts = api.getParticipants(room.id)
                _state.update {
                    it.copy(
                        messages = history.messages,
                        participants = parts.participants,
                        loading = false,
                    )
                }
                realtimeClient.connect(room.id)
                if (isHost()) startHostPushLoop()
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        loading = false,
                        error = e.message ?: "Room connect failed",
                    )
                }
            }
        }
    }

    private fun startHostPushLoop() {
        hostPushJob?.cancel()
        hostPushJob = viewModelScope.launch {
            while (isActive) {
                delay(2500)
                if (!isHost() || applyingRemote) continue
                if (!_state.value.playerReady) continue
                if (_state.value.playing) {
                    pushHostState(playing = true)
                }
            }
        }
    }

    fun onPlayerReady() {
        _state.update { it.copy(playerReady = true) }
        ensureSync()
        if (isHost()) {
            pushHostState(playing = true, positionSec = 0.0)
        } else {
            realtimeClient.requestState()
        }
    }

    fun onPlayerTick(time: Double, duration: Double, playing: Boolean) {
        _state.update {
            it.copy(positionSec = time, durationSec = duration, playing = playing)
        }
    }

    fun onPlayerError(code: Int) {
        _state.update { it.copy(error = "YouTube error $code") }
    }

    fun hostPlayPause() {
        if (!isHost()) return
        val next = !_state.value.playing
        if (next) emitPlayerCmd("play") else emitPlayerCmd("pause")
        _state.update { it.copy(playing = next) }
        pushHostState(playing = next)
    }

    fun hostSeekBy(deltaSec: Double) {
        if (!isHost()) return
        val next = (_state.value.positionSec + deltaSec).coerceAtLeast(0.0)
        emitPlayerCmd("seek", next)
        _state.update { it.copy(positionSec = next) }
        pushHostState(playing = _state.value.playing, positionSec = next)
    }

    private fun pushHostState(playing: Boolean, positionSec: Double? = null) {
        if (!isHost()) return
        val now = System.currentTimeMillis()
        if (now - lastHostPushMs < 120) return
        lastHostPushMs = now
        val pos = positionSec ?: _state.value.positionSec
        val mediaId = _state.value.room.mediaItem?.videoId
            ?: _state.value.room.mediaItem?.id
        realtimeClient.sendSyncCommand(
            mediaId = mediaId,
            positionMs = (pos * 1000).toLong(),
            playing = playing,
        )
    }

    fun setDraft(text: String) {
        _state.update { it.copy(draft = text) }
    }

    fun sendMessage() {
        val text = _state.value.draft.trim()
        if (text.isBlank()) return
        realtimeClient.sendChat(text)
        Analytics.messageSent()
        _state.update { it.copy(draft = "") }
    }

    fun leave() {
        hostPushJob?.cancel()
        viewModelScope.launch {
            runCatching { api.leaveRoom(_state.value.room.id) }
            Analytics.roomLeft()
            realtimeClient.disconnect()
        }
    }

    override fun onCleared() {
        hostPushJob?.cancel()
        realtimeClient.disconnect()
        super.onCleared()
    }
}
