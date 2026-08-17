// Plink/Features/WatchRoom/RoomPolls.swift — M13: room polls («что смотрим дальше?»)
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

struct RoomPollCard: View {
    let poll: RoomPollState
    let myUserId: String
    let canClose: Bool
    let onVote: (Int) -> Void
    let onClose: () -> Void
    let onDismiss: () -> Void

    private var myVote: Int? { poll.votes[myUserId] }
    private var showResults: Bool { myVote != nil || poll.isClosed }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(poll.isClosed ? "Голосование завершено" : "Голосование · \(poll.createdByName)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if canClose && !poll.isClosed {
                    Button("Завершить") { onClose() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .buttonStyle(.plain)
                }
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(poll.question)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                    pollOptionRow(index: index, option: option)
                }
            }
        }
        .padding(14)
        .plinkGlass(.overlay, cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func pollOptionRow(index: Int, option: String) -> some View {
        let count = poll.voteCount(for: index)
        let fraction = poll.totalVotes > 0 ? Double(count) / Double(poll.totalVotes) : 0
        Button {
            guard !poll.isClosed, myVote == nil else { return }
            onVote(index)
        } label: {
            ZStack(alignment: .leading) {
                if showResults {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.18))
                            .frame(width: geo.size.width * max(0.03, fraction))
                    }
                }
                HStack(spacing: 6) {
                    Text(option)
                        .font(.system(size: 13, weight: myVote == index ? .bold : .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    if myVote == index {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    }
                    if showResults {
                        Text("\(count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 34)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Composer

struct PollComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options: [String] = ["", ""]
    let onCreate: (String, [String]) -> Void

    private var canCreate: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            options.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Вопрос") {
                    TextField("Что смотрим дальше?", text: $question)
                }
                Section("Варианты (2–4)") {
                    ForEach(options.indices, id: \.self) { i in
                        TextField("Вариант \(i + 1)", text: $options[i])
                    }
                    if options.count < 4 {
                        Button {
                            options.append("")
                        } label: {
                            Label("Добавить вариант", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle("Голосование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        onCreate(question, options)
                        dismiss()
                    }
                    .disabled(!canCreate)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
