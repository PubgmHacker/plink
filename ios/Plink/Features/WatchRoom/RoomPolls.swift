// Room polls («что смотрим дальше?»)
//
// Polls ride on the existing chat protocol: a poll event is a chat message
// whose text starts with RoomPollWire.marker followed by a JSON payload.
// Clients that understand the marker render a poll card instead of a chat
// bubble (the message is intercepted in WatchRoomModel.handleChatBroadcast
// before normal chat handling). No backend changes required — the gateway
// relays chat text verbatim, and old clients simply show a short odd message.

import SwiftUI

// MARK: - Wire format

public enum RoomPollWire {
    /// INVISIBLE SEPARATOR guards make accidental collisions with user text impossible.
    public static let marker = "\u{2063}plink.poll\u{2063}"

    public struct Event: Codable, Sendable {
        public enum Kind: String, Codable, Sendable { case create, vote, close }
        public var kind: Kind
        public var pollId: String
        public var question: String?
        public var options: [String]?
        public var optionIndex: Int?
    }

    public static func encode(_ event: Event) -> String? {
        guard let data = try? JSONEncoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return marker + json
    }

    public static func decode(_ text: String) -> Event? {
        guard text.hasPrefix(marker) else { return nil }
        let json = String(text.dropFirst(marker.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Event.self, from: data)
    }
}

// MARK: - State

public struct RoomPollState: Equatable, Sendable {
    public var id: String
    public var question: String
    public var options: [String]
    /// userId → chosen option index (server relays every client's vote event).
    public var votes: [String: Int] = [:]
    public var createdBy: String
    public var createdByName: String
    public var isClosed = false

    public func voteCount(for index: Int) -> Int {
        votes.values.filter { $0 == index }.count
    }

    public var totalVotes: Int { votes.count }
}

// MARK: - Poll card (overlay in the room)

/// Карточка голосования поверх кадра. Переписана 04.09.2026: раньше это была
/// серая полоска на 18 % белого — «дешёвое и несовременное» окно из отзыва.
/// Теперь у неё акцентная шкала с процентами, победитель после закрытия и
/// счётчик голосов, а сама карточка не спорит с фильмом: стекло, не плита.
struct RoomPollCard: View {
    let poll: RoomPollState
    let myUserId: String
    let canClose: Bool
    let onVote: (Int) -> Void
    let onClose: () -> Void
    let onDismiss: () -> Void

    private var myVote: Int? { poll.votes[myUserId] }
    private var showResults: Bool { myVote != nil || poll.isClosed }
    /// Индекс победителя — только у закрытого голосования и только если он один.
    private var winner: Int? {
        guard poll.isClosed, poll.totalVotes > 0 else { return nil }
        let counts = poll.options.indices.map { poll.voteCount(for: $0) }
        guard let best = counts.max() else { return nil }
        let leaders = counts.indices.filter { counts[$0] == best }
        return leaders.count == 1 ? leaders[0] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(poll.question)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 7) {
                ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                    pollOptionRow(index: index, option: option)
                }
            }

            footer
        }
        .padding(16)
        // Тёмный пол под содержимым. Карточку рисовали и смотрели на тёмных
        // кадрах, а над светлым планом стекло её теряет: замер снимка
        // 23-room-poll-open дал подпись «3 голоса» на 1.60:1 к своей же
        // подложке, а сам вопрос — 2.76:1. Пелена внутри стекла держит пол
        // независимо от кадра; стеклом карточка при этом быть не перестаёт —
        // размытие под пеленой то же, и на тёмном кадре её не видно вовсе.
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.42))
        )
        .plinkGlass(.overlay, cornerRadius: 22)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .animation(.plinkLayout, value: poll.votes)
        .animation(.plinkLayout, value: poll.isClosed)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: poll.isClosed ? "checkmark.seal.fill" : "chart.bar.xaxis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(poll.isClosed ? V4.free : V4.accent)
            Text(poll.isClosed ? "Голосование завершено" : "Голосование")
                .font(.system(size: 11, weight: .heavy))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            if !poll.isClosed {
                // Замер по 23-room-poll-open: 0.45 давало 3.54:1 — для 11 pt
                // нужно 4.5:1. Имя автора — не декор, по нему понимают, кого
                // просить закрыть голосование. 0.45 → 0.62.
                Text(poll.createdByName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if canClose && !poll.isClosed {
                Button("Завершить") { onClose() }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .buttonStyle(.plain)
            }
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(0.10)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .plinkHitTarget(24)
            .accessibilityLabel("Скрыть голосование")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if poll.totalVotes > 0 {
            Text(votesWord(poll.totalVotes))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
        } else if !poll.isClosed {
            Text("Голосов пока нет — выберите вариант")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private func votesWord(_ n: Int) -> String {
        let tail = n % 100
        if tail >= 11 && tail <= 14 { return "\(n) голосов" }
        switch n % 10 {
        case 1: return "\(n) голос"
        case 2, 3, 4: return "\(n) голоса"
        default: return "\(n) голосов"
        }
    }

    @ViewBuilder
    private func pollOptionRow(index: Int, option: String) -> some View {
        let count = poll.voteCount(for: index)
        let fraction = poll.totalVotes > 0 ? Double(count) / Double(poll.totalVotes) : 0
        let mine = myVote == index
        let won = winner == index
        Button {
            guard !poll.isClosed, myVote == nil else { return }
            HapticManager.impact(.light)
            onVote(index)
        } label: {
            ZStack(alignment: .leading) {
                // Шкала — акцент, а не белая заливка: у процента появился цвет,
                // и выбранный вариант виден, не считая цифры.
                if showResults {
                    GeometryReader { geo in
                        // Шкала живёт только слева от колонки цифр. Раньше она
                        // мерилась от полной ширины строки, и её кромка заезжала
                        // под проценты: замер снимка 23-room-poll-open дал заливку
                        // до 277 pt при цифрах с 282 pt — 5 pt зазора, а на доле
                        // 77…98 % (обычный расклад 4:1) кромка садится ровно на
                        // глиф. Колонка цифр — 86 pt: «100 %» плюс счётчик плюс
                        // галочка своего голоса. Шкала мерится от остатка, поэтому
                        // 100 % по-прежнему заполняет дорожку целиком.
                        let lane: CGFloat = 86
                        let track = max(0, geo.size.width - lane)
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: won
                                        ? [V4.free.opacity(0.55), V4.free.opacity(0.28)]
                                        : mine
                                            ? [V4.accent.opacity(0.60), V4.accent.opacity(0.30)]
                                            : [.white.opacity(0.16), .white.opacity(0.08)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            // Ноль голосов — ноль шкалы. Прежние 3 pt оставляли у
                            // левого края огрызок заливки, и на снимке он читался
                            // как артефакт отрисовки, а не как «голосов нет».
                            .frame(width: max(track * fraction, fraction > 0 ? 34 : 0))
                    }
                }
                HStack(spacing: 8) {
                    Text(option)
                        .font(.system(size: 14, weight: mine || won ? .bold : .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if won {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(V4.amber)
                    }
                    Spacer(minLength: 4)
                    if showResults {
                        // Процент проигравшей опции мерился 4.31:1 при 0.7 —
                        // ниже 4.5:1. Цифра результата обязана читаться у всех
                        // вариантов, иначе «0 %» выглядит выключенным. 0.7 → 0.8.
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white.opacity(mine || won ? 0.95 : 0.8))
                            .monospacedDigit()
                        Text("\(count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .monospacedDigit()
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    if mine {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 40)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(mine ? V4.accent.opacity(0.5) : .white.opacity(0.08), lineWidth: mine ? 1 : 0.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option)
        .accessibilityValue(showResults ? "\(count), \(Int((fraction * 100).rounded())) процентов" : "не выбрано")
    }
}

// MARK: - Composer

/// Окно создания голосования. Было системной `Form` со серыми ячейками —
/// в отзыве 02.09 его назвали «максимально дешёвым и несовременным». Стало
/// своим экраном на токенах комнаты: подсказки-заготовки вопроса, варианты
/// с номерами и удалением, живой предпросмотр карточки и одна кнопка-пилюля.
struct PollComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options: [String] = ["", ""]
    @FocusState private var focus: Field?
    let onCreate: (String, [String]) -> Void

    private enum Field: Hashable { case question, option(Int) }

    private static let presets = [
        "Что смотрим дальше?",
        "Ставим на паузу?",
        "Перематываем?",
        "Меняем фильм?"
    ]

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var filledOptions: [String] {
        options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var canCreate: Bool { !trimmedQuestion.isEmpty && filledOptions.count >= 2 }

    var body: some View {
        NavigationStack {
            ZStack {
                V4.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        questionBlock
                        optionsBlock
                        previewBlock
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                VStack {
                    Spacer()
                    createButton
                }
            }
            .navigationTitle("Голосование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(V4.navBG, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(V4.muted)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    // MARK: Вопрос

    private var questionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            blockTitle("Вопрос")
            ZStack(alignment: .leading) {
                if question.isEmpty {
                    Text("Что смотрим дальше?")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(V4.muted.opacity(0.55))
                }
                TextField("", text: $question, axis: .vertical)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .tint(V4.accent)
                    .focused($focus, equals: .question)
                    .submitLabel(.next)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(V4.surface.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(focus == .question ? V4.accent.opacity(0.55) : V4.line, lineWidth: 0.8)
            )

            // Заготовки: в комнате голосуют на бегу, печатать вопрос целиком
            // никто не станет.
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { preset in
                        Button {
                            question = preset
                            HapticManager.impact(.light)
                        } label: {
                            Text(preset)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(question == preset ? V4.accentInk : V4.muted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(question == preset ? V4.accent : V4.raised.opacity(0.7))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Варианты

    private var optionsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                blockTitle("Варианты")
                Spacer()
                Text("\(filledOptions.count) из 4")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(V4.muted.opacity(0.7))
                    .monospacedDigit()
            }

            VStack(spacing: 8) {
                ForEach(options.indices, id: \.self) { i in
                    optionRow(i)
                }
            }

            if options.count < 4 {
                Button {
                    withAnimation(.plinkLayout) { options.append("") }
                    focus = .option(options.count - 1)
                    HapticManager.impact(.light)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .black))
                        Text("Ещё вариант")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(V4.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(V4.accent.opacity(0.12)))
                    .overlay(Capsule().stroke(V4.accent.opacity(0.28), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func optionRow(_ i: Int) -> some View {
        let focused = focus == .option(i)
        HStack(spacing: 10) {
            Text("\(i + 1)")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(options[i].isEmpty ? V4.muted : V4.accentInk)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(options[i].isEmpty ? V4.raised.opacity(0.8) : V4.accent)
                )
            ZStack(alignment: .leading) {
                if options[i].isEmpty {
                    Text(i == 0 ? "Например, «Продолжаем»" : "Например, «Другой фильм»")
                        .font(.system(size: 15))
                        .foregroundStyle(V4.muted.opacity(0.5))
                        .lineLimit(1)
                }
                TextField("", text: $options[i])
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(V4.ink)
                    .tint(V4.accent)
                    .focused($focus, equals: .option(i))
                    .submitLabel(i == options.count - 1 ? .done : .next)
            }
            if options.count > 2 {
                Button {
                    withAnimation(.plinkLayout) { options.remove(at: i) }
                    HapticManager.impact(.light)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(V4.muted.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Убрать вариант \(i + 1)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(V4.surface.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(focused ? V4.accent.opacity(0.55) : V4.line, lineWidth: 0.8)
        )
    }

    // MARK: Предпросмотр

    @ViewBuilder
    private var previewBlock: some View {
        if canCreate {
            VStack(alignment: .leading, spacing: 10) {
                blockTitle("Так увидит комната")
                RoomPollCard(
                    poll: RoomPollState(
                        id: "preview",
                        question: trimmedQuestion,
                        options: filledOptions,
                        votes: [:],
                        createdBy: "preview",
                        createdByName: "Вы"
                    ),
                    myUserId: "preview",
                    canClose: false,
                    onVote: { _ in },
                    onClose: {},
                    onDismiss: {}
                )
                .allowsHitTesting(false)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(V4.raised.opacity(0.35))
                )
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func blockTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy))
            .kerning(0.7)
            .textCase(.uppercase)
            .foregroundStyle(V4.muted)
    }

    // MARK: Кнопка

    private var createButton: some View {
        Button {
            onCreate(trimmedQuestion, filledOptions)
            HapticManager.impact(.medium)
            dismiss()
        } label: {
            Text("Запустить голосование")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(canCreate ? V4.accentInk : V4.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Capsule().fill(canCreate ? AnyShapeStyle(Cinema2026.accentAction) : AnyShapeStyle(V4.raised.opacity(0.7)))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canCreate)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [V4.canvas.opacity(0), V4.canvas.opacity(0.92), V4.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 130)
            .allowsHitTesting(false),
            alignment: .bottom
        )
    }
}
