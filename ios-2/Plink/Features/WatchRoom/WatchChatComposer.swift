// Plink/Features/WatchRoom/WatchChatComposer.swift — PATCH 26: Telegram-style emoji
//
// PATCH 26: inline emoji panel (Telegram-style) instead of popover.

import SwiftUI
import PhotosUI
import ImageIO          // CGImageSource* + ключи метаданных GIF (задержка кадров)

struct WatchChatComposer: View {
    let model: WatchRoomModel

    @State private var state = ChatComposerState()
    @State private var showEmojiPanel = false
    @State private var currentPackIndex = 0
    @State private var showPacksPopover = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoDraft: ChatPhotoDraft?
    @State private var photoCaption = ""
    @State private var photoError: String?
    /// Голосовой ввод в чате комнаты — тот же движок, что на вкладке ИИ.
    @StateObject private var voiceCapture = V4VoiceCapture()

    /// Тема для орба и кнопки микрофона. Комната читает выбранную тему из
    /// UserDefaults — так же, как PlinkApprovedV4Root пишет её при смене.
    private var roomTheme: V4Theme {
        let raw = UserDefaults.standard.string(forKey: "plink.v4ThemeName") ?? ""
        return V4Theme(rawValue: raw) ?? .electric
    }

    private var canSend: Bool {
        // M16: ИИ-модератор — при активном муте отправка заблокирована
        if model.mutedRemainingSec > 0 { return false }
        // Connected or still negotiating — allow optimistic send
        let online = model.connectionState == .connected || model.connectionState.isTransient
        return state.canSend(connected: online)
    }

    private var hasPremium: Bool {
        PremiumStatusManager.shared.isPremium
    }

    private let emojiPacks: [EmojiPack] = PlinkEmojiCatalog.allPacks

    private var currentPack: EmojiPack {
        guard currentPackIndex >= 0 && currentPackIndex < emojiPacks.count else { return emojiPacks[0] }
        return emojiPacks[currentPackIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // M16: баннер мута от ИИ-модератора с живым обратным отсчётом
            if model.mutedUntil != nil {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let remaining = model.mutedRemainingSec
                    if remaining > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 12, weight: .bold))
                            Text("\(L.string(.queueMutedLabel)) \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Cinema2026.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Cinema2026.danger.opacity(0.12))
                    }
                }
            }

            // M16: очередь видео комнаты — компактная лента над чатом
            if !model.roomQueue.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.triangle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Cinema2026.accent)
                        Text("\(L.string(.queueLabel)) \(model.roomQueue.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Cinema2026.accent)
                        ForEach(model.roomQueue.prefix(10)) { item in
                            // M17: чип очереди с управлением — включить (хост) / убрать
                            Menu {
                                if model.isHost {
                                    Button {
                                        model.playFromQueue(item)
                                        HapticManager.impact(.light)
                                    } label: {
                                        Label("Включить сейчас", systemImage: "play.fill")
                                    }
                                }
                                Button(role: .destructive) {
                                    model.removeFromQueue(item)
                                    HapticManager.impact(.light)
                                } label: {
                                    Label("Убрать из очереди", systemImage: "trash")
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    // M18: молния — поставлено с приоритетом Plink+
                                    if item.priority == true {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Cinema2026.accent)
                                    }
                                    Text(item.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.75))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.25))
            }

            // Quick reactions (multi-device floating reactions)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReactionPalette.free, id: \.self) { emoji in
                        Button {
                            model.sendReaction(emoji: emoji, hasPremium: hasPremium)
                            HapticManager.impact(.light)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 22))
                                .frame(width: 40, height: 36)
                                .background(Cinema2026.raised, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reaction \(emoji)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // PATCH 26: inline emoji panel (Telegram-style)
            if showEmojiPanel {
                EmojiInlinePanel(
                    pack: currentPack,
                    hasPremium: hasPremium,
                    onPick: { emoji in
                        // Empty field + pick → live reaction; otherwise insert into message
                        if state.trimmedText.isEmpty {
                            model.sendReaction(emoji: emoji, hasPremium: hasPremium)
                            HapticManager.impact(.light)
                        } else {
                            state.insertAtCursor(emoji)
                        }
                    },
                    onPremiumUpsell: {
                        // Don't silently close — switch to free pack so user can still pick
                        if let freeIdx = emojiPacks.firstIndex(where: { !$0.isPremium }) {
                            currentPackIndex = freeIdx
                        }
                        HapticManager.impact(.light)
                    },
                    onSwitchPack: { index in
                        currentPackIndex = index
                    },
                    packs: emojiPacks
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Панель записи — над полем ввода, а не поверх экрана: кадр и
            // переписка остаются видны, пока человек говорит.
            if voiceCapture.isCapturing {
                V4VoiceDock(
                    capture: voiceCapture,
                    theme: roomTheme,
                    onSend: {
                        voiceCapture.pressEnded { text in
                            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            state.text = clean
                        }
                    },
                    onCancel: { voiceCapture.cancel() }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Telegram-style: [ + ] [ field ………………… ] [😊] [↑]
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Cinema2026.accent)
                        .frame(width: 38, height: 40)
                        .background(Cinema2026.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Галерея")
                .simultaneousGesture(TapGesture().onEnded { Task { await PlinkPermissions.preparePhotoPicker() } })

                VStack(spacing: 4) {
                    TextField("Сообщение…", text: $state.text, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 15))
                        .foregroundStyle(Cinema2026.text)
                        .tint(Cinema2026.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Cinema2026.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(
                                    state.isOverLength ? Cinema2026.danger : .white.opacity(0.05),
                                    lineWidth: state.isOverLength ? 1 : 0.5
                                )
                        )
                        .onTapGesture {
                            if showEmojiPanel {
                                withAnimation(.easeOut(duration: 0.2)) { showEmojiPanel = false }
                            }
                        }

                    if state.isOverLength {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text("\(state.trimmedText.count)/\(ChatComposerState.maxLength)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Cinema2026.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }
                }

                // Emoji — right side next to send (Telegram)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showEmojiPanel.toggle()
                    }
                    HapticManager.impact(.light)
                } label: {
                    Image(systemName: showEmojiPanel ? "keyboard" : "face.smiling.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(showEmojiPanel ? Cinema2026.accent : Cinema2026.secondary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Эмодзи")
                .onLongPressGesture {
                    showPacksPopover = true
                }
                .popover(isPresented: $showPacksPopover) {
                    PacksPopover(
                        packs: emojiPacks,
                        currentIndex: $currentPackIndex,
                        hasPremium: hasPremium,
                        onDismiss: { showPacksPopover = false }
                    )
                }

                // Пустое поле — микрофон, есть текст — отправка. Голос здесь
                // способ ввода, а не отдельный режим: распознанное садится в
                // то же поле, его можно поправить перед отправкой.
                if state.trimmedText.isEmpty {
                    V4VoiceMicButton(
                        capture: voiceCapture,
                        theme: roomTheme,
                        surface: "room_chat",
                        chrome: .bare,
                        onResult: { text in
                            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            state.text = clean
                        }
                    )
                } else {
                    Button {
                        let value = state.trimmedText
                        guard !value.isEmpty, !state.isOverLength else { return }
                        model.sendChat(text: value)
                        state.clearAfterSend()
                        showEmojiPanel = false
                        HapticManager.impact(.light)
                    } label: {
                        V4GlyphIcon(glyph: .send, size: 16, filled: true, weight: .regular)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                state.isOverLength
                                    ? AnyShapeStyle(Cinema2026.raised)
                                    : AnyShapeStyle(Cinema2026.accentAction),
                                in: Circle()
                            )
                            .overlay(Circle().stroke(.white.opacity(0.05), lineWidth: 0.5))
                    }
                    .disabled(state.isOverLength)
                    .accessibilityLabel("Отправить")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Cinema2026.surface.opacity(0.95))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Cinema2026.divider.opacity(0.4))
                    .frame(height: 0.5)
            }
            .onReceive(NotificationCenter.default.publisher(for: .plinkInsertAtCursor)) { note in
                if let insertion = note.userInfo?["text"] as? String {
                    state.insertAtCursor(insertion)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await preparePhotoDraft(from: item) }
        }
        .sheet(item: $photoDraft) { draft in
            PhotoSendPreviewSheet(
                draft: draft,
                caption: $photoCaption,
                onCancel: {
                    photoDraft = nil
                    selectedPhotoItem = nil
                    photoCaption = ""
                },
                onSend: {
                    model.sendPhoto(
                        dataURL: draft.compressed.dataURL,
                        previewImage: draft.compressed.image,
                        caption: photoCaption
                    )
                    state.clearAfterSend()
                    photoDraft = nil
                    selectedPhotoItem = nil
                    photoCaption = ""
                    HapticManager.impact(.medium)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .alert("Фото", isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil } }
        )) {
            Button("OK", role: .cancel) { photoError = nil }
        } message: {
            Text(photoError ?? "")
        }
    }

    private func preparePhotoDraft(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run { photoError = "Не удалось прочитать фото" }
                return
            }
            let compressed = try ChatImageCompressor.compress(data)
            await MainActor.run {
                photoCaption = state.trimmedText
                photoDraft = ChatPhotoDraft(compressed: compressed)
            }
        } catch {
            await MainActor.run {
                photoError = "Не удалось подготовить фото: \(error.localizedDescription)"
                selectedPhotoItem = nil
            }
        }
    }
}

// MARK: - Emoji Pack Model (custom packs for Plink+)

struct EmojiPack: Identifiable {
    let id = UUID()
    let name: String
    let emojis: [String]
    let isPremium: Bool
}

// MARK: - Packs Popover (long tap on emoji button → Telegram style)

struct PacksPopover: View {
    let packs: [EmojiPack]
    @Binding var currentIndex: Int
    let hasPremium: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizationManager.shared.string(.wcPacksTitle))
                .font(.headline)
                .padding(.horizontal)

            ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                Button {
                    if !pack.isPremium || hasPremium {
                        currentIndex = index
                        onDismiss()
                    }
                } label: {
                    HStack {
                        Text(pack.name)
                            .foregroundStyle(Cinema2026.text)
                        Spacer()
                        if pack.isPremium {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(Cinema2026.accent)
                        }
                        if currentIndex == index {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Cinema2026.accent)
                        }
                    }
                    .padding(8)
                    .background(currentIndex == index ? Cinema2026.raised : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(pack.isPremium && !hasPremium)
            }

            if !hasPremium {
                Text(LocalizationManager.shared.string(.wcPacksPremiumHint))
                    .font(.caption)
                    .foregroundStyle(Cinema2026.secondary)
                    .padding(.horizontal)
            }
        }
        .padding()
        .frame(width: 280)
        .background(Cinema2026.surface)
    }
}

// MARK: - Inline emoji panel (Telegram-style, custom packs)

struct EmojiInlinePanel: View {
    let pack: EmojiPack
    let hasPremium: Bool
    let onPick: (String) -> Void
    let onPremiumUpsell: () -> Void
    let onSwitchPack: (Int) -> Void
    let packs: [EmojiPack]

    var body: some View {
        VStack(spacing: 4) {
            // Pack switcher
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(packs.enumerated()), id: \.element.id) { index, p in
                        Button {
                            if !p.isPremium || hasPremium {
                                onSwitchPack(index)
                            } else {
                                onPremiumUpsell()
                            }
                        } label: {
                            Text(p.name)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(p.id == pack.id ? Cinema2026.accent.opacity(0.2) : Cinema2026.raised)
                                .clipShape(Capsule())
                                .foregroundStyle(p.id == pack.id ? Cinema2026.accent : Cinema2026.text)
                                .overlay {
                                    if p.isPremium && !hasPremium {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 8))
                                            .foregroundStyle(Cinema2026.amber)
                                            .offset(x: 8, y: -8)
                                    }
                                }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(pack.emojis, id: \.self) { emojiName in
                        Button {
                            if pack.isPremium && !hasPremium {
                                onPremiumUpsell()
                            } else {
                                onPick(emojiName)  // pass name; chat will render Image or text
                            }
                        } label: {
                            EmojiAssetImage(name: emojiName, pack: pack.name)
                                .frame(width: 28, height: 28)
                                .opacity(pack.isPremium && !hasPremium ? 0.5 : 1)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 6)
        .background(Cinema2026.surface.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle().fill(Cinema2026.divider.opacity(0.4)).frame(height: 0.5)
        }
    }
}

// MARK: - Emoji picker notification

extension Notification.Name {
    static let plinkInsertAtCursor = Notification.Name("plinkInsertAtCursor")
}

// MARK: - Emoji asset loading
//
// Аудит 26.07.2026. Здесь было три бага, из-за которых «отображались не все эмодзи»:
//
//  1. ГЛАВНЫЙ: каталог хранит имена с префиксом `emoji_` («emoji_laugh»), а файлы
//     на диске лежат без него («reactions/laugh.png»). Bundle.url(forResource:)
//     ищет точное совпадение → не находил НИЧЕГО, и все 36 эмодзи паков
//     Reactions (20), Plink+ (8) и Fun (8) показывали одну заглушку face.smiling.
//     Кастомные паки (Cute Faces, Pepe, Stickers, Cats, Le Pepe) совпадали
//     по именам один в один и поэтому работали — отсюда и ощущение «часть есть,
//     часть нет».
//
//  2. Файл читался с диска и декодировался ЗАНОВО на каждой перерисовке тела View.
//     В панели на 100+ эмодзи это сотни лишних чтений и декодов PNG на главном
//     потоке при каждом скролле. Теперь результат кэшируется.
//
//  3. Для любого ненайденного имени показывался один и тот же смайлик, поэтому
//     «злой», «грустный» и «спящий» выглядели одинаково. Теперь для каждого
//     имени подбирается осмысленный SF Symbol — он рисуется нативно, тянется
//     под нужный размер и красится в цвет темы.
//
// GIF-кадры декодируются вне главного потока и уважают Reduce Motion.

/// Потокобезопасный кэш ассетов эмодзи (NSCache сам по себе thread-safe).
final class EmojiAssetCache {
    static let shared = EmojiAssetCache()

    private let stills = NSCache<NSString, UIImage>()
    private let animations = NSCache<NSString, NSArray>()
    private let delays = NSCache<NSString, NSNumber>()
    private let misses = NSCache<NSString, NSNumber>()

    private init() {
        stills.countLimit = 300
        animations.countLimit = 40
    }

    private func key(_ name: String, _ pack: String) -> NSString {
        "\(pack)/\(name)" as NSString
    }

    /// Имя из каталога может быть с префиксом `emoji_`, а файл на диске — без него.
    /// Пробуем оба варианта, каждый — как .png и как .gif.
    private func locate(name: String, pack: String) -> (url: URL, isGIF: Bool)? {
        let dir = "Emojis/\(PlinkEmojiCatalog.packDirectory(for: pack))"
        var candidates = [name]
        if name.hasPrefix("emoji_") {
            candidates.append(String(name.dropFirst("emoji_".count)))
        }
        for candidate in candidates {
            if let url = Bundle.main.url(forResource: candidate, withExtension: "png", subdirectory: dir) {
                return (url, false)
            }
            if let url = Bundle.main.url(forResource: candidate, withExtension: "gif", subdirectory: dir) {
                return (url, true)
            }
        }
        return nil
    }

    /// Статичная картинка (PNG). Для GIF возвращает nil — его рисует анимированная ветка.
    func still(name: String, pack: String) -> UIImage? {
        let k = key(name, pack)
        if let cached = stills.object(forKey: k) { return cached }
        if misses.object(forKey: k) != nil { return nil }

        guard let found = locate(name: name, pack: pack), !found.isGIF,
              let data = try? Data(contentsOf: found.url),
              let image = UIImage(data: data)
        else {
            // Ассет-каталог как запасной источник (на случай новых паков в .xcassets)
            if let fromCatalog = UIImage(named: name, in: .main, with: nil) {
                stills.setObject(fromCatalog, forKey: k)
                return fromCatalog
            }
            misses.setObject(1, forKey: k)
            return nil
        }
        stills.setObject(image, forKey: k)
        return image
    }

    /// Есть ли у этого имени GIF (быстрая проверка без декодирования).
    func hasAnimation(name: String, pack: String) -> Bool {
        locate(name: name, pack: pack)?.isGIF ?? false
    }

    /// Кадры GIF + средняя задержка. Декодирование уходит с главного потока.
    func animation(name: String, pack: String) async -> (frames: [UIImage], delay: TimeInterval) {
        let k = key(name, pack)
        if let cached = animations.object(forKey: k) as? [UIImage], !cached.isEmpty {
            return (cached, delays.object(forKey: k)?.doubleValue ?? 0.1)
        }
        guard let found = locate(name: name, pack: pack), found.isGIF else { return ([], 0.1) }

        let decoded: ([UIImage], TimeInterval) = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: found.url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil)
            else { return ([], 0.1) }

            let count = CGImageSourceGetCount(source)
            var frames: [UIImage] = []
            frames.reserveCapacity(count)
            var total: TimeInterval = 0

            for index in 0..<count {
                if let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) {
                    frames.append(UIImage(cgImage: cgImage))
                }
                // Реальная задержка кадра из метаданных GIF вместо жёстких 0.1 с,
                // иначе быстрые гифки играли медленно, а медленные — слишком быстро.
                if let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                   let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                    let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                    let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
                    total += max(unclamped ?? clamped ?? 0.1, 0.02)
                }
            }
            let average = frames.isEmpty ? 0.1 : max(total / Double(frames.count), 0.02)
            return (frames, average)
        }.value

        if !decoded.0.isEmpty {
            animations.setObject(decoded.0 as NSArray, forKey: k)
            delays.setObject(NSNumber(value: decoded.1), forKey: k)
        }
        return decoded
    }
}

/// Загружает кастомное эмодзи (PNG/GIF) из `Resources/Emojis/<pack>/`.
/// Если файла нет — рисует подходящий SF Symbol, а не пустоту.
struct EmojiAssetImage: View {
    let name: String
    let pack: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames: [UIImage] = []
    @State private var frameDelay: TimeInterval = 0.1

    var body: some View {
        Group {
            if let still = EmojiAssetCache.shared.still(name: name, pack: pack) {
                Image(uiImage: still).resizable()
            } else if !frames.isEmpty {
                if reduceMotion, let first = frames.first {
                    // Уважаем «Уменьшение движения»: показываем первый кадр.
                    Image(uiImage: first).resizable()
                } else {
                    GifPlayerView(images: frames, frameDuration: frameDelay)
                }
            } else {
                Image(systemName: Self.symbolName(for: name)).resizable()
            }
        }
        .task(id: "\(pack)/\(name)") {
            guard EmojiAssetCache.shared.hasAnimation(name: name, pack: pack) else { return }
            let result = await EmojiAssetCache.shared.animation(name: name, pack: pack)
            frames = result.frames
            frameDelay = result.delay
        }
    }

    /// Осмысленный SF Symbol для имён, у которых пока нет своей картинки.
    /// Покрывает 13 позиций каталога без файлов на диске: Reactions (scream, cry,
    /// think, cool, angry, sad, wow, sleepy, pray, ok, poop) и Plink+ (neon_cool,
    /// neon_wow). Так «злой» и «грустный» перестают выглядеть одинаково.
    static func symbolName(for rawName: String) -> String {
        var key = rawName
        if key.hasPrefix("emoji_") { key = String(key.dropFirst("emoji_".count)) }
        if key.hasPrefix("neon_") { key = String(key.dropFirst("neon_".count)) }

        switch key {
        case "laugh": return "face.smiling"
        case "fire": return "flame.fill"
        case "heart", "love": return "heart.fill"
        case "thumbs_up": return "hand.thumbsup.fill"
        case "thumbs_down": return "hand.thumbsdown.fill"
        case "clap": return "hands.clap.fill"
        case "flex": return "figure.strengthtraining.traditional"
        case "party": return "sparkles"
        case "scream": return "exclamationmark.bubble.fill"
        case "cry", "sad": return "drop.fill"
        case "think": return "questionmark.bubble.fill"
        case "cool": return "eyeglasses"
        case "angry": return "bolt.fill"
        case "wow": return "sparkle"
        case "sleepy": return "moon.zzz.fill"
        case "pray": return "hands.sparkles.fill"
        case "ok": return "checkmark.seal.fill"
        case "poop": return "trash.fill"
        case "popcorn": return "popcorn.fill"
        case "movie", "film": return "film.fill"
        case "clapper": return "film.stack.fill"
        case "director": return "megaphone.fill"
        case "oscar": return "star.fill"
        case "ticket": return "ticket.fill"
        case "camera": return "camera.fill"
        default: return "face.smiling"
        }
    }
}

// Simple GIF player — cycles through frames
struct GifPlayerView: View {
    let images: [UIImage]
    @State private var currentFrame = 0
    @State private var frameTimer: Timer?
    /// Реальная задержка кадров из метаданных GIF. По умолчанию — прежние 0.1 с.
    var frameDuration: TimeInterval = 0.1

    init(images: [UIImage], frameDuration: TimeInterval = 0.1) {
        self.images = images
        self.frameDuration = frameDuration
    }

    var body: some View {
        if images.isEmpty {
            Color.clear
        } else {
            Image(uiImage: images[currentFrame])
                .resizable()
                .onAppear {
                    // P1 audit fix: timer was never invalidated -> leaked run-loop
                    // work for every rendered GIF. Store and stop on disappear.
                    frameTimer?.invalidate()
                    frameTimer = Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { _ in
                        currentFrame = (currentFrame + 1) % images.count
                    }
                }
                .onDisappear {
                    frameTimer?.invalidate()
                    frameTimer = nil
                }
        }
    }
}
