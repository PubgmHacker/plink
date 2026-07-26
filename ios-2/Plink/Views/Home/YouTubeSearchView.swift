// Plink/Views/Home/YouTubeSearchView.swift — Brain §4: Native YouTube picker
//
// Uses backend /api/media/search and /api/media/trending.
// Shows embeddability status. URL paste is secondary action only.

import SwiftUI

// MARK: - Data models (match backend response format)
//
// Brain Phase 3: backend now returns embeddable, privacyStatus,
// liveBroadcastContent, durationSeconds. iOS uses embeddable to disable
// rows where the video cannot be embedded in Plink.

struct YouTubeVideoSummary: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let channel: String
    let thumbnailURL: String?
    // Brain Phase 3: backend may send `durationSeconds` (new) or `duration` (legacy).
    // Decode either; prefer durationSeconds when present.
    let durationSeconds: Int?
    let duration: Int?
    let url: String?
    let embeddable: Bool?
    let privacyStatus: String?
    let liveBroadcastContent: String?

    // Back-compat: when backend omits these, default to safe values.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `id` may be missing if backend returns videoId only — fall back to videoId.
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .videoId)
            ?? ""
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        // `channel` may be missing — fall back to channelTitle.
        self.channel = try c.decodeIfPresent(String.self, forKey: .channel)
            ?? c.decodeIfPresent(String.self, forKey: .channelTitle)
            ?? ""
        self.thumbnailURL = try c.decodeIfPresent(String.self, forKey: .thumbnailURL)
        self.durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        self.duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
        self.embeddable = try c.decodeIfPresent(Bool.self, forKey: .embeddable)
        self.privacyStatus = try c.decodeIfPresent(String.self, forKey: .privacyStatus)
        self.liveBroadcastContent = try c.decodeIfPresent(String.self, forKey: .liveBroadcastContent)
    }

    private enum CodingKeys: String, CodingKey {
        case id, videoId, title, channel, channelTitle
        case thumbnailURL, duration, durationSeconds
        case url, embeddable, privacyStatus, liveBroadcastContent
    }

    // Convenience accessors
    var videoId: String { id }
    var channelTitle: String { channel }
    var resolvedDurationSeconds: Int? { durationSeconds ?? duration }
    var thumbnailURLString: String? { thumbnailURL }
    var resolvedLiveBroadcastContent: String { liveBroadcastContent ?? "none" }
    var resolvedEmbeddable: Bool? { embeddable }

    // Brain Revision 3: row states based on embeddable field.
    //   - true → selectable (green checkmark when selected)
    //   - false → disabled, "Нельзя встроить" label, lock icon, 50% opacity
    //   - nil → selectable but with "Проверим при запуске" hint (amber dot)
    var embeddableState: EmbeddableState {
        if let embeddable {
            return embeddable ? .embeddable : .notEmbeddable
        }
        return .unknown
    }

    enum EmbeddableState {
        case embeddable      // embeddable == true  → selectable, no badge
        case notEmbeddable   // embeddable == false → disabled, "Нельзя встроить"
        case unknown         // embeddable == nil   → selectable, "Проверим при запуске"
    }

    var isEmbeddable: Bool { embeddable != false }

    var isLive: Bool { resolvedLiveBroadcastContent == "live" }

    var durationText: String? {
        guard let seconds = resolvedDurationSeconds, seconds > 0 else { return nil }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct YouTubeSearchResponse: Decodable, Sendable {
    let results: [YouTubeVideoSummary]
}

// MARK: - Service

@MainActor
@Observable
final class YouTubePickerModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    var query = ""
    var items: [YouTubeVideoSummary] = []
    var state: State = .idle
    var selected: YouTubeVideoSummary?
    var showURLPaste = false
    var urlText = ""

    private var searchTask: Task<Void, Never>?
    private let apiBaseURL = PlinkConfig.baseURLString

    func queryChanged() {
        searchTask?.cancel()
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if value.isEmpty {
                await loadTrending()
            } else {
                await search(value)
            }
        }
    }

    func loadTrending() async {
        state = .loading
        do {
            let url = URL(string: "\(apiBaseURL)/api/media/trending?regionCode=RU&maxResults=20")!
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = .failed("Не удалось загрузить")
                return
            }
            let resp = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            items = resp.results
            state = items.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func search(_ query: String) async {
        state = .loading
        do {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let url = URL(string: "\(apiBaseURL)/api/media/search?q=\(encoded)&limit=20")!
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = .failed("Не удалось найти")
                return
            }
            let resp = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            items = resp.results
            state = items.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry() {
        Task {
            query.isEmpty ? await loadTrending() : await search(query)
        }
    }

    func selectFromURL() {
        let videoId = extractVideoId(from: urlText) ?? urlText
        guard videoId.count == 11 else { return }
        // Brain Phase 3: when user pastes a URL, embeddability is unknown — assume embeddable.
        // Backend will return error 101/150 if embedding is disabled, and the user will see
        // the friendly error UI in the player.
        let dict: [String: Any] = [
            "id": videoId,
            "title": "YouTube: \(videoId)",
            "channel": "",
            "thumbnailURL": "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg",
            "embeddable": true,
        ]
        // Build a Data representation so we can use the Decodable init.
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let summary = try? JSONDecoder().decode(YouTubeVideoSummary.self, from: data) {
            selected = summary
        }
    }

    private func extractVideoId(from url: String) -> String? {
        if url.contains("youtu.be/") {
            return url.components(separatedBy: "youtu.be/").last?.components(separatedBy: "?").first
        }
        if let components = URLComponents(string: url),
           let item = components.queryItems?.first(where: { $0.name == "v" }) {
            return item.value
        }
        if url.count == 11 { return url }
        return nil
    }
}

// MARK: - View

struct YouTubeSearchView: View {
    @State private var model = YouTubePickerModel()
    let onSelect: (String, String, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.showURLPaste {
                    urlPasteView
                } else {
                    switch model.state {
                    case .idle, .loading:
                        loadingView
                    case .empty:
                        emptyView
                    case .failed(let message):
                        errorView(message)
                    case .loaded:
                        resultsList
                    }
                }
            }
            .navigationTitle("YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.query, prompt: "Найти видео")
            .onChange(of: model.query) { _, _ in model.queryChanged() }
            .task { await model.loadTrending() }
            .safeAreaInset(edge: .bottom) {
                if let item = model.selected {
                    selectedBar(item: item)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Ссылка") {
                        model.showURLPaste.toggle()
                    }
                }
            }
        }
    }

    // MARK: - Results list

    private var resultsList: some View {
        List(model.items) { item in
            // Brain Phase 3: rows where embeddable == false are disabled (unclickable).
            if item.isEmbeddable {
                Button {
                    confirmSelection(item)
                } label: {
                    YouTubeResultRow(item: item, isSelected: false)
                }
                .buttonStyle(.plain)
            } else {
                YouTubeResultRow(item: item, isSelected: false, isDisabled: true)
                    .allowsHitTesting(false)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Cinema2026.background)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Cinema2026.accent)
                .scaleEffect(1.2)
            Text(model.query.isEmpty ? "Загрузка популярного…" : "Поиск…")
                .font(.caption)
                .foregroundStyle(Cinema2026.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Cinema2026.background)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Cinema2026.secondary)
            Text(LocalizationManager.shared.string(.nothingFound))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
            Text(LocalizationManager.shared.string(.ytTryAnother))
                .font(.caption)
                .foregroundStyle(Cinema2026.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Cinema2026.background)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Cinema2026.amber)
            Text(LocalizationManager.shared.string(.ytError))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
            Text(message)
                .font(.caption)
                .foregroundStyle(Cinema2026.secondary)
                .multilineTextAlignment(.center)
            Button("Повторить") { model.retry() }
                .buttonStyle(.bordered)
                .tint(Cinema2026.accent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Cinema2026.background)
    }

    // MARK: - URL paste fallback

    private var urlPasteView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "link")
                .font(.system(size: 40))
                .foregroundStyle(Cinema2026.secondary)
            Text(LocalizationManager.shared.string(.ytPasteLink))
                .font(.headline)
                .foregroundStyle(Cinema2026.text)
            TextField("https://youtube.com/watch?v=…", text: $model.urlText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)
            Button("Выбрать") {
                model.selectFromURL()
                if let item = model.selected {
                    confirmSelection(item)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Cinema2026.accent)
            .disabled(model.urlText.isEmpty)
            Spacer()
        }
        .background(Cinema2026.background)
    }

    // MARK: - Selected bar

    private func selectedBar(item: YouTubeVideoSummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: item.thumbnailURLString ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(2)
                    Text(item.channelTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Cinema2026.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    confirmSelection(item)
                } label: {
                    Text(LocalizationManager.shared.string(.ytSelect))
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Cinema2026.background)
                }
            }
            .padding(14)
            .background(Cinema2026.surface)
            .overlay(alignment: .top) {
                Rectangle().fill(Cinema2026.divider).frame(height: 0.5)
            }
        }
    }

    private func confirmSelection(_ item: YouTubeVideoSummary) {
        let thumb = item.thumbnailURLString ?? "https://img.youtube.com/vi/\(item.videoId)/mqdefault.jpg"
        onSelect(item.videoId, item.title, thumb)
        dismiss()
    }
}

// MARK: - Result row

struct YouTubeResultRow: View {
    let item: YouTubeVideoSummary
    let isSelected: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: item.thumbnailURLString ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(isDisabled ? 0.5 : 1.0)

                if let duration = item.durationText, !isDisabled {
                    Text(duration)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.8), in: Capsule())
                        .padding(4)
                }

                // Brain Phase 3: show LIVE badge when content is live.
                if item.isLive, !isDisabled {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Cinema2026.danger, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDisabled ? Cinema2026.secondary : Cinema2026.text)
                    .lineLimit(2)

                Text(item.channelTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Cinema2026.secondary)
                    .lineLimit(1)

                // Brain Revision 3: row state badges.
                switch item.embeddableState {
                case .notEmbeddable:
                    Text(LocalizationManager.shared.string(.ytCantEmbed))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Cinema2026.amber)
                case .unknown:
                    Text(LocalizationManager.shared.string(.ytCheckOnPlay))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                case .embeddable:
                    // No badge — fully embeddable, no special hint.
                    EmptyView()
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Cinema2026.accent)
            } else if isDisabled {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Cinema2026.secondary)
                    .font(.system(size: 14))
            } else if item.embeddableState == .unknown {
                // Subtle question mark for unknown embeddability.
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Cinema2026.secondary)
                    .font(.system(size: 14))
            }
        }
        .padding(.vertical, 6)
        .background(isSelected ? Cinema2026.accent.opacity(0.06) : .clear)
        .contentShape(Rectangle())
    }
}
