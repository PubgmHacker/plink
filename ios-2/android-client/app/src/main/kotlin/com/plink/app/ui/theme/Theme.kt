package com.plink.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColors = darkColorScheme(
    primary = PlinkPurple,
    onPrimary = Color.White,
    secondary = PlinkPurpleDark,
    background = PlinkBackground,
    surface = PlinkSurface,
    onSurface = PlinkOnSurface,
    error = PlinkError,
)

private val LightColors = lightColorScheme(
    primary = PlinkPurple,
    onPrimary = Color.White,
    secondary = PlinkPurpleDark,
)

@Composable
fun PlinkTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}