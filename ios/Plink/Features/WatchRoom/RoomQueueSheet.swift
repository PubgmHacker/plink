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
// 04.09.2026 — по отзыву «окно очереди максимально дешёвое». Системный List с
// серыми ячейками заменён на карточки: у того, что играет сейчас, — свой
// герой-блок с кадром и акцентной рамкой, у остальных — плиты с превью,
// номером, значком сервиса и одной кнопкой «включить». Пустое состояние
// перестало быть надписью посреди пустоты: три призрачных слота показывают,
// куда встанут ролики. Перетаскивание осталось на List — только он даёт
// настоящий drag-reorder, но строки больше не выглядят системными.
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
    private var nowPlaying: RoomQueueWire.Item? { items.first }
    private var upNext: [RoomQueueWire.Item] { Array(items.dropFirst()) }

    var body: some View {
        NavigationStack {
            ZStack {
                V4.canvas.ignoresSafeArea()
                if items.isEmpty {
                    emptyState
                } else {
                    queueList
                }
            }
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(V4.navBG, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
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
            if let nowPlaying {
                Section {
                    nowPlayingCard(nowPlaying)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                        .moveDisabled(true)
                        .deleteDisabled(true)
                }
            }

            Section {
                ForEach(upNext) { item in
                    row(item)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        // У хоста List забирает справа свой жёлоб под ручку
                        // перетаскивания. С отступом 16 замер по снимку
                        // 22-room-queue-host давал 17,5 pt чёрной пустоты
                        // между кромкой карточки (337 pt) и ручкой (354,5 pt)
                        // — ручка висела сама по себе, будто её забыли убрать.
                        // Отступ 6 подводит карточку к 347 pt: ручка садится
                        // вплотную и читается как хват этой строки. Гостю
                        // жёлоба нет, ему нужны прежние 16.
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4,
                                                  trailing: model.isHost ? 6 : 16))
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
            } header: {
                if !upNext.isEmpty {
                    HStack(spacing: 8) {
                        Text("Дальше")
                            .font(.system(size: 12, weight: .heavy))
                            .kerning(0.7)
                            .textCase(.uppercase)
                            .foregroundStyle(V4.muted)
                        Text("\(upNext.count)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(V4.accentInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(V4.accent))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            } footer: {
                Text(model.isHost
                     ? "Перетащите, чтобы изменить порядок. Смахните влево, чтобы убрать."
                     : "Порядок воспроизведения меняет хост комнаты.")
                    .font(.system(size: 12))
                    .foregroundStyle(V4.muted)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    // Подвал секции — тоже строка списка, и plain-List вешал
                    // под ним свой разделитель: на снимке под подсказкой жила
                    // одинокая серая линия, единственная во всей панели.
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .environment(\.editMode, .constant(model.isHost ? .active : .inactive))
    }

    // MARK: - Что играет сейчас

    private func nowPlayingCard(_ item: RoomQueueWire.Item) -> some View {
        HStack(spacing: 12) {
            thumb(item, width: 104, height: 60)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    // Пульсирующая точка вместо слова «сейчас» рядом с
                    // текстом: взгляд ловит её раньше, чем читает подпись.
                    Circle()
                        .fill(V4.accent)
                        .frame(width: 6, height: 6)
                    Text("В эфире")
                        .font(.system(size: 10, weight: .heavy))
                        .kerning(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(V4.accent)
                }
                Text(item.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                metaLine(item)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(V4.cardBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(V4.accent.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Строка очереди

    private func row(_ item: RoomQueueWire.Item) -> some View {
        HStack(spacing: 11) {
            Text("\(indexOf(item) + 1)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(V4.muted)
                .frame(width: 20)
                .monospacedDigit()

            thumb(item, width: 74, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                metaLine(item)
            }

            Spacer(minLength: 2)

            if model.isHost {
                Button {
                    model.playFromQueue(item)
                    HapticManager.impact(.medium)
                    dismiss()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(V4.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(V4.accent.opacity(0.14)))
                        .overlay(Circle().stroke(V4.accent.opacity(0.30), lineWidth: 0.8))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Включить «\(item.title)» сейчас")
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(V4.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(V4.line, lineWidth: 0.6)
        )
    }

    /// Подпись «сервис · кто добавил» плюс молния приоритета Plink+.
    private func metaLine(_ item: RoomQueueWire.Item) -> some View {
        HStack(spacing: 5) {
            if let service = service(for: item) {
                ServiceLogoView(service: service, size: 13)
                Text(service.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(V4.muted)
            } else {
                Text(item.source)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(V4.muted)
            }
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(V4.muted.opacity(0.6))
            Text(item.addedBy)
                .font(.system(size: 11))
                .foregroundStyle(V4.muted.opacity(0.85))
                .lineLimit(1)
            if item.priority == true {
                // Молния — поставлено с приоритетом Plink+.
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(V4.amber)
            }
        }
    }

    // MARK: - Превью кадра

    /// Кадр ролика. У YouTube он публичный и бесплатный, поэтому очередь
    /// выглядит как очередь, а не как список ссылок. Остальные сервисы не дают
    /// превью по URL — вместо битой картинки рисуем плиту с их знаком, это
    /// честнее и не мигает серым при загрузке.
    @ViewBuilder
    private func thumb(_ item: RoomQueueWire.Item, width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack {
            shape.fill(V4.raised.opacity(0.9))
            if let url = youtubeThumb(item.streamURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        serviceTile(item)
                    }
                }
            } else {
                serviceTile(item)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.08), lineWidth: 0.6))
    }

    @ViewBuilder
    private func serviceTile(_ item: RoomQueueWire.Item) -> some View {
        if let service = service(for: item) {
            ZStack {
                LinearGradient(
                    colors: [service.accentColor.opacity(0.35), service.accentColor.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                ServiceLogoView(service: service, size: 22)
            }
        } else {
            Image(systemName: "film")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(V4.muted)
        }
    }

    private func service(for item: RoomQueueWire.Item) -> VideoService? {
        if let direct = VideoService(rawValue: item.source.lowercased()) { return direct }
        let url = item.streamURL.lowercased()
        if url.contains("youtu") { return .youtube }
        if url.contains("rutube") { return .rutube }
        if url.contains("vk.com") || url.contains("vkvideo") { return .vk }
        if url.contains("ivi.ru") { return .ivi }
        return nil
    }

    /// `youtu.be/<id>`, `watch?v=<id>`, `embed/<id>`, `shorts/<id>` — четыре
    /// формы, которыми ролик попадает в очередь.
    private func youtubeThumb(_ streamURL: String) -> URL? {
        guard let id = youtubeID(streamURL) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }

    private func youtubeID(_ raw: String) -> String? {
        guard let url = URL(string: raw), let host = url.host?.lowercased() else { return nil }
        let isYouTube = host.contains("youtube.com") || host.contains("youtu.be")
        guard isYouTube else { return nil }
        var candidate: String?
        if host.contains("youtu.be") {
            candidate = url.pathComponents.dropFirst().first
        } else if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value {
            candidate = v
        } else {
            let parts = url.pathComponents.dropFirst()
            if let marker = parts.firstIndex(where: { $0 == "embed" || $0 == "shorts" || $0 == "v" }),
               parts.indices.contains(marker + 1) {
                candidate = parts[marker + 1]
            }
        }
        guard let id = candidate, id.count == 11,
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }

    // MARK: - Пусто

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(V4.accent.opacity(0.10))
                    .frame(width: 108, height: 108)
                    .blur(radius: 6)
                V4GlyphIcon(glyph: .queue, size: 27)
                    .foregroundStyle(V4.ink.opacity(0.75))
                    .frame(width: 76, height: 76)
                    .plinkGlass(.control, in: Circle())
            }

            Text("Очередь пуста")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(V4.ink)
                .padding(.top, 16)

            Text("Добавьте ролик из поиска или попросите ИИ собрать подборку — он встанет сюда и включится следующим.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(V4.muted)
                .padding(.horizontal, 34)
                .padding(.top, 7)
                .fixedSize(horizontal: false, vertical: true)

            // Три призрачных слота: пустое окно объясняет форму будущего
            // списка, а не просто сообщает, что смотреть нечего.
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    ghostSlot(index: i)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)

            Spacer(minLength: 16)
        }
    }

    private func ghostSlot(index: Int) -> some View {
        HStack(spacing: 11) {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(V4.muted.opacity(0.35))
                .frame(width: 20)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(V4.raised.opacity(0.45))
                .frame(width: 74, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                Capsule()
                    .fill(V4.raised.opacity(0.55))
                    .frame(width: index == 1 ? 96 : 132, height: 9)
                Capsule()
                    .fill(V4.raised.opacity(0.35))
                    .frame(width: 64, height: 7)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(V4.surface.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(V4.line, style: StrokeStyle(lineWidth: 0.8, dash: [5, 4]))
        )
        .opacity(1.0 - Double(index) * 0.22)
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
        // Секция «Дальше» начинается со второго элемента очереди: индексы из
        // ForEach нужно сдвинуть на играющий сейчас, иначе перетаскивание
        // переставляет не то, что тянут.
        let shifted = IndexSet(source.map { $0 + 1 })
        draftOrder.move(fromOffsets: shifted, toOffset: destination + 1)
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
