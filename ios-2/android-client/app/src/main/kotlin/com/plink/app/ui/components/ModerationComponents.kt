package com.plink.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Bg = Color(0xFF0E1113)
private val Surface = Color(0xFF171B1E)
private val TextPrimary = Color(0xFFECEBEA)
private val TextSecondary = Color(0xFFA6ACAD)
private val Cyan = Color(0xFF2DE2E6)
private val Green = Color(0xFF26D9A4)
private val Danger = Color(0xFFD14B45)

// MARK: - Report Dialog

@Composable
fun ReportDialog(
    userId: String,
    onDismiss: () -> Unit,
    onSubmit: (reason: String, details: String) -> Unit,
) {
    val reasons = listOf(
        "spam" to "Спам",
        "harassment" to "Оскорбления",
        "nsfw" to "Неприемлемый контент",
        "other" to "Другое",
    )
    var selectedReason by remember { mutableStateOf("spam") }
    var details by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Flag, contentDescription = null, tint = Danger, modifier = Modifier.size(24.dp))
                Spacer(Modifier.size(8.dp))
                Text("Пожаловаться", color = TextPrimary, fontWeight = FontWeight.Bold)
            }
        },
        text = {
            Column {
                Text("Причина:", color = TextSecondary, fontSize = 13.sp, modifier = Modifier.padding(bottom = 8.dp))
                reasons.forEach { (value, label) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .selectable(selected = selectedReason == value, onClick = { selectedReason = value })
                            .padding(vertical = 4.dp)
                            .semantics { contentDescription = label },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = selectedReason == value, onClick = { selectedReason = value })
                        Spacer(Modifier.size(8.dp))
                        Text(label, color = TextPrimary)
                    }
                }
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = details,
                    onValueChange = { details = it },
                    placeholder = { Text("Дополнительные детали (опционально)") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                    maxLines = 4,
                )
            }
        },
        confirmButton = {
            Button(
                onClick = { onSubmit(selectedReason, details) },
                colors = ButtonDefaults.buttonColors(containerColor = Danger),
            ) { Text("Отправить") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Отмена", color = TextSecondary) }
        },
        containerColor = Surface,
    )
}

// MARK: - Block Confirmation Dialog

@Composable
fun BlockUserDialog(
    username: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Block, contentDescription = null, tint = Danger, modifier = Modifier.size(24.dp))
                Spacer(Modifier.size(8.dp))
                Text("Заблокировать", color = TextPrimary, fontWeight = FontWeight.Bold)
            }
        },
        text = {
            Text(
                "Заблокировать @$username? Их сообщения больше не будут видны.",
                color = TextSecondary,
                fontSize = 14.sp,
            )
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(containerColor = Danger),
            ) { Text("Заблокировать") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Отмена", color = TextSecondary) }
        },
        containerColor = Surface,
    )
}

// MARK: - Kick Confirmation Dialog (host only)

@Composable
fun KickUserDialog(
    username: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.PersonRemove, contentDescription = null, tint = Danger, modifier = Modifier.size(24.dp))
                Spacer(Modifier.size(8.dp))
                Text("Выгнать из комнаты", color = TextPrimary, fontWeight = FontWeight.Bold)
            }
        },
        text = {
            Text(
                "Выгнать @$username из комнаты? Они не смогут вернуться без нового кода.",
                color = TextSecondary,
                fontSize = 14.sp,
            )
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(containerColor = Danger),
            ) { Text("Выгнать") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Отмена", color = TextSecondary) }
        },
        containerColor = Surface,
    )
}

// MARK: - Message Context Menu (long-press)

@Composable
fun MessageContextMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    isHost: Boolean,
    onReport: () -> Unit,
    onBlock: () -> Unit,
    onKick: () -> Unit,
) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
    ) {
        DropdownMenuItem(
            text = { Text("Пожаловаться", color = TextPrimary) },
            leadingIcon = { Icon(Icons.Default.Flag, contentDescription = null, tint = Danger) },
            onClick = { onDismiss(); onReport() },
        )
        DropdownMenuItem(
            text = { Text("Заблокировать пользователя", color = TextPrimary) },
            leadingIcon = { Icon(Icons.Default.Block, contentDescription = null, tint = Danger) },
            onClick = { onDismiss(); onBlock() },
        )
        if (isHost) {
            DropdownMenuItem(
                text = { Text("Выгнать из комнаты", color = Danger) },
                leadingIcon = { Icon(Icons.Default.PersonRemove, contentDescription = null, tint = Danger) },
                onClick = { onDismiss(); onKick() },
            )
        }
    }
}
