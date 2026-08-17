package com.plink.app.ui.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.plink.app.data.models.User
import com.plink.app.viewmodel.ProfileViewModel
import java.io.ByteArrayOutputStream

@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel,
    onUserUpdate: (User) -> Unit,
    onLogout: () -> Unit,
    onBack: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    BackHandler { onBack() }

    val picker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.openInputStream(uri)?.use { input ->
                val bytes = input.readBytes()
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                val dataUrl = bitmapToDataUrl(bitmap)
                viewModel.uploadAvatar(dataUrl)
            }
        }
    }

    LaunchedEffect(state.user.id, state.user.avatarURL, state.user.avatarData) {
        onUserUpdate(state.user)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        TextButton(onClick = onBack, modifier = Modifier.align(Alignment.Start)) {
            Text("← Назад")
        }

        Text("Профиль", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(24.dp))

        val avatarModel = state.user.avatarData ?: state.user.avatarURL
        if (!avatarModel.isNullOrBlank()) {
            AsyncImage(
                model = avatarModel,
                contentDescription = state.user.username,
                modifier = Modifier
                    .size(96.dp)
                    .clip(CircleShape),
                contentScale = ContentScale.Crop,
            )
        } else {
            Text(
                text = state.user.username.firstOrNull()?.uppercaseChar().toString(),
                style = MaterialTheme.typography.headlineLarge,
                modifier = Modifier
                    .size(96.dp)
                    .clip(CircleShape)
                    .padding(top = 28.dp),
            )
        }

        Spacer(Modifier.height(16.dp))
        Text(state.user.username, style = MaterialTheme.typography.titleLarge)
        Text("@${state.user.username}", style = MaterialTheme.typography.bodyMedium)
        Text(state.user.email, style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(16.dp))

        Button(
            onClick = { picker.launch("image/*") },
            enabled = !state.uploading,
        ) {
            Text(if (state.uploading) "Загрузка..." else "Сменить аватар")
        }

        state.error?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.error)
        }

        Spacer(Modifier.height(24.dp))
        Button(
            onClick = onLogout,
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error,
            ),
        ) {
            Text("Выйти")
        }
    }
}

private fun bitmapToDataUrl(bitmap: Bitmap): String {
    val output = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, output)
    val base64 = Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
    return "data:image/jpeg;base64,$base64"
}