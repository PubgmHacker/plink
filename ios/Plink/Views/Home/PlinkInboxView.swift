// Plink/Views/Home/PlinkInboxView.swift — M17, переписан 04.09.2026
// Колокольчик на главной = СОБЫТИЯ, а не переписка. Заявки в друзья и
// приглашения в комнату — то, на что нужно ответить да/нет, и то, чего
// нет больше нигде в интерфейсе. Сообщения из колокольчика убраны
// намеренно: непрочитанные живут во вкладке «Чаты» и в системном центре
// уведомлений, дублировать их третьим списком незачем — колокольчик
// звенел из-за обычной болтовни и терял смысл.

import SwiftUI

struct PlinkInboxView: View {
    @ObservedObject private var friends = FriendManager.shared
    @ObservedObject private var invites = RoomInviteService.shared
    @Environment(\.dismiss) private var dismiss

    /// Заявка/приглашение, по которым уже идёт запрос: кнопки гаснут, чтобы
    /// один тап не улетел дважды.
    @State private var busyIDs: Set<String> = []
    @State private var toast: String?

    private var requests: [FriendRequest] { friends.incomingRequests }
    private var roomInvites: [RoomInvite] {
        invites.pendingInvites.sorted { $0.timestamp > $1.timestamp }
    }
    private var isEmpty: Bool { requests.isEmpty && roomInvites.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                V4.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        if isEmpty {
                            emptyState
                        } else {
                            if !roomInvites.isEmpty {
                                section(
                                    title: "Приглашения",
                                    subtitle: "Друзья зовут смотреть вместе",
                                    count: roomInvites.count
                                ) {
                                    ForEach(roomInvites) { invite in
                                        inviteRow(invite)
                                        if invite.id != roomInvites.last?.id { rowDivider }
                                    }
                                }
                            }
                            if !requests.isEmpty {
                                section(
                                    title: L.string(.frIncoming),
                                    subtitle: "Ответь — и появится в списке друзей",
                                    count: requests.count
                                ) {
                                    ForEach(requests) { request in
                                        requestRow(request)
                                        if request.id != requests.last?.id { rowDivider }
                                    }
                                }
                            }
                            messagesHint
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)

                if let toast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(V4.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .plinkGlass(.overlay, in: Capsule())
                            .padding(.bottom, 22)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .navigationTitle("События")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(V4.navBG, for: .navigationBar)
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .animation(.plinkLayout, value: requests.map(\.id))
            .animation(.plinkLayout, value: roomInvites.map(\.id))
        }
    }

    // MARK: - Секция

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        subtitle: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(V4.muted)
                Text("\(count)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(V4.accentInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(V4.accent))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(V4.cardBG)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(V4.line, lineWidth: 0.6)
                )

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(V4.muted.opacity(0.8))
                .padding(.horizontal, 4)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(V4.line)
            .frame(height: 0.6)
            .padding(.leading, 68)
    }

    // MARK: - Заявка в друзья

    @ViewBuilder
    private func requestRow(_ request: FriendRequest) -> some View {
        let user = request.fromUser
        let busy = busyIDs.contains(request.id)
        HStack(spacing: 12) {
            PlinkStableAvatar(
                url: PlinkAvatarURL.resolve(userId: user.id, stored: user.avatarURL),
                letter: String(user.displayTitle.prefix(1)).uppercased(),
                size: 44,
                userId: user.id
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(1)
                Text(L.string(.frWantsToAdd))
                    .font(.system(size: 12))
                    .foregroundStyle(V4.muted)
                    .lineLimit(1)
                Text(request.formattedDate)
                    .font(.system(size: 11))
                    .foregroundStyle(V4.muted.opacity(0.65))
            }
            Spacer(minLength: 6)
            VStack(spacing: 6) {
                actionButton(L.string(.frAccept), filled: true, disabled: busy) {
                    Task { await accept(request) }
                }
                actionButton(L.string(.frDecline), filled: false, disabled: busy) {
                    Task { await decline(request) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(busy ? 0.55 : 1)
    }

    // MARK: - Приглашение в комнату

    @ViewBuilder
    private func inviteRow(_ invite: RoomInvite) -> some View {
        let busy = busyIDs.contains(invite.id)
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                PlinkStableAvatar(
                    url: PlinkAvatarURL.resolve(userId: invite.fromUserID, stored: invite.fromAvatarURL),
                    letter: String(invite.fromUsername.prefix(1)).uppercased(),
                    size: 44,
                    userId: invite.fromUserID
                )
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(V4.accentInk)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(V4.accent))
                    .overlay(Circle().stroke(V4.canvas, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(invite.fromUsername)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(1)
                Text(invite.mediaTitle ?? invite.roomName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(V4.muted)
                    .lineLimit(1)
                Text(invite.timestamp.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundStyle(V4.muted.opacity(0.65))
            }
            Spacer(minLength: 6)
            VStack(spacing: 6) {
                actionButton(L.string(.frJoin), filled: true, disabled: busy) {
                    Task { await join(invite) }
                }
                actionButton(L.string(.frDecline), filled: false, disabled: busy) {
                    invites.declineInvite(invite)
                    HapticManager.impact(.light)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(busy ? 0.55 : 1)
    }

    // MARK: - Кнопка ответа

    @ViewBuilder
    private func actionButton(
        _ title: String,
        filled: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(filled ? V4.accentInk : V4.muted)
                .frame(width: 92, height: 30)
                .background(
                    Capsule().fill(filled ? AnyShapeStyle(V4.accent) : AnyShapeStyle(V4.raised.opacity(0.9)))
                )
                .overlay(
                    Capsule().stroke(filled ? Color.clear : V4.line, lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Пусто

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(V4.accent.opacity(0.10))
                    .frame(width: 96, height: 96)
                Image(systemName: "bell.badge.slash")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(V4.muted)
            }
            Text("Пока тихо")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(V4.ink)
            Text("Здесь появятся заявки в друзья и приглашения в комнаты.\nСообщения — во вкладке «Чаты».")
                .font(.system(size: 13))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }

    /// Подсказка внизу непустого списка: человек, который искал переписку в
    /// колокольчике, должен узнать, куда она переехала.
    private var messagesHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V4.muted)
            Text("Сообщения — во вкладке «Чаты»")
                .font(.system(size: 12))
                .foregroundStyle(V4.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(V4.raised.opacity(0.5))
        )
    }

    // MARK: - Действия

    private func reload() async {
        await friends.loadIncomingRequests()
        await invites.refreshFromServer()
    }

    private func accept(_ request: FriendRequest) async {
        busyIDs.insert(request.id)
        await friends.acceptRequest(request)
        busyIDs.remove(request.id)
        HapticManager.impact(.medium)
        show(toast: "\(request.fromUser.displayTitle) теперь в друзьях")
    }

    private func decline(_ request: FriendRequest) async {
        busyIDs.insert(request.id)
        await friends.declineRequest(request)
        busyIDs.remove(request.id)
        HapticManager.impact(.light)
    }

    private func join(_ invite: RoomInvite) async {
        busyIDs.insert(invite.id)
        let room = await invites.acceptInvite(invite)
        busyIDs.remove(invite.id)
        guard let room else {
            HapticManager.errorOccurred()
            show(toast: "Не удалось войти. Комната могла закрыться.")
            return
        }
        HapticManager.impact(.medium)
        dismiss()
        // Пауза = длительность закрытия шита: комната открывается поверх
        // главной, а не поверх исчезающего колокольчика.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
        }
    }

    private func show(toast text: String) {
        withAnimation(.plinkLayout) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.plinkLayout) {
                if toast == text { toast = nil }
            }
        }
    }
}
