package com.plink.app

import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Minimal unit smoke so CI `testDebugUnitTest` is not a no-op.
 * Expand with realtime/join coverage as the Android client matures.
 */
class SmokeTest {
    @Test
    fun packageNameIsPlink() {
        assertTrue(BuildConfig.APPLICATION_ID.contains("plink"))
    }
}
