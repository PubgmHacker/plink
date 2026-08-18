//
//  PlinkRoomAppearance.swift
//  Plink
//
//  P1 — Host-authoritative room appearance protocol.
//  Implements Section 2.2 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//

import SwiftUI
import Foundation

// MARK: - RoomAppearance

internal struct RoomAppearance: Codable, Sendable, Equatable {
    let themeId: String
    let themeRevision: Int
    var intensity: Double       // 0.0 ... 0.44 (V4 cap)
    var motionEnabled: Bool

    init(
        themeId: String,
        themeRevision: Int = 1,
        intensity: Double = 0.44,
        motionEnabled: Bool = true
    ) {
        self.themeId = themeId
        self.themeRevision = themeRevision
        // V4 cap: 0...0.44. Нижнюю границу тоже держим — отрицательная
        // непрозрачность из битого ответа рисовала бы пустой слой.
        self.intensity = min(max(intensity, 0), 0.44)
        self.motionEnabled = motionEnabled
    }

    /// Идентификатор бесплатной статики — «живой темы нет».
    static let staticThemeId = "room-default-static"

    /// Тема из каталога roomLive выбрана (а не бесплатная статика).
    var isLiveTheme: Bool { themeId != Self.staticThemeId }

    static let defaultStatic = RoomAppearance(
        themeId: "room-default-static",
        themeRevision: 1,
        intensity: 0.30,
        motionEnabled: false
    )
}

// MARK: - RoomAppearanceRegistry

internal enum RoomAppearanceRegistry {
    static func resolve(themeId: String) -> AppearanceDescriptor? {
        AppearanceCatalog.roomLive.first { $0.id == themeId }
    }

    /// Returns `defaultStatic` if the themeId is unknown or revoked.
    static func safeResolve(themeId: String) -> RoomAppearance {
        if resolve(themeId: themeId) != nil {
            return RoomAppearance(themeId: themeId, intensity: 0.44, motionEnabled: true)
        }
        return .defaultStatic
    }
}

// MARK: - RoomAppearanceStore (per active room)

@MainActor
@Observable
internal final class RoomAppearanceStore {
    /// Транспорт PATCH /rooms/:id/appearance. Инъекция нужна тестам: без неё
    /// проверить «локально не блокируем, решает сервер» можно только сетью.
    typealias Transport = (String, RoomAppearanceUpdate) async throws -> Void

    private(set) var appearance: RoomAppearance = .defaultStatic
    private(set) var isHost: Bool = false

    /// Пришло ли уже авторитетное состояние (realtime-событие или
    /// собственная успешная запись хоста). Гидрация из GET /rooms/:id после
    /// этого запрещена — см. `applyHydration`.
    private(set) var hasAuthoritativeState = false

    private let roomID: String
    private let entitlement: EntitlementProviding
    private let transport: Transport

    init(
        roomID: String,
        isHost: Bool,
        entitlement: EntitlementProviding,
        transport: Transport? = nil
    ) {
        self.roomID = roomID
        self.isHost = isHost
        self.entitlement = entitlement
        self.transport = transport ?? { room, body in
            // Здесь был requestNoBody, который на
            // любой не-2xx отдаёт «Ошибка сервера (403): Request failed» —
            // тело ответа он не разбирает. А именно в теле лежит
            // { error, code: "PREMIUM_REQUIRED" }. Через request<T> текст
            // сервера доезжает до пользователя.
            let _: RoomAppearanceAck = try await APIClient.shared.request(
                "rooms/\(room)/appearance",
                method: .patch,
                body: body
            )
        }
    }

    // MARK: - Receive from server

    func applyServerUpdate(_ new: RoomAppearance) {
        hasAuthoritativeState = true
        apply(new)
    }

    /// Начальная гидрация из GET /rooms/:id. Ревью 26.07.2026: гонка с
    /// realtime — запрос стартует в connect() без синхронизации с сокетом, и
    /// если хост поменял тему в этот момент, ответ БД мог тихо перезаписать
    /// уже применённое событие room.appearance.updated. Авторитетное состояние
    /// всегда старше гидрации, поэтому после него она игнорируется.
    func applyHydration(_ new: RoomAppearance) {
        guard !hasAuthoritativeState else { return }
        apply(new)
    }

    private func apply(_ new: RoomAppearance) {
        let resolved = RoomAppearanceRegistry.safeResolve(themeId: new.themeId)
        // Неизвестный/отозванный themeId → defaultStatic (ревизия каталога),
        // известный → ревизия сервера.
        let revision = resolved.themeId == new.themeId ? new.themeRevision : resolved.themeRevision
        self.appearance = RoomAppearance(
            themeId: resolved.themeId,
            themeRevision: revision,
            intensity: new.intensity,
            motionEnabled: new.motionEnabled
        )
    }

    /// Роль приходит только в `session.ready`, поэтому стор создаётся до неё
    /// (предположение по hostID комнаты) и уточняется здесь.
    func setHost(_ value: Bool) {
        guard isHost != value else { return }
        isHost = value
    }

    // MARK: - Host mutations

    func updateTheme(to themeId: String) async throws {
        guard isHost else { throw RoomAppearanceError.notHost }
        // Бесплатная статика — единственный вид без каталожного дескриптора:
        // это выход из живой темы, сервер тоже пропускает его без Plink+.
        if themeId == RoomAppearance.staticThemeId {
            let payload = RoomAppearance(
                themeId: themeId,
                themeRevision: 1,
                intensity: RoomAppearance.defaultStatic.intensity,
                motionEnabled: false
            )
            try await commit(payload)
            return
        }
        guard let desc = RoomAppearanceRegistry.resolve(themeId: themeId) else {
            throw RoomAppearanceError.unknownTheme
        }
        if desc.premium {
            // Ревью 26.07.2026: локального БЛОКИРУЮЩЕГО guard здесь больше нет.
            // DefaultEntitlementProvider читает PremiumStatusManager.isPremium,
            // а тот по правилу C9 на каждом холодном старте жёстко ставит
            // false, пока не приедет ответ сервера (AuthService → syncFromServer).
            // До этого момента хост с активным Plink+ получал отказ «Живые темы
            // доступны в Plink+» вообще без запроса — при том, что PATCH
            // /rooms/:id/appearance его бы пропустил. Авторитет — сервер: он
            // отдаёт 403 с code PREMIUM_REQUIRED и готовым текстом.
            // refresh() оставлен: он подтягивает свежие права для остального UI
            // и ничего не стоит, если ответ уже есть.
            await entitlement.refresh()
        }
        let payload = RoomAppearance(
            themeId: themeId,
            themeRevision: desc.revision,
            intensity: 0.44,
            motionEnabled: true
        )
        try await commit(payload)
    }

    func setIntensity(_ value: Double) async throws {
        guard isHost else { throw RoomAppearanceError.notHost }
        let capped = min(max(value, 0), 0.44)
        var updated = appearance
        updated.intensity = capped
        try await commit(updated)
    }

    func setMotionEnabled(_ value: Bool) async throws {
        guard isHost else { throw RoomAppearanceError.notHost }
        var updated = appearance
        updated.motionEnabled = value
        try await commit(updated)
    }

    // MARK: - Backend

    /// Сохранить на сервере и, только после успеха, применить локально.
    /// Успешная запись хоста — такое же авторитетное состояние, как событие:
    /// после неё запоздавшая гидрация из GET /rooms/:id не откатит тему.
    private func commit(_ payload: RoomAppearance) async throws {
        try await persistAppearance(payload)
        hasAuthoritativeState = true
        self.appearance = payload
    }

    private func persistAppearance(_ payload: RoomAppearance) async throws {
        let body = RoomAppearanceUpdate(
            themeId: payload.themeId,
            themeRevision: payload.themeRevision,
            intensity: payload.intensity,
            motionEnabled: payload.motionEnabled
        )
        do {
            try await transport(roomID, body)
        } catch let apiError as APIError {
            if case .serverError(let status, let message) = apiError, status == 403 {
                // Ревью 26.07.2026: 403 на этом роуте отдают ДВА источника —
                // preHandler requireHost (rooms.ts) и проверка Plink+. Поле
                // `code: PREMIUM_REQUIRED` до нас не доезжает: APIError несёт
                // только status и текст. Зато премиум-гейт по построению не
                // может сработать на бесплатной статике (FREE_ROOM_THEME_IDS на
                // сервере) — значит там 403 всегда означает «уже не хост».
                // Свой текст про хост-права понятнее английского ответа роута.
                if payload.themeId == RoomAppearance.staticThemeId {
                    throw RoomAppearanceError.notHost
                }
                throw RoomAppearanceError.requiresPlinkPlus(serverMessage: message)
            }
            throw RoomAppearanceError.backendRejected(reason: apiError.localizedDescription)
        } catch {
            throw RoomAppearanceError.backendRejected(reason: error.localizedDescription)
        }
    }
}

/// Ответ PATCH /rooms/:id/appearance: { success, appearance }.
/// Тело нам не нужно (авторитетная тема прилетит событием), но декодер
/// обязан во что-то распаковаться — все поля опциональны намеренно.
private struct RoomAppearanceAck: Decodable {
    let success: Bool?
}

// MARK: - Errors

internal enum RoomAppearanceError: LocalizedError, Sendable {
    case notHost
    case unknownTheme
    /// 403 PREMIUM_REQUIRED (или локальная проверка прав до запроса).
    /// serverMessage — текст бэкенда, если он до нас доехал.
    case requiresPlinkPlus(serverMessage: String?)
    case backendRejected(reason: String)

    var errorDescription: String? {
        switch self {
        case .notHost:                  return "Только хост может менять оформление комнаты."
        case .unknownTheme:             return "Тема не найдена в реестре."
        case .requiresPlinkPlus(let serverMessage):
            let text = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "Живые темы комнаты доступны в Plink+" : text
        case .backendRejected(let r):   return "Сервер отклонил: \(r)"
        }
    }
}

// MARK: - Wire bridge

extension RoomAppearance {
    /// Единая точка перевода «провод/БД → доменная модель».
    /// Источники: событие `room.appearance.updated` и строка `Room.appearance`
    /// из GET /rooms/:id (там же лежат аудит-поля, которые нам не нужны).
    init(wire: RealtimeServerMessage.RoomAppearanceUpdated.Payload) {
        self.init(
            themeId: wire.themeId,
            themeRevision: wire.themeRevision,
            intensity: wire.intensity,
            motionEnabled: wire.motionEnabled
        )
    }
}

// MARK: - RoomAppearanceControlPanel (host only)

/// Панель хоста: выбор живой темы комнаты, интенсивность, движение.
/// Показывается только хосту (точка входа — кнопка в верхнем хроме плеера).
struct RoomAppearanceControlPanel: View {
    let store: RoomAppearanceStore
    /// Куда отдать текст ошибки — экран комнаты показывает его тостом.
    var onError: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var isBusy = false
    @State private var inlineError: String?
    /// Локальное значение ползунка на время драга (nil — берём из стора).
    @State private var intensityDraft: Double?

    private var themes: [AppearanceDescriptor] { AppearanceCatalog.roomLive }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Живая тема видна всем в комнате. Она рисуется вокруг плеера и никогда не поверх видео.")
                        .font(.system(size: 13))
                        .foregroundStyle(Cinema2026.secondary)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        themeTile(
                            id: RoomAppearance.staticThemeId,
                            title: "Без темы",
                            subtitle: "Обычный тёмный зал",
                            colors: ["#0A0E1A", "#101314"],
                            premium: false
                        )
                        ForEach(themes) { item in
                            themeTile(
                                id: item.id,
                                title: item.title,
                                subtitle: item.subtitle,
                                colors: item.previewColors,
                                premium: item.premium
                            )
                        }
                    }

                    if store.appearance.isLiveTheme {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Интенсивность")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Cinema2026.text)
                            // PATCH уходит ТОЛЬКО по отпусканию ползунка:
                            // роут рейт-лимитирован (30/мин), а каждый вызов
                            // рассылает событие всем участникам на всех
                            // репликах — слать его на каждый кадр драга нельзя.
                            Slider(
                                value: Binding(
                                    get: { intensityDraft ?? store.appearance.intensity },
                                    set: { intensityDraft = $0 }
                                ),
                                in: 0...0.44,
                                onEditingChanged: { editing in
                                    guard !editing, let value = intensityDraft else { return }
                                    intensityDraft = nil
                                    commit { try await store.setIntensity(value) }
                                }
                            )
                            .tint(Cinema2026.accent)
                            // Ревью: commit молча игнорирует действие при isBusy
                            // (`guard !isBusy else { return }`), а незаблокированный
                            // ползунок терял быстрый второй жест без следа.
                            .disabled(isBusy)

                            Toggle("Движение", isOn: Binding(
                                get: { store.appearance.motionEnabled },
                                set: { newValue in commit { try await store.setMotionEnabled(newValue) } }
                            ))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Cinema2026.text)
                            .tint(Cinema2026.accent)
                            // Тумблер без этого визуально отскакивал назад:
                            // состояние читается из стора, а запрос не уходил.
                            .disabled(isBusy)
                        }
                        .padding(14)
                        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let inlineError {
                        Text(inlineError)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Cinema2026.danger)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(16)
            }
            .background(Cinema2026.background.ignoresSafeArea())
            .navigationTitle("Тема комнаты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(Cinema2026.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func themeTile(
        id: String,
        title: String,
        subtitle: String,
        colors: [String],
        premium: Bool
    ) -> some View {
        let selected = store.appearance.themeId == id
        Button {
            guard !isBusy, !selected else { return }
            commit { try await store.updateTheme(to: id) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colors.map { Color(hex: $0) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 64)
                    .overlay(alignment: .topTrailing) {
                        if premium {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Cinema2026.amber)
                                .padding(6)
                        }
                    }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Cinema2026.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Cinema2026.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func commit(_ work: @escaping () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        inlineError = nil
        Task { @MainActor in
            do {
                try await work()
            } catch {
                let text = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                inlineError = text
                onError(text)
            }
            isBusy = false
        }
    }
}

// Ревью 26.07.2026: отсюда удалены `Array[safe:]` (новое общее расширение —
// риск коллизии, единственный потребитель обошёлся проверкой indices) и
// `ProcessInfo.isLowPower` (мёртвый код: слой темы читает
// ProcessInfo.processInfo.isLowPowerModeEnabled напрямую).
