//  ModerationViews.swift
//  Plink — M39
//
//  Три экрана, без которых App Review не пропускает UGC-приложения:
//  жалоба, список блокировок и экран принятия правил (EULA) без возможности свайпнуть.

import SwiftUI

struct ReportSheet: View {
    let targetType: ModerationService.TargetType
    let targetId: String
    let targetName: String
    var offerBlock: Bool = true

    @Environment(\.dismiss) private var dismiss
    @StateObject private var moderation = ModerationService.shared
    @State private var reason: ModerationService.Reason?
    @State private var comment = ""
    @State private var alsoBlock = false
    @State private var isSending = false
    @State private var isSent = false

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background.ignoresSafeArea()
                if isSent { successState } else { form }
            }
            .navigationTitle(isSent ? "" : "Пожаловаться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(V4.muted)
                }
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Жалоба на «\(targetName)»")
                    .font(.system(size: 15))
                    .foregroundStyle(V4.muted)

                VStack(spacing: 8) {
                    ForEach(ModerationService.Reason.allCases) { item in
                        Button {
                            Haptics.selection()
                            reason = item
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .frame(width: 22)
                                    .foregroundStyle(reason == item ? V4.accent : V4.muted)
                                Text(item.title)
                                    .font(.system(size: 15))
                                    .foregroundStyle(V4.ink)
                                Spacer()
                                if reason == item {
                                    Image(systemName: "checkmark").foregroundStyle(V4.accent)
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(V4.cardBG))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Комментарий — необязательно")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(V4.muted)
                    TextEditor(text: $comment)
                        .frame(height: 96)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(V4.cardBG))
                        .foregroundStyle(V4.ink)
                }

                if offerBlock && targetType == .user {
                    Toggle(isOn: $alsoBlock) {
                        Text("Также заблокировать")
                            .font(.system(size: 15))
                            .foregroundStyle(V4.ink)
                    }
                    .tint(V4.accent)
                }

                Text("Мы рассматриваем жалобы в течение 24 часов.")
                    .font(.system(size: 12))
                    .foregroundStyle(V4.muted)

                Button {
                    guard let reason else { return }
                    isSending = true
                    Task {
                        await moderation.report(targetType: targetType, targetId: targetId,
                                                reason: reason,
                                                comment: comment.isEmpty ? nil : comment)
                        if alsoBlock && targetType == .user {
                            await moderation.block(userID: targetId)
                        }
                        isSending = false
                        isSent = true
                        Haptics.success()
                    }
                } label: {
                    HStack {
                        if isSending { ProgressView().tint(V4.accentInk) }
                        Text("Отправить жалобу").font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 15).fill(reason == nil ? V4.line : V4.accent))
                    .foregroundStyle(reason == nil ? V4.muted : V4.accentInk)
                }
                .disabled(reason == nil || isSending)
            }
            .padding(18)
        }
    }

    private var successState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(V4.accent)
            Text("Жалоба отправлена")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(V4.ink)
            Text("Мы проверим её в течение 24 часов и сообщим о решении.")
                .font(.system(size: 14))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("Готово") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(V4.accentInk)
                .padding(.horizontal, 26).padding(.vertical, 13)
                .background(Capsule().fill(V4.accent))
        }
    }
}

struct BlockedUsersView: View {
    @StateObject private var moderation = ModerationService.shared

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()
            if moderation.blockedUserIDs.isEmpty {
                EmptyStateView(
                    icon: "hand.raised",
                    title: "Список пуст",
                    message: "Здесь появятся люди, которых вы заблокируете."
                )
            } else {
                List {
                    ForEach(Array(moderation.blockedUserIDs), id: \.self) { id in
                        HStack {
                            Text(id)
                                .font(.system(size: 14))
                                .foregroundStyle(V4.ink)
                            Spacer()
                            Button("Разблокировать") {
                                Task { await moderation.unblock(userID: id) }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(V4.accent)
                        }
                        .listRowBackground(V4.cardBG)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Заблокированные")
        .task { await moderation.refreshBlockedList() }
    }
}

struct EULAGateView: View {
    let onAccept: () -> Void

    private let rules: [(String, String)] = [
        ("hand.raised.slash", "Никакой травли, угроз и ненависти"),
        ("eye.slash", "Никакого контента 18+ и шокового видео"),
        ("c.circle", "Только легальные источники и ваши собственные файлы"),
        ("flag", "Жалобы рассматриваются за 24 часа, нарушители блокируются"),
    ]

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                Text("Правила сообщества")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(V4.ink)
                Text("Перед первым совместным просмотром подтвердите, что согласны с правилами.")
                    .font(.system(size: 15))
                    .foregroundStyle(V4.muted)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(rules, id: \.1) { icon, text in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon)
                                .foregroundStyle(V4.accent)
                                .frame(width: 22)
                            Text(text)
                                .font(.system(size: 14))
                                .foregroundStyle(V4.ink)
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(V4.cardBG))

                Spacer()

                Button {
                    Haptics.success()
                    ModerationService.shared.acceptEULA()
                    onAccept()
                } label: {
                    Text("Принимаю правила")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(V4.accent))
                        .foregroundStyle(V4.accentInk)
                }

                HStack(spacing: 16) {
                    Link("Условия", destination: URL(string: "https://plink.app/terms")!)
                    Link("Конфиденциальность", destination: URL(string: "https://plink.app/privacy")!)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(V4.accent)
                .frame(maxWidth: .infinity)
            }
            .padding(22)
        }
        .interactiveDismissDisabled(true)
    }
}
