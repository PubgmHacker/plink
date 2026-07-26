import SwiftUI
import PhotosUI

// MARK: - Profile View v3 (Premium + Edit Profile)
/// Профиль: премиальный хедер, бейдж Premium, статистика, история.
/// Настройки — через шестерёнку.
struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    var onSignOut: () -> Void

    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var showPaywall = false
    @State private var showPhotoPicker = false
    @State private var showCoverPicker = false
    @State private var showFriendsSheet = false  // 🔧 NEW: friends list sheet
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?  // 🔧 NEW: cover photo selection
    @State private var friendManager: FriendManager? = nil
    @State private var ringRotation: Double = 0  // moved from top-level (line 1154)
    @State private var isPremium = false

    init(viewModel: ProfileViewModel, onSignOut: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSignOut = onSignOut
    }

    var body: some View {
        ZStack {
            // 🔧 FIX: plain dark background — NO orbs. Orbs clash with cover photo
            // and avatar. User asked 5-6 times to remove them.
            // Simple deep dark gradient that complements cover/avatar.
            LinearGradient(
                colors: [
                    Color(hex: 0x0A0D14),   // deep dark (top)
                    Color(hex: 0x0D1117),   // slightly lighter (center)
                    Color(hex: 0x0A0D14),   // deep dark (bottom)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Header per spec: 80pt avatar with rotating ring, name 22pt, @ 14pt, email 12pt, badges under username
                    profileHeaderNew

                    // Stats live in edit/personal profile sheet, not the settings list

                    // Grouped cards (RoundedRectangle 14pt)
                    VStack(spacing: 0) {
                        profileCard(title: "Аккаунт", icon: "person.circle", action: { showEditProfile = true })
                        profileCard(title: "Подписка", icon: "crown", action: { showPaywall = true })
                        profileCard(title: "Приложение", icon: "app", action: { showSettings = true })
                        if viewModel.user?.isAdmin == true {
                            profileCard(title: "Админ", icon: "shield", action: { /* open admin */ })
                            if viewModel.user?.isAdmin == true {
                                Button("Тест push") {
                                    Task { /* call /api/dev/test-push */ }
                                }
                                .font(.caption)
                            }
                        }
                        profileCard(title: "Безопасность", icon: "lock", action: { /* security */ })
                    }
                    .background(Cinema2026.raised.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.06), lineWidth: 0.5))

                    // Logout button (red, arrow.right.square.fill)
                    Button(role: .destructive) {
                        onSignOut()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.square.fill")
                            Text(LocalizationManager.shared.string(.prSignOut))
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(.red)
                        .padding()
                        .background(Cinema2026.raised.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 48)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clear, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(loc.string(.profileTitle))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            // 🔧 Pack v3: убрана шестерёнка — настройки в таббаре
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadUser()
            isPremium = PremiumStatusManager.shared.isPremium
            // 🔧 FIX: initialize friendManager so friendsCount works
            if friendManager == nil {
                friendManager = FriendManager(api: apiClient)
                await friendManager?.loadFriends()
            }
        }
        // 🔧 Pack v3: Перезагружаем после EditProfileSheet (ник + аватар)
        .onChange(of: showEditProfile) { _, isShown in
            if !isShown {
                Task {
                    await viewModel.loadUser()
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            // SettingsView was deleted — redirect to NotificationsView
            NavigationStack {
                NotificationsView()
            }
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(viewModel: viewModel)
        }
        // 🔧 NEW: friends list sheet — shows when tapping friends count
        .sheet(isPresented: $showFriendsSheet) {
            NavigationStack {
                FriendsView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text(LocalizationManager.shared.string(.tabFriends))
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPaywall) {
            // M17: единый paywall Plink+ во всём приложении
            PlinkPlusPaywall(trigger: .settings)
                .onDisappear { isPremium = PremiumStatusManager.shared.isPremium }
        }
        // 🔧 v11 (July 2026): REMOVED direct photosPicker handlers from
        // ProfileView. Avatar/cover editing is now ONLY available inside
        // EditProfileSheet (tap 'Редактировать' button). The showPhotoPicker /
        // showCoverPicker / selectedPhotoItem / selectedCoverItem state
        // variables remain declared (for backward-compat with any external
        // callers) but are no longer wired to anything in this view — they
        // were triggering the iOS PhotosPicker sheet which let users change
        // avatar/cover without entering Edit mode, which the user explicitly
        // asked us to prevent.
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 0) {
            // ─── COVER (VK-style, lower height) ───
            // 🔧 VK-STYLE: 150pt (was 180) — VK uses ~140-160pt cover.
            // Lower = avatar sits closer to top, more elegant.
            //
            // 🔧 v11 (July 2026): REMOVED direct camera button from cover.
            // User explicitly requested: 'без нажатия редактировать профиль
            // нельзя поменять аватарку и обложку'. Cover/avatar are now
            // read-only here — editing only via EditProfileSheet (tap
            // 'Редактировать' button below). This avoids accidental taps
            // and keeps the profile header clean.
            ZStack(alignment: .bottomTrailing) {
                if let coverImage = viewModel.coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [
                            Color.bioCyan.opacity(0.6),
                            Color.bioEmerald.opacity(0.5),
                            Color.bioTeal.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 150)
                    .overlay(
                        RadialGradient(
                            colors: [Color.white.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                }

                LinearGradient(
                    colors: [.clear, Color.bioObsidian.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 50)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 150)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // ─── AVATAR (overlapping cover, VK-style) ───
            // 🔧 VK-STYLE: 100pt avatar + 6px ring = 112pt total (was 120+12=132)
            // Smaller avatar = more elegant, matches VK proportions.
            //
            // 🔧 v11 (July 2026): REMOVED direct camera button from avatar.
            // Read-only display here. Editing only via EditProfileSheet.
            ZStack {
                Circle()
                    .fill(Color.bioObsidian)
                    .frame(width: 112, height: 112)
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    .frame(width: 112, height: 112)

                AvatarView(
                    image: viewModel.avatarImage,
                    imageURL: viewModel.avatarURL,
                    username: viewModel.displayName,
                    size: 100,
                    isPremium: isPremium,
                    isAdmin: viewModel.user?.isAdmin ?? false
                )
            }
            .offset(y: -50)  // 🔧 VK-style: avatar overlaps cover (was -60)
            .padding(.bottom, -40)  // compensate (was -50)

            // ─── NAME + EMAIL ───
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    PremiumUsernameText(
                        text: viewModel.displayName,
                        isPremium: isPremium,
                        isAdmin: viewModel.user?.isAdmin ?? false,
                        font: .title2.bold()
                    )
                    if viewModel.user?.isAdmin == true {
                        AdminBadgeChip()
                    }
                }

                Text(viewModel.email)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.raveTextSecondary)
            }
            .padding(.top, 8)

            // ─── EDIT BUTTON ───
            Button { showEditProfile = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                    Text(LocalizationManager.shared.string(.prEditProfile))
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                // 🔧 TELEGRAM-GLASS: убран cyan raveGradient + glow.
                .telegramGlass(cornerRadius: 14, borderColor: .black.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let image = viewModel.avatarImage {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let avatarURL = viewModel.avatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: avatarFallback
                }
            }
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color.ravePrimary, Color.raveAccent],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Text(viewModel.displayName.prefix(2).uppercased())
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Premium Banner (дорогой стиль — без дешёвого gold)

    @ViewBuilder
    private var premiumBanner: some View {
        if isPremium {
            let expiryDate = PremiumStatusManager.shared.subscriptionExpiry ?? Date().addingTimeInterval(30 * 86400)
            let formatter = DateFormatter()
            let _ = { formatter.locale = Locale(identifier: "ru_RU"); formatter.dateFormat = "d MMMM yyyy" }()
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.bioCyan.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundColor(.bioCyan)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizationManager.shared.string(.prPlusActive))
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        
                    Text("Действует до \(formatter.string(from: expiryDate))")
                        .font(.caption)
                        .foregroundColor(.raveTextSecondary)
                }

                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.bioEmerald)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .telegramGlass(cornerRadius: 16, borderColor: Color.bioCyan.opacity(0.25))
        } else {
            Button { showPaywall = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.bioCyan.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(.bioCyan)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizationManager.shared.string(.prGetPlus))
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            
                        Text("20 участников · Приоритет ИИ · Живые темы · Кино-баблы")
                            .font(.caption)
                            .foregroundColor(.raveTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.raveTextSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .telegramGlass(cornerRadius: 16)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Activity Block

    private var activityBlock: some View {
        // 🔧 FIX: only show if there's actual activity (history exists)
        Group {
            if !viewModel.history.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 14))
                            .foregroundColor(.bioCyan)
                        Text(LocalizationManager.shared.string(.prActivity))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.raveTextPrimary)
                    }

                    // Show last watched item
                    if let lastItem = viewModel.history.first {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.bioEmerald.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.bioEmerald)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(lastItem.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.raveTextPrimary)
                                    .lineLimit(1)
                                Text("Просмотрено \(lastItem.formattedDate)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.raveTextSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            statBox(value: "\(viewModel.roomsJoined)", label: loc.string(.profileStatsRooms))
            Divider().frame(height: 40).background(Color.white.opacity(0.06))
            statBox(value: "\(viewModel.hoursWatched)", label: loc.string(.profileStatsHours))
            Divider().frame(height: 40).background(Color.white.opacity(0.06))
            // 🔧 FIX: clickable friends count → navigate to friends
            Button {
                showFriendsSheet = true
            } label: {
                statBox(value: "\(friendManager?.friends.count ?? 0)", label: loc.string(.profileStatsFriends))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 16)
        .telegramGlass(cornerRadius: 18)
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(.raveTextPrimary)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.raveTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Watch History

    @State private var showWatchStats = false

    private var watchHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc.string(.profileHistory))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.raveTextPrimary)
                    
                Spacer()
                if !viewModel.history.isEmpty {
                    // M13: watch-party статистика
                    Button {
                        showWatchStats = true
                    } label: {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.raveTextSecondary)
                    }
                    .sheet(isPresented: $showWatchStats) {
                        WatchStatsView(items: viewModel.history)
                    }
                    Button(loc.string(.profileClear)) { viewModel.clearHistory() }
                        .font(.system(size: 13))
                        .foregroundColor(.raveDanger)
                }
            }

            if viewModel.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(.raveTextTertiary)
                    Text(loc.string(.profileHistoryEmpty))
                        .font(.subheadline)
                        .foregroundColor(.raveTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .telegramGlass(cornerRadius: 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.history) { item in
                            WatchHistoryPoster(item: item) { viewModel.rewatch(item) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.removeHistoryItem(item)
                                    } label: {
                                        Label(loc.string(.delete), systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }
}

// MARK: - Premium Avatar Stroke (пульсирующая ледяной голубой + розовый)
/// Анимированная обводка аватарки для премиум-пользователей.
struct PremiumAvatarStroke: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        AngularGradient(
            colors: [
                Color.bioCyan,
                Color.raveAccent,
                Color(hex: 0x22D3EE),
                Color.raveAccent,
                Color.bioCyan,
            ],
            center: .center
        )
    }
}

// MARK: - Premium Animated Avatar Border
struct PremiumAvatarModifier: ViewModifier {
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .trim(from: 0, to: CGFloat(rotation / 360.0))
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.bioCyan,
                                Color.raveAccent,
                                Color(hex: 0x22D3EE),
                                Color.bioCyan,
                            ],
                            center: .center
                        ),
                        lineWidth: 3.5
                    )
                    .rotationEffect(.degrees(rotation))
            )
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

extension View {
    func premiumAvatarBorder() -> some View {
        modifier(PremiumAvatarModifier())
    }
}

// MARK: - Premium Glow Card Modifier (стеклянное свечение на карточках комнат)
struct PremiumGlowCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .glassCard(cornerRadius: cornerRadius, opacity: 0.06)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [Color.bioCyan.opacity(0.3), Color.raveAccent.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.bioCyan.opacity(0.15), radius: 12, y: 4)
    }
}

extension View {
    func premiumGlowCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(PremiumGlowCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Edit Profile Sheet
/// Изменение имени пользователя.
struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProfileViewModel
    @State private var newUsername = ""
    /// 🔧 v11 (July 2026): Telegram-style display name (separate from @username).
    /// nil/empty means "use @username as display name" (backward compat).
    @State private var newDisplayName = ""
    @State private var isSaving = false
    @State private var isPremium = false
    @State private var showAvatarPicker = false
    @State private var showCoverPicker = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var photosDeniedAlert = false

    init(viewModel: ProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
        _newUsername = State(initialValue: viewModel.username)
        _newDisplayName = State(initialValue: viewModel.user?.displayName ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 🔧 EDIT PROFILE: тёмный минималистичный фон — не яркий ocean.
                // deep dark blue → black, спокойный, без ярких орбов.
                Cinema2026.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // ─── COVER (VK-style, same as ProfileView but smaller) ───
                        ZStack(alignment: .bottomTrailing) {
                            if let coverImage = viewModel.coverImage {
                                Image(uiImage: coverImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 140)
                                    .clipped()
                            } else {
                                LinearGradient(
                                    colors: [
                                        Color.bioCyan.opacity(0.6),
                                        Color.bioEmerald.opacity(0.5),
                                        Color.bioTeal.opacity(0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(height: 140)
                                .overlay(
                                    RadialGradient(
                                        colors: [Color.white.opacity(0.15), .clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 160
                                    )
                                )
                            }

                            LinearGradient(
                                colors: [.clear, Color.bioObsidian.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 45)
                            .frame(maxHeight: .infinity, alignment: .bottom)

                            Button {
                                Task { await openCoverPicker() }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 34, height: 34)
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                        }
                        .frame(height: 140)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        // ─── AVATAR (overlapping cover) ───
                        ZStack {
                            Circle()
                                .fill(Color.bioObsidian)
                                .frame(width: 108, height: 108)
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                .frame(width: 108, height: 108)

                            Button {
                                Task { await openAvatarPicker() }
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    AvatarView(
                                        image: viewModel.avatarImage,
                                        imageURL: viewModel.avatarURL,
                                        username: viewModel.displayName,
                                        size: 96,
                                        isPremium: isPremium,
                                        isAdmin: viewModel.user?.isAdmin ?? false
                                    )

                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.ravePrimary))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .offset(y: -45)
                        .padding(.bottom, -35)

                        // ─── DISPLAY NAME (v11) — FIRST field ───
                        // 🔧 v11 (July 2026): Telegram-style display name shown FIRST.
                        // The human-readable nick shown in chat/profile, separate from
                        // the unique @username tag. Empty = fall back to @username.
                        // Can contain spaces, emoji, any unicode.
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "textformat")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.bioAmber)
                                Text(LocalizationManager.shared.string(.prDisplayName))
                                    .font(.subheadline.bold())
                                    .foregroundColor(.raveTextPrimary)
                                if viewModel.user?.isAdmin == true {
                                    AdminBadgeChip(compact: true)
                                }
                            }
                            Text(LocalizationManager.shared.string(.phDisplayNameHint))
                                .font(.system(size: 11))
                                .foregroundColor(.raveTextTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            TextField("Например: Alex Films", text: $newDisplayName)
                                .textFieldStyle(RaveTextFieldStyle())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.bioAmber.opacity(0.35),
                                                    Color.bioCoral.opacity(0.15)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.5
                                        )
                                )
                        }
                        .padding(.horizontal, 4)

                        // ─── USERNAME FIELD — SECOND field ───
                        // 🔧 v11 (July 2026): @username is now the SECOND field.
                        // Unique tag (like Telegram @username) — latin letters, digits,
                        // underscore, dot only. Max 15 chars. Used for search/deeplinks.
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "at")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.bioCyan)
                                Text("@username (тег)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.raveTextPrimary)
                            }
                            Text(LocalizationManager.shared.string(.phUsernameHint))
                                .font(.system(size: 11))
                                .foregroundColor(.raveTextTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            // 🔧 v11: show current @username
                            Text("Текущий: @\(viewModel.username)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.raveTextTertiary)
                            TextField("например: alex_films", text: $newUsername)
                                .textFieldStyle(RaveTextFieldStyle())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .onChange(of: newUsername) { _, newValue in
                                    // 🔧 v11: enforce latin-only + allowed chars + max 15 chars.
                                    // Allowed: a-z, 0-9, _, . (no spaces, no cyrillic, no symbols).
                                    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")
                                    let cleaned = newValue.lowercased()
                                        .unicodeScalars
                                        .filter { allowed.contains($0) }
                                        .map { String($0) }
                                        .joined()
                                        .prefix(15)  // max 15 chars
                                    newUsername = String(cleaned)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.bioCyan.opacity(0.35),
                                                    Color.bioEmerald.opacity(0.15)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.5
                                        )
                                )
                        }
                        .padding(.horizontal, 4)

                        Spacer(minLength: 20)

                        // ─── SAVE BUTTON ───
                        Button {
                            Task {
                                isSaving = true
                                // 🔧 v11: combined update — username + displayName in one call.
                                // If displayName is empty, backend clears it (uses @username as fallback).
                                await viewModel.updateProfile(username: newUsername, displayName: newDisplayName)
                                isSaving = false
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                Text(isSaving ? "Сохранение…" : "Сохранить")
                                    .font(.headline.bold())
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            // 🔧 FIX: visible gradient button — not transparent glass
                            .background(
                                LinearGradient(
                                    colors: [Color.bioCyan, Color.bioEmerald],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color.bioCyan.opacity(0.4), radius: 8, y: 3)
                        }
                        .disabled(newUsername.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .opacity(newUsername.trimmingCharacters(in: .whitespaces).isEmpty || isSaving ? 0.5 : 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundColor(.bioCyan)
                }
            }
            .task {
                isPremium = PremiumStatusManager.shared.isPremium
            }
            .photosPicker(isPresented: $showAvatarPicker, selection: $selectedAvatarItem, matching: .images)
            .onChange(of: selectedAvatarItem) { _, newItem in
                guard let newItem else { return }
                newItem.loadTransferable(type: Data.self) { result in
                    DispatchQueue.main.async {
                        if case .success(let data?) = result, let img = UIImage(data: data) {
                            viewModel.saveAvatar(img)
                        }
                    }
                }
                selectedAvatarItem = nil
            }
            .photosPicker(isPresented: $showCoverPicker, selection: $selectedCoverItem, matching: .images)
            .onChange(of: selectedCoverItem) { _, newItem in
                guard let newItem else { return }
                newItem.loadTransferable(type: Data.self) { result in
                    DispatchQueue.main.async {
                        if case .success(let data?) = result, let img = UIImage(data: data) {
                            viewModel.saveCover(img)
                        }
                    }
                }
                selectedCoverItem = nil
            }
            .alert("Фото недоступны", isPresented: $photosDeniedAlert) {
                Button("Настройки") { PlinkPermissions.openAppSettings() }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(LocalizationManager.shared.string(.phPhotoLimited))
            }
        }
    }

    /// System permission sheet (first time) → PhotosPicker. PHPicker works even after Deny.
    private func openAvatarPicker() async {
        let access = await PlinkPermissions.preparePhotoPicker()
        switch access {
        case .authorized, .systemPickerOnly:
            try? await Task.sleep(nanoseconds: 150_000_000)
            showAvatarPicker = true
        case .blocked:
            photosDeniedAlert = true
        }
    }

    private func openCoverPicker() async {
        let access = await PlinkPermissions.preparePhotoPicker()
        switch access {
        case .authorized, .systemPickerOnly:
            try? await Task.sleep(nanoseconds: 150_000_000)
            showCoverPicker = true
        case .blocked:
            photosDeniedAlert = true
        }
    }
}

// MARK: - Watch History Poster (вертикальный постер для карусели)
/// Постер 120×170 с прогресс-баром просмотра и названием снизу.
struct WatchHistoryPoster: View {
    let item: WatchHistoryItem
    var onRewatch: () -> Void

    var body: some View {
        Button(action: onRewatch) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottom) {
                    // Постер
                    posterImage
                        .frame(width: 120, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )

                    // Прогресс-бар
                    if let progress = item.progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.black.opacity(0.4)).frame(height: 3)
                                Rectangle().fill(Color.ravePrimary).frame(width: geo.size.width * progress, height: 3)
                            }
                        }
                        .frame(width: 120, height: 3)
                    }

                    // Иконка типа медиа
                    Image(systemName: mediaIcon)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(6)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
                .frame(width: 120, height: 170)

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)

                Text(item.formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(.raveTextSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var mediaIcon: String {
        switch item.mediaType {
        case "movie": return "film"
        case "series": return "tv"
        case "music": return "music.note"
        case "livestream": return "dot.radiowaves.left.and.right"
        default: return "video"
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let urlStr = item.thumbnailURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    posterGradient
                }
            }
        } else {
            posterGradient
        }
    }

    private var posterGradient: some View {
        LinearGradient(
            colors: gradientPalette,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "play.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.6))
        )
    }

    private var gradientPalette: [Color] {
        let palettes: [[Color]] = [
            [Color.ravePrimary.opacity(0.4), .black],
            [Color.raveAccent.opacity(0.4), .black],
            [Color.raveCyan.opacity(0.4), .black],
            [Color.raveWarning.opacity(0.4), .black],
        ]
        return palettes[abs(item.id.hashValue) % palettes.count]
    }
}

// MARK: - Watch History Card (старый — оставлен для совместимости)
struct WatchHistoryCard: View {
    let item: WatchHistoryItem
    var onRewatch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                thumbnail
                    .frame(width: 100, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if let progress = item.progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.4)).frame(height: 3)
                            Rectangle().fill(Color.ravePrimary).frame(width: geo.size.width * progress, height: 3)
                        }
                    }
                    .frame(width: 100, height: 3)
                }
            }
            .frame(width: 100, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(2)
                Text(item.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.raveTextSecondary)
            }

            Spacer()

            Button(action: onRewatch) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundColor(.ravePrimary)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let urlStr = item.thumbnailURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.raveSurface)
                }
            }
        } else {
            Rectangle().fill(Color.raveSurface)
        }
    }
}

// MARK: - P0.2 New Profile Header and Cards (Apple ID / Telegram style)
extension ProfileView {
    var profileHeaderNew: some View {
    VStack(alignment: .leading, spacing: 12) {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: (viewModel.user?.isAdmin ?? false) ? [Color.red, Color.red.opacity(0.6), Color.red] : [Cinema2026.accent, Cinema2026.accent.opacity(0.6), Cinema2026.accent],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 86, height: 86)
                .rotationEffect(.degrees(ringRotation))
                .onAppear {
                    withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { ringRotation = 360 }
                }
            AvatarView(
                image: viewModel.avatarImage,
                imageURL: viewModel.avatarURL,
                username: viewModel.displayName,
                size: 80,
                isPremium: isPremium,
                isAdmin: viewModel.user?.isAdmin ?? false
            )
        }
        .padding(.top, 8)

        Text(viewModel.displayName)
            .font(.system(size: 22, weight: .bold))

        if let username = viewModel.user?.username {
            Text("@\(username)")
                .font(.system(size: 14))
                .foregroundStyle(Cinema2026.secondary)
        }

        if let email = viewModel.user?.email {
            Text(email)
                .font(.system(size: 12))
                .foregroundStyle(Cinema2026.secondary)
        }

        HStack(spacing: 8) {
            if viewModel.user?.isAdmin == true {
                Text(LocalizationManager.shared.string(.prAdmin))
                    .font(.system(size: 10, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.red.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.red)
            }
            if isPremium {
                Text("PLINK+")
                    .font(.system(size: 10, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Cinema2026.accent.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(Cinema2026.accent)
            }
        }
    }
    }
}

// ringRotation moved into ProfileView struct (was top-level — illegal)

private func profileCard(title: String, icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Cinema2026.accent)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(Cinema2026.text)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Cinema2026.secondary)
                .font(.system(size: 14))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    .buttonStyle(.plain)
    .overlay(alignment: .bottom) {
        if title != "Безопасность" {
            Rectangle()
                .fill(Cinema2026.divider.opacity(0.3))
                .frame(height: 0.5)
                .padding(.leading, 48)
        }
    }
}
