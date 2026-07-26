package com.plink.app.data.sync

class ClockSynchronizer {
    data class Sample(val rttMs: Double, val offsetMs: Double)

    private val samples = ArrayDeque<Sample>()
    private val maxSamples = 20
    private val topN = 5

    var offsetMs: Double = 0.0
        private set
    var rttMs: Double = 0.0
        private set
    var probeCount: Int = 0
        private set

    val isSynchronized: Boolean get() = probeCount >= 3

    fun ingest(clientSentMs: Long, serverMs: Long, clientReceivedMs: Long) {
        val rtt = (clientReceivedMs - clientSentMs).coerceAtLeast(0).toDouble()
        val midpoint = clientSentMs + rtt / 2.0
        val offset = serverMs - midpoint
        samples.addLast(Sample(rtt, offset))
        while (samples.size > maxSamples) samples.removeFirst()
        probeCount += 1
        val best = samples.sortedBy { it.rttMs }.take(topN)
        if (best.isEmpty()) return
        val offsets = best.map { it.offsetMs }.sorted()
        offsetMs = offsets[offsets.size / 2]
        rttMs = best.map { it.rttMs }.average()
    }

    fun reset() {
        samples.clear()
        offsetMs = 0.0
        rttMs = 0.0
        probeCount = 0
    }

    val serverNowMs: Long
        get() = System.currentTimeMillis() + offsetMs.toLong()
}
