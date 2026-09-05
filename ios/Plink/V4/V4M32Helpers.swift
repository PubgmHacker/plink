// Watch history — its own screen, entered from the profile face.
//
// The face keeps only the "What we watched" carousel; this screen is the
// full archive: a period pill and a three-column poster grid grouped by
// day (Today / Yesterday / date), like a gallery. It shows the profile
// owner's server history — the same list the face rail is built from. When
// the server has nothing yet, the device-local history takes over, and only
// then can the list be trimmed ("Clear", "Remove"): the server keeps no
// deletion endpoint for history.

import SwiftUI

struct V4WatchHistorySheet: View {
    var accent: Color
    var accentInk: Color = .white
    /// Server history of the profile owner (what the face rail shows).
    var entries: [UserSocialProfile.WatchHistoryEntry] = []

    @ObservedObject private var manager = WatchHistoryManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var period: PlinkStatsPeriod = .all

    /// One grid cell: a history entry plus local playback progress.
    private struct Cell: Identifiable {
        let entry: UserSocialProfile.WatchHistoryEntry
        let progress: Double?
        /// Local history item behind the cell (nil — server entry).
        let local: WatchHistoryItem?
        var id: String { entry.id }
        var date: Date { entry.watchedAt ?? .distantPast }
    }

    private struct DaySection: Identifiable {
        let day: Date
        let title: String
        let cells: [Cell]
        var id: Date { day }
    }

    private var isLocalMode: Bool { entries.isEmpty }

    private var allCells: [Cell] {
        if !entries.isEmpty {
            return entries.map { Cell(entry: $0, progress: nil, local: nil) }
        }
        return manager.history.map { item in
            Cell(
                entry: UserSocialProfile.WatchHistoryEntry(
                    id: item.id,
                    title: item.title,
                    thumb: item.thumbnailURL,
                    kind: item.mediaType,
                    watchedAt: item.watchedAt,
                    roomId: nil
                ),
                progress: item.progress,
                local: item
            )
        }
    }

    private var sections: [DaySection] {
        let bound = period.lowerBound()
        let cells = allCells
            .filter { bound == nil || $0.date >= bound! }
            .sorted { $0.date > $1.date }
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [Cell]] = [:]
        for cell in cells {
            let day = calendar.startOfDay(for: cell.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(cell)
        }
        return order.map { day in
            DaySection(day: day, title: sectionTitle(for: day, calendar: calendar), cells: buckets[day] ?? [])
        }
    }

    private func sectionTitle(for day: Date, calendar: Calendar) -> String {
        if day == .distantPast || day < Date(timeIntervalSince1970: 0) { return "—" }
        if calendar.isDateInToday(day) { return LocalizationManager.shared.string(.stToday) }
        if calendar.isDateInYesterday(day) { return LocalizationManager.shared.string(.stYesterday) }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: Date())
        return sameYear
            ? day.formatted(.dateTime.day().month(.wide))
            : day.formatted(.dateTime.day().month(.wide).year())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                V4.canvas.ignoresSafeArea()
                RadialGradient(
                    colors: [accent.opacity(0.12), .clear],
                    center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 420
                )
                .ignoresSafeArea()

                if allCells.isEmpty {
                    V4EmptyState(
                        icon: "clock.arrow.circlepath",
                        title: LocalizationManager.shared.string(.stHistoryEmpty),
                        subtitle: LocalizationManager.shared.string(.stHistoryEmptySub),
                        accent: accent,
                        accentInk: accentInk
                    )
                    .padding(.horizontal, 32)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            PlinkPeriodPill(selection: $period, accent: accent, accentInk: accentInk)
                                .padding(.top, 6)
                            let list = sections
                            if list.isEmpty {
                                Text(LocalizationManager.shared.string(.stWatchedEmpty))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(V4.muted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            } else {
                                ForEach(list) { section in
                                    daySection(section)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 40)
                        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: period)
                    }
                }
            }
            .navigationTitle(LocalizationManager.shared.string(.stHistoryTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Close is always on the right (the shared V4 sheet pattern);
                // the destructive "Clear" lives apart from it in the left corner.
                ToolbarItem(placement: .topBarLeading) {
                    if isLocalMode, !manager.history.isEmpty {
                        Button("Очистить") { confirmClear = true }
                            .tint(V4.ink)
                            .accessibilityHint("Удаляет всю историю просмотров")
                    }
                }
                V4SheetCloseToolbarItem { dismiss() }
            }
            .confirmationDialog(
                "Очистить историю просмотров?",
                isPresented: $confirmClear,
                titleVisibility: .visible
            ) {
                Button("Удалить всё", role: .destructive) {
                    HapticManager.impact(.medium)
                    manager.clearAll()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("История хранится только на этом устройстве. Действие нельзя отменить.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func daySection(_ section: DaySection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(section.title)
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(-0.2)
                    .foregroundStyle(V4.ink)
                Text("\(section.cells.count)")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(V4.muted)
                Spacer(minLength: 0)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(section.cells) { cell in
                    PlinkWatchTile(item: cell.entry, accent: accent, progress: cell.progress)
                        // Ячейка висит на верхней кромке ряда. Без этого
                        // LazyVGrid центрирует ячейки по высоте, и сосед с
                        // двухстрочной подписью («Большой кролик Бак»)
                        // поднимал свой постер на 22 pt выше соседей —
                        // верхние кромки плиток в ряду не сходились.
                        .frame(maxHeight: .infinity, alignment: .top)
                        .contextMenu {
                            if let local = cell.local {
                                Button(role: .destructive) {
                                    HapticManager.impact(.light)
                                    manager.remove(local)
                                } label: {
                                    Label("Убрать", systemImage: "trash")
                                }
                            }
                        }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plinkGlass(.control, cornerRadius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(section.title), \(section.cells.count)")
    }
}
