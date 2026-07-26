import SwiftUI

/// Пустые состояния, состояния ошибки и скелетоны загрузки (M39).
/// До M39 экраны при пустых данных показывали просто чёрный фон.

struct EmptyStateView: View {
    let icon: String
    let titleKey: String
    let messageKey: String
    var actionTitleKey: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(V4.raised)
                    .frame(width: 76, height: 76)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(V4.muted)
            }

            Text(LocalizedStringKey(titleKey))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(V4.ink)

            Text(LocalizedStringKey(messageKey))
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(V4.muted)
                .padding(.horizontal, 32)

            if let actionTitleKey, let action {
                Button {
                    Haptics.light()
                    action()
                } label: {
                    Text(LocalizedStringKey(actionTitleKey))
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(V4.accent, in: Capsule())
                        .foregroundStyle(V4.accentInk)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

struct ErrorStateView: View {
    let messageKey: String
    var detail: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(V4.danger)

            Text(LocalizedStringKey(messageKey))
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(V4.ink)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(V4.muted)
                    .padding(.horizontal, 28)
            }

            if let retry {
                Button {
                    Haptics.light()
                    retry()
                } label: {
                    Label(LocalizedStringKey("state.retry"), systemImage: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(V4.raised, in: Capsule())
                        .foregroundStyle(V4.ink)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

/// Полоса «нет сети» поверх контента вместо молчаливого зависания.
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .bold))
            Text(LocalizedStringKey("state.offline"))
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(V4.accentInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(V4.danger)
    }
}

/// Скелетон карточки. Пульсация вместо спиннера — экран не «прыгает» при загрузке.
struct SkeletonCard: View {
    var height: CGFloat = 96
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(V4.raised)
            .frame(height: height)
            .opacity(shimmer ? 0.45 : 0.85)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: shimmer)
            .onAppear { shimmer = true }
    }
}

struct SkeletonList: View {
    var count: Int = 4
    var height: CGFloat = 96

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonCard(height: height)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Бейдж качества синхронизации в комнате.
struct SyncQualityBadge: View {
    let driftMilliseconds: Double
    let quality: ClockSync.Quality

    private var isAligning: Bool { abs(driftMilliseconds) > 120 }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isAligning ? Color.orange : V4.accent)
                .frame(width: 7, height: 7)

            Text(LocalizedStringKey(isAligning ? "sync.aligning" : "sync.inSync"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(V4.ink)

            if !isAligning {
                Text(quality.label)
                    .font(.system(size: 11))
                    .foregroundStyle(V4.muted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(V4.raised.opacity(0.9), in: Capsule())
        .animation(.easeInOut(duration: 0.25), value: isAligning)
    }
}
