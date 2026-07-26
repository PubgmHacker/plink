
import SwiftUI

// MARK: - ServiceHeroCard
// Large horizontal card for direct-sync services (YouTube, VK, Rutube)
struct ServiceHeroCard: View {
    let service: VideoService
    let kind: ServiceCardKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Brand gradient background
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [service.accentColor.opacity(0.85), service.accentColor.opacity(0.3), .black.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 130)

                // Overlay glass
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.15))
                    .frame(width: 200, height: 130)

                // SYNC badge top-right
                VStack {
                    HStack {
                        Spacer()
                        Text("SYNC")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.2), in: Capsule())
                            .padding(10)
                    }
                    Spacer()
                }
                .frame(width: 200, height: 130)

                // Bottom content
                HStack(alignment: .bottom, spacing: 10) {
                    ServiceLogoView(service: service, size: 38)
                        .shadow(radius: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text(service.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(14)
            }
            .frame(width: 200, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: service.accentColor.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ServiceGridCard
// 2-column card for cinema services (Kinopoisk, Netflix, Okko ...)
struct ServiceGridCard: View {
    let service: VideoService
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 10) {
                    ServiceLogoView(service: service, size: 52)
                        .shadow(radius: 4)

                    Text(service.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(1)

                    Text(service.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Cinema2026.secondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)

                    // "Host subscription" pill
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 8))
                        Text("Host")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Cinema2026.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Cinema2026.accent.opacity(0.12), in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Cinema2026.surface)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [service.accentColor.opacity(0.5), .clear],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                }

                // Glow dot top-right when pre-authorized
                if ServiceAuthStore.hasAccess(to: service.serviceType) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}
