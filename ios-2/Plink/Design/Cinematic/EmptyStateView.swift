// Shared empty state — Cinema2026 (functional empty UX; no V4 layout changes)

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    var ctaTitle: String? = nil
    var ctaAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Cinema2026.accent)
                .frame(width: 88, height: 88)
                .background(Circle().fill(Color.white.opacity(0.04)))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Cinema2026.text)
                .multilineTextAlignment(.center)
            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Cinema2026.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let ctaTitle, let ctaAction {
                Button(action: ctaAction) {
                    Text(ctaTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Cinema2026.background)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Cinema2026.text, in: Capsule())
                }
                .accessibilityLabel(ctaTitle)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }
}

extension EmptyStateView {
    static func noActiveRooms(create: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(icon: "film", title: "Нет активных комнат",
                       description: "Создай первую комнату из Популярного или войди по коду",
                       ctaTitle: "Создать комнату", ctaAction: create)
    }
    static func trendingError(retry: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(icon: "wifi.slash", title: "Не удалось загрузить",
                       description: "Проверь подключение к интернету",
                       ctaTitle: "Повторить", ctaAction: retry)
    }
    static func noFriends(invite: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(icon: "person.2", title: "Друзей пока нет",
                       description: "Пригласи друзей, чтобы смотреть вместе",
                       ctaTitle: "Пригласить друзей", ctaAction: invite)
    }
    static var noFriendRequests: EmptyStateView {
        EmptyStateView(icon: "envelope.open", title: "Нет запросов",
                       description: "Здесь появятся входящие запросы на дружбу")
    }
    static func noMessages(goFriends: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(icon: "bubble.left.and.bubble.right", title: "Нет сообщений",
                       description: "Начни диалог с другом из раздела Друзья",
                       ctaTitle: "Перейти к друзьям", ctaAction: goFriends)
    }
    static func aloneInRoom(share: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(icon: "person.3", title: "Ты один в комнате",
                       description: "Поделись кодом комнаты с друзьями",
                       ctaTitle: "Поделиться кодом", ctaAction: share)
    }
    static var noChatMessages: EmptyStateView {
        EmptyStateView(icon: "text.bubble", title: "Сообщений пока нет",
                       description: "Напиши первым — начни беседу!")
    }
    static func searchEmpty(goTrending: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(icon: "magnifyingglass", title: "Ничего не найдено",
                       description: "Попробуй другой запрос или выбери из Популярного",
                       ctaTitle: "К популярному", ctaAction: goTrending)
    }
    static func aiEmpty(ask: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(icon: "sparkles", title: "Спроси AI",
                       description: "AI Companion подскажет что посмотреть",
                       ctaTitle: "Что посмотреть?", ctaAction: ask)
    }
}
