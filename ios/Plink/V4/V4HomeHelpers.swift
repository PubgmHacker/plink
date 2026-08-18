// Вспомогательные секции Главной.
// HomeFallbackPlaceholder, FriendsWatchingSection, NewThisWeekSection, TrendingPreviewSheet.

import SwiftUI

enum HomeTitleFilter {
    static let allChip = "Для вас"
    static let chips = ["Для вас", "Новое", "Фантастика", "Аниме", "Хоррор", "Комедии"]

    static func apply(chip: String, items: [V4SearchResult]) -> [V4SearchResult] {
        guard chip != allChip else { return items }
        let needle = chip.lowercased()
        return items.filter {
            $0.title.lowercased().contains(needle) || $0.subtitle.lowercased().contains(needle)
        }
    }

    static func caption(chip: String) -> String {
        chip == allChip
            ? "Чипы ищут слово в названии, это не каталог жанров"
            : "Ищем «\(chip)» в названии — не жанр каталога"
    }
}

// MARK: - Fallback, когда trending пуст
struct HomeFallbackPlaceholder: View {
    let theme: V4Theme
    var openRoom: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(V4.accent)
            Text("Пока тихо")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(V4.ink)
            Text("Подборка обновляется. Найди видео вручную —\nи собери первый вечер кино.")
                .font(.system(size: 12.5))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
            Button {
                HapticManager.impact(.medium)
                openRoom()
            } label: {
                Text("Найти видео")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(V4.accentInk)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(V4.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            // Вход в комнату, когда trending пуст (нет сети / пустая подборка).
            .accessibilityIdentifier("home.emptyFindVideo")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(V4.cardBG.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(V4.line))
        .padding(.horizontal, 19)
    }
}

// MARK: - Друзья онлайн
struct FriendsWatchingSection: View {
    let theme: V4Theme
    var openRoom: () -> Void

    private var onlineFriends: [Friend] {
        FriendManager.shared.friends.filter { $0.isOnline }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Сейчас онлайн")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(V4.ink)
                Spacer()
                if !onlineFriends.isEmpty {
                    Text("\(onlineFriends.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V4.accentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(V4.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 19)

            if onlineFriends.isEmpty {
                Button {
                    HapticManager.impact(.light)
                    openRoom()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2")
                            .foregroundStyle(V4.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Никто из друзей сейчас не онлайн")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(V4.ink)
                            Text("Загляни в комнаты — там всегда что-то идёт")
                                .font(.system(size: 11))
                                .foregroundStyle(V4.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(V4.muted)
                    }
                    .padding(14)
                    .background(V4.cardBG.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(V4.line))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 19)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(onlineFriends.prefix(12), id: \.id) { friend in
                            Button {
                                HapticManager.impact(.light)
                                openRoom()
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Circle()
                                            .fill(V4.raised)
                                            .frame(width: 52, height: 52)
                                            .overlay(
                                                Text(String((friend.displayName ?? friend.username).prefix(1)).uppercased())
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundStyle(V4.accent)
                                            )
                                            .overlay(Circle().stroke(V4.line, lineWidth: 1))
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 12, height: 12)
                                            .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 2))
                                    }
                                    Text(friend.displayName ?? friend.username)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(V4.muted)
                                        .lineLimit(1)
                                }
                                .frame(width: 64)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 19)
                }
            }
        }
    }
}

// MARK: - Новое в Plink
struct NewThisWeekSection: View {
    let theme: V4Theme

    private let items: [(icon: String, title: String, subtitle: String)] = [
        ("sparkles", "Умные подсказки ИИ", "Ассистент сам предлагает, что посмотреть компании"),
        ("qrcode", "Вход в комнату по коду", "Шесть символов — и ты внутри, без ссылок и поиска"),
        ("clock.arrow.circlepath", "История просмотров", "Всё, что вы смотрели вместе — теперь в профиле"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Новое в Plink")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(V4.ink)
                Spacer()
            }
            .padding(.horizontal, 19)

            VStack(spacing: 9) {
                ForEach(items, id: \.title) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(V4.accent)
                            .frame(width: 38, height: 38)
                            .background(V4.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(V4.ink)
                            Text(row.subtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(V4.muted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(V4.cardBG.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(V4.line))
                }
            }
            .padding(.horizontal, 19)
        }
    }
}

// MARK: - Превью перед созданием комнаты
struct TrendingPreviewSheet: View {
    let item: V4SearchResult
    let theme: V4Theme
    var onWatch: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let url = item.artworkURL {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle().fill(V4.cardBG)
                                }
                            } else {
                                Rectangle().fill(V4.cardBG)
                            }
                        }
                        .frame(height: 260)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(14)
                        .accessibilityLabel("Закрыть превью")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("YouTube")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(V4.accentInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(V4.accent, in: Capsule())

                        Text(item.title)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(V4.ink)

                        Text(item.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(V4.muted)

                        Button {
                            HapticManager.impact(.medium)
                            onWatch()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("Смотреть вместе")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(V4.accentInk)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                            .background(V4.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        // Единственная кнопка, которая реально создаёт
                        // комнату из Главной. Без идентификатора UI-смоук
                        // воронки искал «Создать комнату» на самой Главной,
                        // не находил её (такой кнопки в продукте нет) и падал.
                        .accessibilityIdentifier("preview.watchTogether")
                        .padding(.top, 10)

                        Button {
                            dismiss()
                        } label: {
                            Text("Может позже")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(V4.muted)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                                .background(V4.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                }
            }
        }
        .onAppear {
            AnalyticsService.shared.track("home_preview_opened")
        }
    }
}
