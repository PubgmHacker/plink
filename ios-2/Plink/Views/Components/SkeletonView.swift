import SwiftUI

// MARK: - Skeleton / Shimmer Loading (M20)
// Показывает прозрачные placeholder-карточки во время загрузки вместо спиннеров.

// MARK: Shimmer effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.35), location: 0.4),
                            .init(color: .white.opacity(0.5), location: 0.5),
                            .init(color: .white.opacity(0.35), location: 0.6),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: phase * geo.size.width * 2)
                    .blendMode(.plusLighter)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Skeleton primitives
struct SkeletonRect: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .shimmer()
    }
}

struct SkeletonCircle: View {
    var size: CGFloat = 40
    var body: some View {
        Circle().fill(Color(.systemGray5)).frame(width: size, height: size).shimmer()
    }
}

// MARK: - Room card skeleton (used in home screen)
struct SkeletonRoomCard: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonRect(width: 64, height: 64, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonRect(height: 14)
                SkeletonRect(width: 120, height: 11)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Group row skeleton (used in groups list)
struct SkeletonGroupRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonCircle(size: 44)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonRect(width: 140, height: 14)
                SkeletonRect(width: 200, height: 11)
            }
            Spacer()
            SkeletonRect(width: 30, height: 11)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Home skeleton (full screen while loading)
struct HomeSkeletonView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero placeholder
                SkeletonRect(height: 200, cornerRadius: 16)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 28)

                // Section header
                HStack {
                    SkeletonRect(width: 130, height: 18)
                    Spacer()
                    SkeletonRect(width: 30, height: 13)
                }
                .padding(.horizontal, 19)
                .padding(.bottom, 12)

                // Horizontal card strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 11) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonRect(width: 160, height: 100, cornerRadius: 12)
                        }
                    }
                    .padding(.horizontal, 19)
                }
                .padding(.bottom, 28)

                // Room list
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonRoomCard()
                }
            }
            .padding(.top, 16)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Groups skeleton
struct GroupsSkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonGroupRow()
                Divider().padding(.leading, 72)
            }
        }
        .allowsHitTesting(false)
    }
}
