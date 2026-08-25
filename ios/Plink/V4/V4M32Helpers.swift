// История просмотров — свой экран, вход со строки на лице профиля.
//
// Раньше лента медиа-карточек лежала прямо на лице профиля, между хиро и
// разделами. Лицо профиля — идентичность и входы в разделы (модель ВК,
// см. V4ProfileViewLive); контент там выглядел свалкой, а при пустой
// истории на лице постоянно висела серая заглушка. Теперь история — шит
// с полным списком (не prefix(10)), свайп-удалением и «Очистить».

import SwiftUI

struct V4WatchHistorySheet: View {
    let theme: V4Theme
    @ObservedObject private var manager = WatchHistoryManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ZStack {
                V4.canvas.ignoresSafeArea()
                RadialGradient(
                    colors: [theme.accentColor.opacity(0.08), .clear],
                    center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 420
                )
                .ignoresSafeArea()

                if manager.history.isEmpty {
                    V4EmptyState(
                        icon: "clock.arrow.circlepath",
                        title: "Здесь будет история",
                        subtitle: "Всё, что вы посмотрите вместе, соберётся сюда — с прогрессом и датами.",
                        accent: theme.accentColor,
                        accentInk: theme.buttonTextColor
                    )
                    .padding(.horizontal, 32)
                } else {
                    List {
                        ForEach(manager.history) { item in
                            historyRow(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4.5, leading: 18, bottom: 4.5, trailing: 18))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        HapticManager.impact(.light)
                                        manager.remove(item)
                                    } label: {
                                        Label("Убрать", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("История")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Крестик закрытия — всегда справа (единый паттерн шитов V4),
                // деструктивное «Очистить» разнесено с ним в левый угол.
                ToolbarItem(placement: .topBarLeading) {
                    if !manager.history.isEmpty {
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

    private func historyRow(_ item: WatchHistoryItem) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumb = item.thumbnailURL, let url = URL(string: thumb) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            thumbFallback
                        }
                    } else {
                        thumbFallback
                    }
                }
                .frame(width: 118, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                if let progress = item.progress {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule()
                                .fill(theme.accentColor)
                                .frame(width: max(5, g.size.width * progress))
                        }
                    }
                    .frame(width: 102, height: 3)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(V4.line))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.formattedDate)
                    .font(.system(size: 11.5))
                    .foregroundStyle(V4.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V4.cardBG.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(V4.line))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.formattedDate)")
    }

    private var thumbFallback: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(V4.cardBG)
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(V4.muted)
            )
    }
}
