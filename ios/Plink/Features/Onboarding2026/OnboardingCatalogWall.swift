// Plink/Features/Onboarding2026/OnboardingCatalogWall.swift
//
// Стена постеров первого экрана онбординга. Три колонки дрейфуют навстречу
// друг другу; постеры — полка Иви, та же, что на Главной
// (V4CinemaCatalog.fetchIviShelf), по сети, без бандла. Пока полка не пришла
// или сети нет — тайлы фирменного градиента, чтобы экран не стоял пустым.
// Границы использования — ios/ART_ASSET_LICENSES.md.

import SwiftUI

struct OnboardingCatalogWall: View {
    /// Выключатель живых постеров: false — только фирменные тайлы, без сети.
    static let usesLivePosters = true

    @State private var posters: [URL] = []
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.plinkFreezeAnimations) private var frozen
    @Environment(\.plinkAccessibilityOverride) private var override

    private let columns = 3
    private let spacing: CGFloat = 10

    private var reduceMotion: Bool { systemReduceMotion || override.reduceMotion || frozen }

    var body: some View {
        GeometryReader { geo in
            let tileWidth = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let tileHeight = tileWidth * 1.5
            let step = tileHeight + spacing
            // Колонка длиннее экрана минимум на один тайл и продублирована:
            // сдвиг в пределах одного цикла никогда не открывает пустоту.
            let perColumn = max(3, Int((geo.size.height / step).rounded(.up)) + 1)
            let cycle = step * CGFloat(perColumn)

            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        let speed: Double = column == 1 ? 9 : 13
                        let travel = CGFloat(fmod(t * speed, Double(cycle)))
                        // Крайние колонки едут вверх, средняя — вниз.
                        let offset = column == 1 ? travel - cycle : -travel
                        VStack(spacing: spacing) {
                            ForEach(0..<(perColumn * 2), id: \.self) { slot in
                                tile(column: column, slot: slot % perColumn,
                                     width: tileWidth, height: tileHeight)
                            }
                        }
                        .offset(y: offset)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.1),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
        }
        .task { await load() }
    }

    // MARK: Тайлы

    @ViewBuilder
    private func tile(column: Int, slot: Int, width: CGFloat, height: CGFloat) -> some View {
        let index = column + slot * columns
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack {
            fallbackTile(index: index)
            if !posters.isEmpty {
                AsyncImage(url: posters[index % posters.count],
                           transaction: Transaction(animation: .easeOut(duration: 0.4))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(PlinkShell.hairline, lineWidth: 1))
    }

    /// Тайл без постера: градиент шелла с фиолетовым отсветом, разным по
    /// фазе, чтобы стена не читалась решёткой одинаковых плиток. Знак — на
    /// каждом третьем, иначе стена превращается в сетку логотипов.
    private func fallbackTile(index: Int) -> some View {
        let phase = Double(index % 5) / 5.0
        return LinearGradient(colors: [PlinkShell.surfaceLift, PlinkShell.surface],
                              startPoint: .top, endPoint: .bottom)
            .overlay(
                RadialGradient(colors: [PlinkShell.accent.opacity(0.2 + phase * 0.16), .clear],
                               center: UnitPoint(x: 0.2 + phase * 0.6, y: 0.25 + phase * 0.5),
                               startRadius: 0, endRadius: 140)
            )
            .overlay {
                if index % 3 == 1 {
                    PlinkBrandMark(size: 30, glow: false).opacity(0.3)
                }
            }
    }

    // MARK: Полка

    /// Источник ссылок на постеры. По умолчанию — живая полка Иви;
    /// DesignAuditShots подменяет его локальными файлами, когда сеть
    /// симулятора слепа (VPN без DNS), чтобы снять стену с настоящими постерами.
    @MainActor static var posterSource: () async -> [URL] = { await liveIviPosters() }

    /// Только Иви и обе полки параллельно — около трёх секунд на холодной
    /// установке. Полный fetchShelf ждёт пул PREMIER (поиск хвоста + 16
    /// страниц), на первом запуске это минуты, а стена нужна к первому экрану.
    static func liveIviPosters() async -> [URL] {
        async let forYou = V4CinemaCatalog.fetchIviShelf(HomeCinemaCatalog.allChip)
        async let fresh = V4CinemaCatalog.fetchIviShelf(HomeCinemaCatalog.freshChip)
        let shelves = [await forYou, await fresh]
        var seen = Set<URL>()
        var urls: [URL] = []
        for item in shelves.joined() {
            guard let url = item.posterURL ?? item.artworkURL, seen.insert(url).inserted else { continue }
            urls.append(url)
        }
        return urls
    }

    @MainActor
    private func load() async {
        guard Self.usesLivePosters, posters.isEmpty else { return }
        let urls = await Self.posterSource()
        guard !urls.isEmpty, !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.5)) { posters = urls }
    }
}
