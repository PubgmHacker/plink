// Plink/V4/PlinkGroupAvatar.swift
//
// Лицо беседы: фото группы, а без фото — цвет, выведенный из её id.
//
// До этого файла аватар беседы во всех списках рисовался градиентом ТЕМЫ. На
// тёплой теме круг сливался с живым фоном, и все беседы выглядели одинаково —
// ровно то, за что 25.08 отвязали от темы буквы-аватары людей
// (PlinkAvatarPalette). Здесь тот же принцип: цвет принадлежит беседе.
//
// Байты фото лежат в БД и отдаются авторизованной ручкой
// GET /api/groups/:id/avatar — обычный AsyncImage до неё не доберётся,
// нужен Bearer-заголовок. Картинка кэшируется в общем PlinkAvatarImageCache
// по ключу с ?v=, поэтому поллинг списка чатов не мигает.

import SwiftUI
import UIKit

struct PlinkGroupAvatar: View {
    let groupId: String
    /// Название — из него берётся буква, когда фото нет.
    let title: String
    /// Версия аватара (мс). nil — фото не установлено, рисуем букву.
    var avatarVersion: Double?
    var size: CGFloat = 48

    @State private var image: UIImage?
    @State private var loadedKey: String?

    var body: some View {
        ZStack {
            letterView
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: cacheKey) { await load(force: false) }
        .onReceive(NotificationCenter.default.publisher(for: .plinkGroupAvatarDidChange)) { note in
            guard (note.object as? String) == groupId else { return }
            image = nil
            loadedKey = nil
            Task { await load(force: true) }
        }
    }

    /// Буква названия на цвете беседы. Ключ градиента — id, а не название:
    /// беседу переименовали — узнаваемый цвет остался прежним.
    private var letterView: some View {
        ZStack {
            Circle().fill(PlinkAvatarPalette.gradient(for: groupId))
            Text(letter)
                .font(.system(size: max(11, size * 0.36), weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var letter: String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("@") { t = String(t.dropFirst()) }
        guard let ch = t.first else { return "#" }
        return String(ch).uppercased()
    }

    /// nil, когда фото не установлено — тогда сеть вообще не трогаем.
    private var url: URL? {
        guard let v = avatarVersion, v > 0 else { return nil }
        var comps = URLComponents(
            url: APIClient.shared.baseURL.appendingPathComponent("groups/\(groupId)/avatar"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [URLQueryItem(name: "v", value: String(Int(v)))]
        return comps?.url
    }

    private var cacheKey: String { url?.absoluteString ?? "letter:\(groupId)" }

    @MainActor
    private func load(force: Bool) async {
        guard let url else {
            image = nil
            loadedKey = nil
            return
        }
        let key = url.absoluteString
        if !force, key == loadedKey, image != nil { return }
        if !force, let cached = PlinkAvatarImageCache.shared.image(for: key) {
            image = cached
            loadedKey = key
            return
        }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 12
        if let token = APIClient.shared.authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return }
            guard let ui = UIImage(data: data) else { return }
            PlinkAvatarImageCache.shared.store(ui, for: key)
            image = ui
            loadedKey = key
        } catch {
            // Остаётся буква — не мигаем плейсхолдером на каждой ошибке сети
        }
    }
}
