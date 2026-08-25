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

// MARK: - Home skeleton (вставляется в уже существующий ScrollView экрана)
//
// 07.08.2026: здесь был собственный вертикальный ScrollView — заглушка
// задумывалась полноэкранной. Но на «Главной» она рисуется внутри её
// ScrollView, а вложенный скролл той же оси теряет предложенную ширину:
// горизонтальная лента ниже отдавала наверх свою полную ширину
// (4×160 + отступы ≈ 710 pt) вместо ширины экрана.
//
// PlinkApprovedV4Root держит все пять вкладок живыми в одном ZStack и гасит
// их через .opacity. ZStack принимает ширину самого широкого ребёнка —
// поэтому растягивался весь экран вместе с таб-баром, а не одна секция.
//
// Скролл здесь не нужен: заглушку не листают, её показывают.
struct HomeSkeletonView: View {
    var body: some View {
        // Формы повторяют реальную сетку витрины (герой 260/29, постеры
        // 128×192 + двухстрочная подпись): заглушка из чужих пропорций
        // (кадр 200/16, полоса 160×100, список комнат) заставляла экран
        // «перепрыгивать» в другую вёрстку в момент загрузки.
        VStack(alignment: .leading, spacing: 0) {
            SkeletonRect(height: 260, cornerRadius: 29)
                .padding(.horizontal, 13)
                .padding(.bottom, 30)

            HStack {
                SkeletonRect(width: 130, height: 18)
                Spacer()
            }
            .padding(.horizontal, 19)
            .padding(.bottom, 12)

            posterStrip
                .padding(.bottom, 26)

            HStack {
                SkeletonRect(width: 110, height: 18)
                Spacer()
            }
            .padding(.horizontal, 19)
            .padding(.bottom, 12)

            posterStrip
        }
        .padding(.top, 16)
        // Страховка: что бы ни выросло внутри, ширина остаётся экранной.
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private var posterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonRect(width: 128, height: 192, cornerRadius: 16)
                        SkeletonRect(width: 104, height: 11, cornerRadius: 4)
                        SkeletonRect(width: 66, height: 9, cornerRadius: 4)
                    }
                }
            }
            .padding(.horizontal, 19)
        }
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
