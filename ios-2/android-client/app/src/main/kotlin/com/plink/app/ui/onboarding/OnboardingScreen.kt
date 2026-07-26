package com.plink.app.ui.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
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
import com.plink.app.data.Analytics
import kotlinx.coroutines.launch

private data class OnboardingStep(val emoji: String, val title: String, val body: String)

private val STEPS = listOf(
    OnboardingStep("▶", "Смотрите вместе", "YouTube, VK, Rutube — синхронно с друзьями. Медиана ~350 мс."),
    OnboardingStep("✦", "AI Companion", "Подскажет, что включить, и поможет создать комнату."),
    OnboardingStep("☾", "Живые темы", "Aurora, Cosmos, Verdant, Magma — атмосфера комнаты в Plink+."),
    OnboardingStep("📱", "Все экраны", "iOS, Android, Mac, Windows — один код комнаты на всех."),
)

private val Bg = Color(0xFF0E1113)
private val TextPrimary = Color(0xFFECEAE3)
private val TextSecondary = Color(0xFFA6ACAE)
private val Cyan = Color(0xFF2DE2E6)
private val Green = Color(0xFF26D9A4)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun OnboardingScreen(onFinish: () -> Unit) {
    val pagerState = rememberPagerState(pageCount = { STEPS.size })
    val scope = rememberCoroutineScope()
    val notifLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) {
        Analytics.onboardingComplete(pagerState.currentPage)
        onFinish()
    }

    LaunchedEffect(pagerState.currentPage) {
        Analytics.onboardingStep(pagerState.currentPage)
    }

    fun finishWithPermission() {
        if (Build.VERSION.SDK_INT >= 33) {
            notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            Analytics.onboardingComplete(pagerState.currentPage)
            onFinish()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Bg)
            .padding(horizontal = 24.dp, vertical = 20.dp),
    ) {
        if (pagerState.currentPage < STEPS.lastIndex) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(
                    onClick = {
                        Analytics.onboardingSkipped(pagerState.currentPage)
                        finishWithPermission()
                    },
                    modifier = Modifier.semantics { contentDescription = "Пропустить онбординг" },
                ) {
                    Text("Пропустить", color = TextSecondary)
                }
            }
        } else {
            Spacer(Modifier.height(48.dp))
        }

        HorizontalPager(
            state = pagerState,
            modifier = Modifier.weight(1f).fillMaxWidth(),
        ) { page ->
            val step = STEPS[page]
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    modifier = Modifier
                        .size(120.dp)
                        .clip(CircleShape)
                        .background(Cyan.copy(alpha = 0.12f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(step.emoji, fontSize = 48.sp)
                }
                Spacer(Modifier.height(28.dp))
                Text(step.title, color = TextPrimary, fontSize = 28.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                Spacer(Modifier.height(12.dp))
                Text(step.body, color = TextSecondary, fontSize = 15.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 12.dp))
            }
        }

        Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), horizontalArrangement = Arrangement.Center) {
            STEPS.indices.forEach { i ->
                Box(
                    Modifier
                        .padding(horizontal = 3.dp)
                        .size(if (i == pagerState.currentPage) 18.dp else 7.dp, 7.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(if (i == pagerState.currentPage) TextPrimary else TextSecondary.copy(0.35f)),
                )
            }
        }

        val isLast = pagerState.currentPage == STEPS.lastIndex
        Button(
            onClick = {
                if (isLast) finishWithPermission()
                else scope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) }
            },
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .semantics { contentDescription = if (isLast) "Начать пользоваться Plink" else "Далее" },
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Brush.horizontalGradient(listOf(Cyan, Green)), RoundedCornerShape(14.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Text(if (isLast) "Начать" else "Далее", color = Bg, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}
