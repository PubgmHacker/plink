package com.plink.app.data.ws

import com.plink.app.data.ApiConfig
import com.plink.app.data.api.PlinkApi
import com.plink.app.data.models.ChatMessage
import com.plink.app.data.models.RealtimeTicketRequest
import com.plink.app.data.sync.RoomPlaybackState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.TimeUnit

data class SessionReady(
    val roomId: String,
    val role: String,
    val serverTimeMs: Long,
)

data class ClockProbeReply(
    val clientSentMs: Long,
    val serverMs: Long,
)

class PlinkRealtimeClient(
    private val api: PlinkApi,
    private val okHttpClient: OkHttpClient,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var webSocket: WebSocket? = null
    private var roomId: String? = null
    private var probeJob: Job? = null

    // Chat written while offline/reconnecting is queued and flushed after
    // the connection is restored (parity with iOS RealtimeClient).
    private val pendingChat = ArrayDeque<String>()
    private val pendingChatLock = Any()

    private val _connected = MutableStateFlow(false)
    val connected: StateFlow<Boolean> = _connected.asStateFlow()

    private val _messages = MutableSharedFlow<ChatMessage>(extraBufferCapacity = 64)
    val messages: SharedFlow<ChatMessage> = _messages.asSharedFlow()

    private val _errors = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val errors: SharedFlow<String> = _errors.asSharedFlow()

    private val _syncStates = MutableSharedFlow<RoomPlaybackState>(extraBufferCapacity = 32)
    val syncStates: SharedFlow<RoomPlaybackState> = _syncStates.asSharedFlow()

    private val _sessionReady = MutableSharedFlow<SessionReady>(extraBufferCapacity = 4)
    val sessionReady: SharedFlow<SessionReady> = _sessionReady.asSharedFlow()

    private val _clockReplies = MutableSharedFlow<ClockProbeReply>(extraBufferCapacity = 16)
    val clockReplies: SharedFlow<ClockProbeReply> = _clockReplies.asSharedFlow()

    private val _participantEvents = MutableSharedFlow<Pair<String, String>>(extraBufferCapacity = 16)
    /** first=joined|left, second=userId */
    val participantEvents: SharedFlow<Pair<String, String>> = _participantEvents.asSharedFlow()

    suspend fun connect(roomId: String) = withContext(Dispatchers.IO) {
        disconnect()
        this@PlinkRealtimeClient.roomId = roomId

        val ticketResponse = api.getRealtimeTicket(RealtimeTicketRequest(roomId))
        val protocols = ticketResponse.protocol.ifEmpty {
            listOf("plink.v2", "plink.ticket.${ticketResponse.ticket}")
        }

        val url = "${ApiConfig.WS_URL}/ws/room/$roomId"
        val request = Request.Builder()
            .url(url)
            .header("Sec-WebSocket-Protocol", protocols.joinToString(", "))
            .build()

        webSocket = okHttpClient.newWebSocket(request, listener)
    }

    fun disconnect() {
        stopClockProbes()
        synchronized(pendingChatLock) { pendingChat.clear() }
        webSocket?.close(1000, "Client disconnect")
        webSocket = null
        roomId = null
        _connected.value = false
    }

    fun sendChat(text: String) {
        val socket = webSocket
        val currentRoomId = roomId ?: return
        if (socket == null || !_connected.value) {
            // Queue while offline — flushed in onOpen
            synchronized(pendingChatLock) {
                if (pendingChat.size >= 50) pendingChat.removeFirst()
                pendingChat.addLast(text)
            }
            return
        }
        val payload = JSONObject().apply {
            put("type", "chat.send")
            put("protocolVersion", 2)
            put("roomId", currentRoomId)
            put("clientMessageId", UUID.randomUUID().toString())
            put("text", text)
        }
        socket.send(payload.toString())
    }

    fun requestState() {
        val socket = webSocket ?: return
        val currentRoomId = roomId ?: return
        if (!_connected.value) return
        socket.send(
            JSONObject().apply {
                put("type", "sync.state.request")
                put("protocolVersion", 2)
                put("roomId", currentRoomId)
                put("afterSeq", 0)
            }.toString(),
        )
    }

    fun sendSyncCommand(
        mediaId: String?,
        positionMs: Long,
        playing: Boolean,
        rate: Double = 1.0,
    ) {
        val socket = webSocket ?: return
        val currentRoomId = roomId ?: return
        if (!_connected.value) return
        socket.send(
            JSONObject().apply {
                put("type", "sync.command")
                put("protocolVersion", 2)
                put("roomId", currentRoomId)
                put("actionId", UUID.randomUUID().toString())
                if (mediaId != null) put("mediaId", mediaId) else put("mediaId", JSONObject.NULL)
                put("positionMs", positionMs.coerceAtLeast(0))
                put("playing", playing)
                put("rate", rate)
            }.toString(),
        )
    }

    private fun startClockProbes() {
        stopClockProbes()
        probeJob = scope.launch {
            while (isActive) {
                val socket = webSocket
                if (socket != null && _connected.value) {
                    socket.send(
                        JSONObject().apply {
                            put("type", "clock.probe")
                            put("protocolVersion", 2)
                            put("clientSentMs", System.currentTimeMillis())
                        }.toString(),
                    )
                }
                delay(5000)
            }
        }
    }

    private fun stopClockProbes() {
        probeJob?.cancel()
        probeJob = null
    }

    private val listener = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            _connected.value = true
            requestState()
            startClockProbes()
            // Flush chat queued while offline
            val queued = synchronized(pendingChatLock) {
                val copy = ArrayList(pendingChat)
                pendingChat.clear()
                copy
            }
            queued.forEach { sendChat(it) }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            scope.launch {
                try {
                    handleServerMessage(JSONObject(text))
                } catch (_: Exception) {
                    _errors.emit("Invalid WebSocket message")
                }
            }
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            _connected.value = false
            stopClockProbes()
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            _connected.value = false
            stopClockProbes()
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            _connected.value = false
            stopClockProbes()
            scope.launch {
                _errors.emit(t.message ?: "WebSocket connection failed")
            }
        }
    }

    private suspend fun handleServerMessage(data: JSONObject) {
        when (data.optString("type")) {
            "session.ready" -> {
                _sessionReady.emit(
                    SessionReady(
                        roomId = data.optString("roomId"),
                        role = data.optString("role", "viewer"),
                        serverTimeMs = data.optLong("serverTimeMs", System.currentTimeMillis()),
                    ),
                )
            }
            "chat.broadcast" -> {
                val message = ChatMessage(
                    id = data.optString("messageId"),
                    senderID = data.optString("senderId").ifBlank {
                        data.optString("senderID")
                    },
                    text = data.optString("text"),
                    createdAt = formatIsoTimestamp(
                        data.optLong("createdAtMs", data.optLong("timestampMs", System.currentTimeMillis())),
                    ),
                    clientMessageId = data.optString("clientMessageId").ifBlank { null },
                )
                _messages.emit(message)
            }
            "sync.state", "sync.state.snapshot" -> {
                val stateObj = data.optJSONObject("state") ?: return
                val state = RoomPlaybackState(
                    protocolVersion = stateObj.optInt("protocolVersion", 2),
                    roomId = stateObj.optString("roomId"),
                    epoch = stateObj.optInt("epoch"),
                    seq = stateObj.optInt("seq"),
                    mediaId = if (stateObj.isNull("mediaId")) null else stateObj.optString("mediaId"),
                    positionMs = stateObj.optLong("positionMs"),
                    playing = stateObj.optBoolean("playing"),
                    rate = stateObj.optDouble("rate", 1.0),
                    effectiveAtServerMs = stateObj.optLong("effectiveAtServerMs"),
                    issuedBy = stateObj.optString("issuedBy"),
                )
                _syncStates.emit(state)
            }
            "clock.probe.reply" -> {
                _clockReplies.emit(
                    ClockProbeReply(
                        clientSentMs = data.optLong("clientSentMs"),
                        serverMs = data.optLong("serverMs"),
                    ),
                )
            }
            "participant.joined" -> {
                _participantEvents.emit("joined" to data.optString("userId"))
            }
            "participant.left" -> {
                _participantEvents.emit("left" to data.optString("userId"))
            }
            "error" -> {
                val error = data.optString("message").ifBlank {
                    data.optString("code", "Realtime error")
                }
                _errors.emit(error)
            }
        }
    }

    companion object {
        fun createOkHttpClient(): OkHttpClient {
            return OkHttpClient.Builder()
                .pingInterval(30, TimeUnit.SECONDS)
                .build()
        }

        private fun formatIsoTimestamp(timestampMs: Long): String {
            return java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
                .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
                .format(java.util.Date(timestampMs))
        }
    }
}
