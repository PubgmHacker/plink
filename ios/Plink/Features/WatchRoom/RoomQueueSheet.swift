// Plink/Features/WatchRoom/RoomQueueSheet.swift — панель очереди комнаты.
//
// 03.08.2026. До этого очередь жила единственной горизонтальной лентой чипов
// над чатом (WatchChatComposer, M16). На ленте помещалось десять элементов,
// порядок читался только по позиции, а кто поставил ролик — не показывалось
// вовсе. Кнопка «Очередь» в строке управления вела в приглашение, потому что
// открывать было нечего.
//
// Здесь очередь становится настоящим списком: что играет сейчас, кто добавил,
// перетаскивание у хоста и свайп для удаления.
//
// Права: менять порядок и включать ролик может только хост — те же правила на
// сервере (PATCH /rooms/:id/queue, POST .../play), поэтому гостю кнопки и
// ручки перетаскивания не показываем, а не показываем и получаем 403.

import SwiftUI

struct RoomQueueSheet: View {
    @Bindable var model: WatchRoomModel
    @Environment(\.dismiss) private var dismiss

    /// Локальный порядок на время перетаскивания: пока палец держит строку,
    /// список не должен прыгать от входящих бродкастов.
    @State private var draftOrder: [RoomQueueWire.Item] = []
    @State private var isReordering = false

    private var items: [RoomQueueWire.Item] {
        isReordering ? draftOrder : model.roomQueue
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    queueList
                }
            }
            .background(V4.canvas)
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(V4.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Список

    private var queueList: some View {
        List {
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, isNowPlaying: index == 0)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(V4.line)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.removeFromQueue(item)
                                HapticManager.impact(.light)
                            } label: {
                                Label("Убрать", systemImage: "trash")
                            }
                        }
                }
                .onMove(perform: model.isHost ? move : nil)
            } footer: {
                Text(model.isHost
                     ? "Перетащите, чтобы изменить порядок. Смахните влево, чтобы убрать."
                     : "Порядок воспроизведения меняет хост комнаты.")
                    .font(.system(size: 12))
                    .foregroundStyle(V4.muted)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(model.isHost ? .active : .inactive))
    }

    private func row(_ item: RoomQueueWire.Item, isNowPlaying: Bool) -> some View {
        HStack(spacing: 12) {
            // Позиция или индикатор «играет сейчас» — одна колонка фиксированной
            // ширины, чтобы заголовки роликов начинались на одной вертикали.
            ZStack {
                if isNowPlaying {
                    V4GlyphIcon(glyph: .play, size: 13, filled: true)
                        .foregroundStyle(V4.canvas)
                        .frame(width: 26, height: 26)
                        .background(V4.accent, in: Circle())
                } else {
                    Text("\(indexOf(item) + 1)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(V4.muted)
                        .frame(width: 26, height: 26)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: isNowPlaying ? .semibold : .regular))
                    .foregroundStyle(V4.ink)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if isNowPlaying {
                        Text("Играет сейчас")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(V4.accent)
                    } else {
                        Text(item.source)
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    }

                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(V4.muted)

                    Text("добавил \(item.addedBy)")
                        .font(.system(size: 12))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)

                    if item.priority == true {
                        // Молния — поставлено с приоритетом Plink+.
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(V4.amber)
                    }
                }
            }

            Spacer(minLength: 4)

            if model.isHost && !isNowPlaying {
                Button {
                    model.playFromQueue(item)
                    HapticManager.impact(.medium)
                    dismiss()
                } label: {
                    V4GlyphIcon(glyph: .play, size: 14, filled: true)
                        .foregroundStyle(V4.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Включить «\(item.title)» сейчас")
            }
        }
        .padding(.vertical, 5)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            V4GlyphIcon(glyph: .queue, size: 27)
                .foregroundStyle(V4.muted)
                .frame(width: 72, height: 72)
                .plinkGlass(.control, in: Circle())

            Text("Очередь пуста")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(V4.ink)
            Text("Добавьте ролик из поиска или попросите ИИ собрать подборку — он встанет сюда.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(V4.muted)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Позиция и перестановка

    private func indexOf(_ item: RoomQueueWire.Item) -> Int {
        items.firstIndex(where: { $0.id == item.id }) ?? 0
    }

    private func move(from source: IndexSet, to destination: Int) {
        if !isReordering {
            draftOrder = model.roomQueue
            isReordering = true
        }
        draftOrder.move(fromOffsets: source, toOffset: destination)
        HapticManager.selection()
        model.reorderQueue(draftOrder)
        // Отпускаем локальный порядок, когда сервер пришлёт канонический
        // бродкастом. Раньше отпустить — список моргнёт старым порядком.
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { isReordering = false }
        }
    }
}
