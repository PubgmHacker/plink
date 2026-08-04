// Plink/V4/V4AppearanceView.swift — live appearance controls

import SwiftUI
import PhotosUI
import UIKit
import Foundation

extension View {
    func groupStyle() -> some View {
        self
            .padding(.horizontal, 13)
            .background(V4.searchBG)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(V4.line))
            .padding(.horizontal, 19)
            .padding(.bottom, 18)
    }
}

// MARK: - Shared prefs (UserDefaults-backed)

enum PlinkAppearancePrefs {
    static let livingMotionKey = "plink.livingMotion"
    static let highContrastKey = "plink.highContrast"

    static var livingMotion: Bool {
        get {
            if UserDefaults.standard.object(forKey: livingMotionKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: livingMotionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: livingMotionKey)
            NotificationCenter.default.post(name: .plinkAppearancePrefsChanged, object: nil)
        }
    }

    static var highContrast: Bool {
        get { UserDefaults.standard.bool(forKey: highContrastKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: highContrastKey)
            NotificationCenter.default.post(name: .plinkAppearancePrefsChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let plinkAppearancePrefsChanged = Notification.Name("plink.appearancePrefsChanged")
}

// MARK: - Appearance screen

struct V4AppearanceView: View {
    @Binding var theme: V4Theme
    @Binding var presented: Bool
    @State private var selectedLiveTheme: Int? = {
        let idx = UserDefaults.standard.integer(forKey: "plink.liveTheme")
        return idx > 0 ? idx : nil
    }()
    @State private var liveThemeIndex: Int = UserDefaults.standard.integer(forKey: "plink.liveTheme")
    @State private var livingMotion = PlinkAppearancePrefs.livingMotion
    @State private var highContrast = PlinkAppearancePrefs.highContrast
    @State private var showRoomThemes = false
    @State private var selectedBubbleID = PlinkBubbleStylePrefs.currentID
    @State private var selectedWallpaper = PlinkChatWallpaperPrefs.current
    @State private var toast: String?
    @ObservedObject private var premium = PremiumStatusManager.shared
    // M13: contextual paywall instead of a dead-end toast
    @State private var showPlusPaywall = false
    @State private var plusPaywallTrigger: PlinkPlusPaywall.Trigger = .theme

    private var plinkPlusActive: Bool { liveThemeIndex > 0 }
    private var bubbleStyles: [AppearanceDescriptor] { PlinkBubbleStylePrefs.allStyles }

    var body: some View {
        ZStack {
            if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) {
                if let vn = live.videoFileName {
                    MetalVideoBackground(videoName: vn, opacity: 0.45, overlayColor: .black, overlayOpacity: 0.55)
                } else {
                    PlinkPlusStaticGradient(theme: live)
                }
            } else {
                V4LivingBackground(theme: theme)
            }

            // High-contrast veil for readability
            if highContrast {
                Color.black.opacity(0.35).ignoresSafeArea().allowsHitTesting(false)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        V4RoundButton(symbol: "‹") { presented = false }
                        Spacer()
                        Text("Оформление")
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                        Color.clear.frame(width: 43, height: 43)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                    V4Heading(
                        eyebrow: "СТАНДАРТНЫЕ",
                        title: "Живая тема",
                        subtitle: "Одна палитра, разные композиции во всём приложении."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 19)
                    .padding(.bottom, 18)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(V4Theme.allCases) { item in themeCard(item) }
                        }
                        .padding(.horizontal, 19)
                        .padding(.bottom, 15)
                    }

                    V4Heading(
                        eyebrow: "PLINK+",
                        title: "Анимированные темы",
                        subtitle: "Живые видео-фоны. Только для Plink+."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 19)
                    .padding(.top, 20)
                    .padding(.bottom, 18)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(PlinkPlusLiveTheme.allCases) { live in liveThemeCard(live) }
                        }
                        .padding(.horizontal, 19)
                        .padding(.bottom, 15)
                    }

                    // ── Bubble styles ──
                    V4Heading(
                        eyebrow: "ЧАТ",
                        title: "Бабл-стиль сообщений",
                        subtitle: "Так выглядят твои сообщения в чате с другом и в комнате."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 19)
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                    // Live preview
                    HStack {
                        Spacer(minLength: 40)
                        PlinkMessageBubble(
                            text: "Привет! Смотрим вместе 🎬",
                            isOwn: true,
                            styleID: selectedBubbleID,
                            fontSize: PlinkTelegramBubbleMetrics.fontSize
                        )
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(bubbleStyles) { style in
                                bubbleStyleCard(style)
                            }
                        }
                        .padding(.horizontal, 19)
                        .padding(.bottom, 18)
                    }

                    // ── Chat wallpapers (Telegram-style DM backgrounds) ──
                    V4Heading(
                        eyebrow: "ЧАТ С ДРУГОМ",
                        title: "Фон переписки",
                        subtitle: "Как в Telegram — фон только в личных чатах."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 19)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(PlinkChatWallpaper.allCases) { wall in
                                wallpaperCard(wall)
                            }
                        }
                        .padding(.horizontal, 19)
                        .padding(.bottom, 18)
                    }

                    VStack(spacing: 0) {
                        interactiveToggle(
                            title: "Живое движение",
                            detail: "Анимация фона (учитывает «Уменьшить движение»)",
                            isOn: $livingMotion
                        ) { on in
                            PlinkAppearancePrefs.livingMotion = on
                            HapticManager.selection()
                            flashToast(on ? "Живое движение вкл." : "Живое движение выкл.")
                        }

                        interactiveToggle(
                            title: "Больше контраста",
                            detail: "Усиливает подложки текста и читаемость",
                            isOn: $highContrast
                        ) { on in
                            PlinkAppearancePrefs.highContrast = on
                            HapticManager.selection()
                            flashToast(on ? "Контраст усилен" : "Контраст обычный")
                        }

                        Button {
                            HapticManager.impact(.light)
                            showRoomThemes = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Темы комнат")
                                        .font(.system(size: 13.6, weight: .bold))
                                        .foregroundStyle(V4.ink)
                                    Text(premium.selectedRoomTheme.displayName + " · пресеты фона чата")
                                        .font(.system(size: 11.2))
                                        .foregroundStyle(V4.muted)
                                }
                                Spacer()
                                Text("›")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(V4.muted)
                            }
                            .frame(minHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(V4.line).frame(height: 1)
                        }
                    }
                    .groupStyle()

                    Spacer(minLength: 40)
                }
            }
            .foregroundStyle(V4.ink)

            if let toast {
                VStack {
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(V4.surface.opacity(0.95), in: Capsule())
                        .padding(.top, 56)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(40)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkLiveThemeChanged)) { n in
            if let i = n.object as? Int {
                liveThemeIndex = i
                selectedLiveTheme = i > 0 ? i : nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkBubbleStyleChanged)) { n in
            if let id = n.object as? String { selectedBubbleID = id }
        }
        .sheet(isPresented: $showRoomThemes) {
            RoomThemesSheet(
                selected: premium.selectedRoomTheme,
                isPremium: premium.isPremium || premium.canCustomizeRoomTheme
            ) { theme in
                applyRoomTheme(theme)
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPlusPaywall) {
            PlinkPlusPaywall(trigger: plusPaywallTrigger)
        }
    }

    private func applyRoomTheme(_ theme: RoomTheme) {
        if !PremiumStatusManager.isFreeRoomTheme(theme) && !premium.isPremium {
            // M13: show the contextual paywall — a dead-end toast converts nobody
            plusPaywallTrigger = .theme
            showPlusPaywall = true
            HapticManager.errorOccurred()
            return
        }
        premium.setRoomTheme(theme)
        HapticManager.selection()
        flashToast("Тема комнаты: \(theme.displayName)")
        showRoomThemes = false
        NotificationCenter.default.post(name: .plinkAppearancePrefsChanged, object: theme.rawValue)
    }

    private func selectBubbleStyle(_ style: AppearanceDescriptor) {
        if style.premium && !premium.isPremium {
            // M13: show the contextual paywall — a dead-end toast converts nobody
            plusPaywallTrigger = .settings
            showPlusPaywall = true
            HapticManager.errorOccurred()
            return
        }
        selectedBubbleID = style.id
        PlinkBubbleStylePrefs.set(style.id)
        // Аудит 26.07.2026: бабл-стиль уезжает PUT /api/profile/appearance
        // (кросс-девайс); сбой сети — молча остаёмся на локальном выборе.
        AppearanceStore.shared.syncBubbleStyle(style.id)
        HapticManager.selection()
        flashToast("Бабл: \(style.title)")
    }

    private func wallpaperCard(_ wall: PlinkChatWallpaper) -> some View {
        let selected = selectedWallpaper == wall
        return Button {
            selectedWallpaper = wall
            PlinkChatWallpaperPrefs.set(wall)
            HapticManager.selection()
            flashToast("Фон чата: \(wall.title)")
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    LinearGradient(colors: wall.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    // Mini 3D stickers preview
                    HStack(spacing: 4) {
                        ForEach(Array(wall.stickers.prefix(4).enumerated()), id: \.offset) { _, e in
                            Text(e).font(.system(size: 14))
                        }
                    }
                    .offset(y: -6)
                    HStack {
                        Spacer(minLength: 18)
                        Text("Hi")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.35), in: Capsule())
                    }
                    .padding(8)
                    .offset(y: 10)
                }
                .frame(width: 108, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? V4.accent : Color.white.opacity(0.18), lineWidth: selected ? 2.2 : 0.8)
                )
                Text(wall.title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(V4.ink)
                    .lineLimit(1)
            }
            .frame(width: 108)
        }
        .buttonStyle(.plain)
    }

    private func bubbleStyleCard(_ style: AppearanceDescriptor) -> some View {
        let selected = selectedBubbleID == style.id
        let locked = style.premium && !premium.isPremium
        let frame = BubbleFrameModel.resolve(styleID: style.id)
        return Button {
            selectBubbleStyle(style)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Mini TikTok-style frame preview
                ZStack {
                    Text("Привет!")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: frame.fillColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: frame.borderColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: frame.borderWidth
                                )
                        )
                    if frame.isDecorative {
                        let c = frame.cornerEmojis
                        VStack {
                            HStack {
                                if let e = c.tl { Text(e).font(.system(size: 12)) }
                                Spacer(minLength: 0)
                                if let e = c.tr { Text(e).font(.system(size: 12)) }
                            }
                            Spacer(minLength: 0)
                            HStack {
                                if let e = c.bl { Text(e).font(.system(size: 10)) }
                                Spacer(minLength: 0)
                                if let e = c.br { Text(e).font(.system(size: 10)) }
                            }
                        }
                        .padding(2)
                    }
                }
                .frame(minHeight: 48)
                .opacity(locked ? 0.45 : 1)

                Text(style.title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(V4.ink)
                    .lineLimit(1)
                Text(style.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(V4.muted)
                    .lineLimit(2)
                    .frame(height: 24, alignment: .top)

                if style.premium {
                    HStack(spacing: 2) {
                        if locked { Image(systemName: "lock.fill").font(.system(size: 7)) }
                        Text("Plink+").font(.system(size: 8, weight: .heavy))
                    }
                    .foregroundStyle(.yellow)
                }
            }
            .padding(10)
            .frame(width: 108, height: 130, alignment: .topLeading)
            .background(V4.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? V4.accent : V4.line, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func flashToast(_ text: String) {
        withAnimation {
            toast = text
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                withAnimation { toast = nil }
            }
        }
    }

    private func themeCard(_ item: V4Theme) -> some View {
        let (c0, c1, c2, _) = item.colors
        let isSelected = (theme == item) && !plinkPlusActive
        return Button(action: {
            theme = item
            UserDefaults.standard.set(0, forKey: "plink.liveTheme")
            selectedLiveTheme = nil
            NotificationCenter.default.post(name: .plinkLiveThemeChanged, object: 0)
        }) {
            ZStack(alignment: .bottomLeading) {
                c0
                RadialGradient(colors: [c1, .clear], center: UnitPoint(x: 0.25, y: 0.22), startRadius: 0, endRadius: 75)
                RadialGradient(colors: [c2, .clear], center: UnitPoint(x: 0.78, y: 0.75), startRadius: 0, endRadius: 80)
                Text(item.name)
                    .font(.system(size: 10.72, weight: .heavy))
                    .padding(9)
            }
            .frame(width: 112, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? V4.ink : V4.line, lineWidth: isSelected ? 2 : 1)
            )
        }
    }

    private func liveThemeCard(_ live: PlinkPlusLiveTheme) -> some View {
        let index = live.rawValue
        let (bg, c1, c2, c3) = live.colors
        let locked = !premium.isPremium
        return Button {
            if locked {
                flashToast("Анимированные темы — только Plink+")
                HapticManager.errorOccurred()
                return
            }
            selectedLiveTheme = index
            HapticManager.selection()
            UserDefaults.standard.set(index, forKey: "plink.liveTheme")
            theme = live.closestStandardTheme
            NotificationCenter.default.post(name: .plinkLiveThemeChanged, object: index)
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let vn = live.videoFileName,
                   let url = Bundle.main.url(forResource: "\(vn)_preview", withExtension: "png", subdirectory: "LiveThemes"),
                   let data = try? Data(contentsOf: url),
                   let preview = UIImage(data: data) {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    ZStack {
                        bg
                        RadialGradient(colors: [c1, .clear], center: UnitPoint(x: 0.25, y: 0.22), startRadius: 0, endRadius: 75)
                        RadialGradient(colors: [c2, .clear], center: UnitPoint(x: 0.78, y: 0.75), startRadius: 0, endRadius: 80)
                        RadialGradient(colors: [c3, .clear], center: UnitPoint(x: 0.5, y: 0.5), startRadius: 0, endRadius: 60)
                    }
                }
                Text(live.name)
                    .font(.system(size: 10.72, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(9)
                VStack {
                    HStack(spacing: 2) {
                        Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
                        Text("Plink+").font(.system(size: 8, weight: .heavy))
                    }
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(6)
                    Spacer()
                }
            }
            .frame(width: 112, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selectedLiveTheme == index ? V4.ink : V4.line, lineWidth: selectedLiveTheme == index ? 2 : 1)
            )
            .opacity(locked ? 0.55 : 1)
        }
    }

    private func interactiveToggle(
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            onChange(isOn.wrappedValue)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.6, weight: .bold))
                        .foregroundStyle(V4.ink)
                    Text(detail)
                        .font(.system(size: 11.2))
                        .foregroundStyle(V4.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                // Custom switch
                ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn.wrappedValue ? V4.accent : V4.raised)
                        .frame(width: 48, height: 29)
                    Circle()
                        .fill(V4.ink)
                        .frame(width: 23, height: 23)
                        .padding(3)
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isOn.wrappedValue)
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line).frame(height: 1)
        }
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "Вкл" : "Выкл")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Room themes sheet

private struct RoomThemesSheet: View {
    let selected: RoomTheme
    let isPremium: Bool
    var onSelect: (RoomTheme) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Фон чата в комнате просмотра")
                        .font(.system(size: 13))
                        .foregroundStyle(V4.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    ForEach(RoomTheme.allCases) { theme in
                        let locked = !PremiumStatusManager.isFreeRoomTheme(theme) && !isPremium
                        Button {
                            onSelect(theme)
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.chatBackground)
                                    .frame(width: 56, height: 40)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(V4.line, lineWidth: 1)
                                    )
                                    .opacity(locked ? 0.45 : 1)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.displayName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(V4.ink)
                                    Text(theme == .default ? "Базовый · бесплатно" : (locked ? "Только Plink+" : "Пресет комнаты"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(V4.muted)
                                }
                                Spacer()
                                if locked {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.yellow)
                                } else if selected == theme {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(V4.accent)
                                }
                            }
                            .padding(12)
                            .background(
                                (selected == theme ? V4.accent.opacity(0.12) : V4.surface.opacity(0.5)),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(V4.canvas.ignoresSafeArea())
            .navigationTitle("Темы комнат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}
