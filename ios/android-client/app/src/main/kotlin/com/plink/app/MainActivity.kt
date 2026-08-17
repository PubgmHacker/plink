package com.plink.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.plink.app.data.models.Room
import com.plink.app.data.models.User
import com.plink.app.ui.auth.AuthScreen
import com.plink.app.ui.home.HomeScreen
import com.plink.app.ui.profile.ProfileScreen
import com.plink.app.ui.room.RoomScreen
import com.plink.app.ui.theme.PlinkTheme
import com.plink.app.viewmodel.AppViewModelFactory
import com.plink.app.viewmodel.AuthViewModel
import com.plink.app.viewmodel.HomeViewModel
import com.plink.app.viewmodel.ProfileViewModel
import com.plink.app.viewmodel.ProfileViewModelFactory
import com.plink.app.viewmodel.RoomViewModel
import com.plink.app.viewmodel.RoomViewModelFactory

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as PlinkApp).container
        val factory = AppViewModelFactory(container)

        setContent {
            PlinkTheme {
                PlinkRoot(
                    factory = factory,
                    container = container,
                )
            }
        }
    }
}

private sealed interface Screen {
    data object Home : Screen
    data class RoomDetail(val room: Room) : Screen
    data class Profile(val user: User) : Screen
}

@Composable
private fun PlinkRoot(
    factory: AppViewModelFactory,
    container: com.plink.app.di.AppContainer,
) {
    val authViewModel: AuthViewModel = viewModel(factory = factory)
    val authState by authViewModel.state.collectAsState()
    var screen by remember { mutableStateOf<Screen?>(null) }
    var currentUser by remember { mutableStateOf<User?>(null) }

    val user = authState.user ?: currentUser
    if (user == null) {
        AuthScreen(viewModel = authViewModel)
        return
    }
    currentUser = user

    when (val current = screen ?: Screen.Home) {
        Screen.Home -> {
            val homeViewModel: HomeViewModel = viewModel(factory = factory)
            HomeScreen(
                viewModel = homeViewModel,
                onOpenRoom = { room -> screen = Screen.RoomDetail(room) },
                onOpenProfile = { screen = Screen.Profile(user) },
            )
        }
        is Screen.RoomDetail -> {
            val roomViewModel: RoomViewModel = viewModel(
                key = "room-${current.room.id}",
                factory = RoomViewModelFactory(
                    api = container.api,
                    realtimeClient = container.createRealtimeClient(),
                    room = current.room,
                    userId = user.id,
                ),
            )
            RoomScreen(
                viewModel = roomViewModel,
                userId = user.id,
                onLeave = {
                    roomViewModel.leave()
                    screen = Screen.Home
                },
            )
        }
        is Screen.Profile -> {
            val profileViewModel: ProfileViewModel = viewModel(
                factory = ProfileViewModelFactory(
                    api = container.api,
                    user = current.user,
                ),
            )
            ProfileScreen(
                viewModel = profileViewModel,
                onUserUpdate = { updated ->
                    currentUser = updated
                },
                onLogout = {
                    authViewModel.logout()
                    screen = null
                    currentUser = null
                },
                onBack = { screen = Screen.Home },
            )
        }
    }
}