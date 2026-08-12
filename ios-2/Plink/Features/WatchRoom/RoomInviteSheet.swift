import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - Room Invite Sheet (M14)
// «Пригласить» одной кнопкой: QR-код + шер-линк + копирование кода.
// QR ведёт на https://plink.app/join/<roomId> (universal link из M12).

struct RoomInviteSheet: View {
    let model: WatchRoomModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var accent: Color { PlinkRoomAccent.current }

    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(.white.opacity(0.22)).frame(width: 36, height: 4).padding(.top, 10)

            Text("Пригласить в комнату")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Cinema2026.text)

            if let qr = Self.qrImage(for: model.roomFallbackURL.absoluteString) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("QR-код приглашения")
            }

            VStack(spacing: 4) {
                Text("КОД КОМНАТЫ")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(Cinema2026.secondary)
                Text(model.displayRoomCode)
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                    .foregroundStyle(accent)
            }

            VStack(spacing: 10) {
                ShareLink(item: model.roomShareText) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Поделиться ссылкой")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .simultaneousGesture(TapGesture().onEnded {
                    AnalyticsService.shared.shareRoom()
                    AnalyticsService.shared.inviteFriend()
                    AnalyticsService.shared.funnelInvite()
                })

                Button {
                    UIPasteboard.general.string = model.roomShareText
                    copied = true
                    HapticManager.impact(.light)
                    AnalyticsService.shared.inviteFriend()
                    AnalyticsService.shared.funnelInvite()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Скопировано" : "Скопировать приглашение")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .plinkGlass(.overlay, cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Cinema2026.background.ignoresSafeArea())
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
    }

    static func qrImage(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - P0 5.3: экран пустой комнаты
//
// Самая слабая точка воронки: создал комнату — ты один, чёрный экран,
// приглашение спрятано за тапом и иконкой в верхней панели. Этот оверлей
// показывается, когда в комнате один участник и нет контента: крупная
// кнопка «Позвать друга», друзья онлайн в один тап, подсказка про соло-старт.
// (Живёт в этом файле, а не отдельным: новые .swift не попадают в сборку
// без xcodegen generate — см. project.yml.)

struct RoomEmptyStateView: View {
    let model: WatchRoomModel
    @ObservedObject private var friendManager = FriendManager.shared
    @State private var showInvite = false
    @State private var invitedIds: Set<String> = []

    private var accent: Color { PlinkRoomAccent.current }

    private var onlineFriends: [Friend] {
        friendManager.friends.filter { $0.isOnline && !$0.deleted }
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: "person.3.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 84, height: 84)
                .background(accent.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(accent.opacity(0.25), lineWidth: 1))

            VStack(spacing: 6) {
                Text("Ты в комнате один")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                Text("Позови друзей — смотреть вместе веселее")
                    .font(.system(size: 14))
                    .foregroundStyle(Cinema2026.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                HapticManager.impact(.light)
                showInvite = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                    Text("Позвать друга")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: CompactPhoneMetrics.primaryButtonHeight)
                .background(accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            if !onlineFriends.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("СЕЙЧАС В СЕТИ")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(Cinema2026.secondary)
                        .padding(.horizontal, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(onlineFriends.prefix(12)) { friend in
                                onlineFriendChip(friend)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }

            Text("Можно начать и одному — выбери видео,\nа друзья подтянутся по коду \(model.displayRoomCode)")
                .font(.system(size: 12.5))
                .foregroundStyle(Cinema2026.secondary.opacity(0.85))
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: 420)
        .task {
            await friendManager.loadFriends()
        }
        .sheet(isPresented: $showInvite) {
            RoomInviteSheet(model: model)
        }
    }

    private func onlineFriendChip(_ friend: Friend) -> some View {
        let isInvited = invitedIds.contains(friend.id)
        return Button {
            guard !isInvited else { return }
            HapticManager.impact(.medium)
            invitedIds.insert(friend.id)
            Task {
                await RoomInviteService.shared.sendInvite(
                    to: friend,
                    roomCode: model.displayRoomCode,
                    roomId: model.shareRoomId
                )
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    friendAvatar(friend)
                    Circle()
                        .fill(Color(red: 0.3, green: 0.9, blue: 0.55))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Cinema2026.background, lineWidth: 2))
                }
                Text(isInvited ? "Приглашён ✓" : friend.displayTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isInvited ? accent : Cinema2026.text)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isInvited
            ? "\(friend.displayTitle): приглашение отправлено"
            : "Пригласить \(friend.displayTitle)")
    }

    @ViewBuilder
    private func friendAvatar(_ friend: Friend) -> some View {
        if let urlString = friend.avatarURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                initialsCircle(friend)
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())
        } else {
            initialsCircle(friend)
        }
    }

    private func initialsCircle(_ friend: Friend) -> some View {
        Text(friend.initials)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(accent)
            .frame(width: 52, height: 52)
            .background(accent.opacity(0.14), in: Circle())
    }
}
