package com.plink.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val TextPrimary = Color(0xFFECEAE3)
private val TextSecondary = Color(0xFFA6ACAE)
private val Cyan = Color(0xFF2DE2E6)
private val Green = Color(0xFF26D9A4)
private val Bg = Color(0xFF0E1113)

@Composable
fun EmptyState(
    icon: String,
    title: String,
    description: String,
    ctaTitle: String? = null,
    onCta: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 32.dp, horizontal = 20.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = "$title. $description"
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            modifier = Modifier
                .size(88.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.04f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(icon, fontSize = 36.sp)
        }
        Spacer(Modifier.height(16.dp))
        Text(title, color = TextPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(description, color = TextSecondary, fontSize = 14.sp, textAlign = TextAlign.Center)
        if (ctaTitle != null && onCta != null) {
            Spacer(Modifier.height(16.dp))
            Button(
                onClick = onCta,
                shape = RoundedCornerShape(999.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
                modifier = Modifier.semantics { contentDescription = ctaTitle },
            ) {
                Box(
                    Modifier
                        .background(Brush.horizontalGradient(listOf(Cyan, Green)), RoundedCornerShape(999.dp))
                        .padding(horizontal = 22.dp, vertical = 12.dp),
                ) {
                    Text(ctaTitle, color = Bg, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                }
            }
        }
    }
}
