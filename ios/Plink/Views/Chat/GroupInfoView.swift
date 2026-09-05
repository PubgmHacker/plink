// Plink/Views/Chat/GroupInfoView.swift
//
// Настройки беседы, как в Telegram: фото и название, описание, участники с
// ролями, права участников, выход и удаление.
//
// До этого экрана беседой нельзя было управлять из приложения вообще: роли
// раздавал только сервер, аватара у группы не существовало, а «выйти» жило
// свайпом в списке. Здесь всё собрано на общих рельсах настроек
// (SettingsScaffold + SettingsCard + Settings*Row), поэтому окно выглядит
// частью приложения, а не отдельной формой.
//
// Права клиент не угадывает: сервер присылает myPermissions, и каждая
// возможность (менять инфо, звать, разжаловать, исключить, удалить) рисуется
// строго по нему. Иконки не зависят от темы — фиксированные смысловые цвета.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

/// Какое поле правим в шите — одна форма на название и описание.
private enum GroupInfoField: String, Identifiable {
    case title
    case about

    var id: String { rawValue }
    var label: String { self == .title ? "Название беседы" : "Описание" }
    var hint: String {
        self == .title
            ? "Как беседа называется в списке чатов"
            : "Пара слов о беседе — её видят все участники"
    }
    var placeholder: String { self == .title ? "Киновечер \u{1F3AC}" : "О чём эта беседа" }
    var limit: Int { self == .title ? 60 : 240 }
    var multiline: Bool { self == .about }
}

/// Счётные строки беседы. Живут отдельно от экрана, потому что то же
/// «12 участников» подписывает беседу в шапке чата.
enum GroupCopy {
    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        RussianPlural.counted(count, one, few, many)
    }

    static func members(_ count: Int) -> String {
        plural(count, "участник", "участника", "участников")
    }

    static func slots(_ count: Int) -> String {
        plural(count, "место", "места", "мест")
    }

    static func messages(_ count: Int) -> String {
        plural(count, "сообщение", "сообщения", "сообщений")
    }
}

struct GroupInfoView: View {
    let groupId: String
    /// Название, известное до загрузки карточки — шапка не мигает пустотой.
    let titleHint: String
    /// Меня в беседе больше нет (вышел или удалил её) — закрыть и сам чат.
    var onLeft: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = GroupChatService.shared
    @ObservedObject private var muteStore = ChatMuteStore.shared

    @State private var detail: GroupDetailDTO?
    @State private var isLoading = true
    @State private var busy = false
    @State private var notice: String?

    @State private var editField: GroupInfoField?
    @State private var photoItem: PhotosPickerItem?
    @State private var memberAction: GroupMemberDTO?
    @State private var openProfile: GroupMemberDTO?
    @State private var showAddMembers = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false

    // MARK: Производные

    private var currentTitle: String { detail?.title ?? titleHint }
    private var members: [GroupMemberDTO] { detail?.members ?? [] }
    private var my: GroupMyPermissionsDTO? { detail?.myPermissions }
    private var muteKey: String { "grp-\(groupId)" }
    private var hasPhoto: Bool { (detail?.avatarVersion ?? 0) > 0 }
    private var canChangeInfo: Bool { my?.canChangeInfo ?? false }

    private var subtitleText: String {
        guard let detail else { return "Загружаем карточку\u{2026}" }
        var parts = [GroupCopy.members(detail.memberCount)]
        if let count = detail.messageCount, count > 0 {
            parts.append(GroupCopy.messages(count))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        SettingsScaffold(
            title: currentTitle,
            subtitle: subtitleText,
            eyebrow: "Беседа",
            showsClose: true
        ) {
            if let notice {
                infoBanner(icon: "exclamationmark.triangle.fill", text: notice, tone: .warning)
            }
            if detail == nil {
                if isLoading {
                    loadingCard
                } else {
                    failureCard
                }
            } else {
                avatarCard
                infoSection
                notificationsSection
                membersSection
                if my?.canManagePermissions == true { permissionsSection }
                dangerSection
                footnote
            }
        }
        .task { await reload() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(item) }
        }
        .sheet(item: $editField) { field in
            GroupFieldEditSheet(
                field: field,
                initial: field == .title ? currentTitle : (detail?.description ?? "")
            ) { value in
                await save(field: field, value: value)
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddMembers) {
            GroupAddMembersSheet(
                groupId: groupId,
                existing: Set(members.map(\.id)),
                maxMembers: detail?.maxMembers,
                currentCount: detail?.memberCount ?? members.count
            ) {
                await reload()
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $openProfile) { member in
            NavigationStack {
                FriendProfileView(userId: member.id, usernameHint: member.username)
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            memberAction?.name ?? "",
            isPresented: Binding(get: { memberAction != nil }, set: { if !$0 { memberAction = nil } }),
            titleVisibility: .visible
        ) {
            memberActions
        }
        .confirmationDialog(
            "Выйти из беседы?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button("Выйти", role: .destructive) { Task { await leave() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Переписка останется у остальных участников. Вернуться можно только по приглашению.")
        }
        .confirmationDialog(
            "Удалить беседу у всех?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить беседу", role: .destructive) { Task { await deleteGroup() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Беседа и все сообщения исчезнут у каждого участника. Отменить нельзя.")
        }
    }
}

// MARK: - Секции

private extension GroupInfoView {

    var loadingCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                ProgressView().tint(V4.muted)
                Text("Загружаем участников и права\u{2026}")
                    .font(.system(size: 14))
                    .foregroundStyle(V4.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
    }

    var failureCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Карточка беседы не загрузилась")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(V4.ink)
                Text(service.errorMessage ?? "Проверьте связь и попробуйте ещё раз.")
                    .font(.system(size: 13))
                    .foregroundStyle(V4.muted)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsPrimaryButton(title: "Повторить", isLoading: isLoading) {
                    Task { await reload() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    /// Фото беседы. Тап по строке — галерея; ниже, если фото есть, снятие.
    var avatarCard: some View {
        SettingsCard {
            if canChangeInfo {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    avatarRow(actionable: true)
                }
                .buttonStyle(.plain)
                if hasPhoto {
                    SettingsNavRow(
                        icon: "trash",
                        title: "Удалить фото беседы",
                        iconColor: V4.danger,
                        showsChevron: false
                    ) {
                        Task { await clearAvatar() }
                    }
                }
            } else {
                avatarRow(actionable: false)
            }
        }
    }

    func avatarRow(actionable: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                PlinkGroupAvatar(
                    groupId: groupId,
                    title: currentTitle,
                    avatarVersion: detail?.avatarVersion,
                    size: 64
                )
                if actionable {
                    // Плашка «камера» — нейтральная, как все иконки после 26.08.
                    ZStack {
                        Circle().fill(V4.surface)
                        Circle().stroke(Color.white.opacity(0.10), lineWidth: 1)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(V4.ink)
                    }
                    .frame(width: 22, height: 22)
                    .offset(x: 3, y: 3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Фото беседы")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(V4.ink)
                Text(avatarHint(actionable: actionable))
                    .font(.system(size: 12))
                    .foregroundStyle(V4.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if busy { ProgressView().tint(V4.muted) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    func avatarHint(actionable: Bool) -> String {
        if !actionable { return "Менять фото и название могут владелец и админы" }
        return hasPhoto ? "Нажмите, чтобы заменить" : "Нажмите и выберите картинку из галереи"
    }

    var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: "Информация")
            SettingsCard {
                SettingsInfoRow(
                    icon: "textformat",
                    title: "Название",
                    value: currentTitle,
                    iconColor: Color(hex: 0x3B82F6),
                    actionTitle: canChangeInfo ? "Изменить" : nil,
                    action: canChangeInfo ? { editField = .title } : nil
                )
                SettingsInfoRow(
                    icon: "text.alignleft",
                    title: "Описание",
                    value: descriptionValue,
                    iconColor: Color(hex: 0xA855F7),
                    actionTitle: canChangeInfo ? (hasDescription ? "Изменить" : "Добавить") : nil,
                    action: canChangeInfo ? { editField = .about } : nil
                )
                SettingsInfoRow(
                    icon: "person.badge.key.fill",
                    title: "Моя роль",
                    value: GroupInfoView.roleName(detail?.myRole ?? "member"),
                    iconColor: Color(hex: 0xF59E0B)
                )
                if let created = detail?.createdDate {
                    SettingsInfoRow(
                        icon: "calendar",
                        title: "Создана",
                        value: GroupInfoView.dateText(created),
                        iconColor: Color(hex: 0x6366F1)
                    )
                }
            }
        }
    }

    var hasDescription: Bool {
        !(detail?.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var descriptionValue: String {
        let raw = (detail?.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Не задано" : raw
    }

    var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: "Уведомления")
            SettingsCard {
                SettingsToggleRow(
                    icon: "bell.slash.fill",
                    title: "Без звука",
                    subtitle: "Беседа перестанет присылать пуши на это устройство",
                    iconColor: V4.amber,
                    isOn: Binding(
                        get: { muteStore.isMuted(muteKey) },
                        set: { muteStore.setMuted(muteKey, muted: $0) }
                    )
                )
            }
        }
    }
}

// MARK: - Участники и права

private extension GroupInfoView {

    var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: "Участники \u{00B7} \(detail?.memberCount ?? members.count)")
            SettingsCard {
                if my?.canInvite == true {
                    SettingsNavRow(
                        icon: "person.badge.plus",
                        title: "Добавить участников",
                        subtitle: inviteSubtitle,
                        iconColor: Color(hex: 0x22C55E)
                    ) {
                        HapticManager.selection()
                        showAddMembers = true
                    }
                }
                ForEach(members) { member in
                    memberRow(member)
                }
            }
        }
    }

    var inviteSubtitle: String {
        guard let max = detail?.maxMembers, max > 0 else { return "Из списка друзей" }
        let left = max - (detail?.memberCount ?? members.count)
        return left > 0 ? "Свободно ещё \(GroupCopy.slots(left)) из \(max)" : "Беседа заполнена — максимум \(GroupCopy.members(max))"
    }

    func memberRow(_ member: GroupMemberDTO) -> some View {
        Button {
            HapticManager.selection()
            memberAction = member
        } label: {
            HStack(spacing: 12) {
                PlinkStableAvatar(
                    url: PlinkAvatarURL.stable(userId: member.id, stored: member.avatarURL),
                    letter: GroupInfoView.letter(member.name),
                    size: 38,
                    userId: member.id
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(member.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(V4.ink)
                            .lineLimit(1)
                        if member.isOwner || member.isAdmin {
                            roleBadge(owner: member.isOwner)
                        }
                    }
                    Text(GroupInfoView.presence(member))
                        .font(.system(size: 12))
                        .foregroundStyle(member.isOnline ? Color(hex: 0x22C55E) : V4.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(V4.muted.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Роль подписана словом, а не цветом темы: владелец — янтарный, админ — синий.
    func roleBadge(owner: Bool) -> some View {
        let tint = owner ? V4.amber : Color(hex: 0x3B82F6)
        return Text(owner ? "владелец" : "админ")
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 1))
    }

    /// Меню по участнику: профиль, роль, исключение. Каждая кнопка живёт
    /// строго по правам с сервера — иначе кнопка обещает то, что вернёт 403.
    @ViewBuilder
    var memberActions: some View {
        if let member = memberAction {
            Button("Открыть профиль") {
                let target = member
                memberAction = nil
                openProfile = target
            }
            if my?.canManageAdmins == true, !member.isOwner, member.id != detail?.ownerID {
                if member.isAdmin {
                    Button("Разжаловать до участника") {
                        let target = member
                        memberAction = nil
                        Task { await setRole(target, role: "member") }
                    }
                } else {
                    Button("Назначить администратором") {
                        let target = member
                        memberAction = nil
                        Task { await setRole(target, role: "admin") }
                    }
                }
            }
            if canRemove(member) {
                Button("Исключить из беседы", role: .destructive) {
                    let target = member
                    memberAction = nil
                    Task { await remove(target) }
                }
            }
            Button("Отмена", role: .cancel) { memberAction = nil }
        }
    }

    /// Владельца не исключают; админ не исключает админа; себя — через «выйти».
    func canRemove(_ member: GroupMemberDTO) -> Bool {
        guard my?.canRemoveMembers == true else { return false }
        if member.isOwner { return false }
        if member.id == detail?.ownerID { return false }
        if detail?.myRole != "owner" && member.isAdmin { return false }
        return true
    }

    var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: "Права участников")
            SettingsCard {
                SettingsToggleRow(
                    icon: "person.badge.plus",
                    title: "Добавлять участников",
                    subtitle: "Обычные участники смогут звать друзей",
                    iconColor: Color(hex: 0x22C55E),
                    isOn: permissionBinding(
                        get: { $0.membersCanInvite },
                        patch: { .init(membersCanInvite: $0) },
                        apply: { $0.membersCanInvite = $1 }
                    ),
                    enabled: !busy
                )
                SettingsToggleRow(
                    icon: "photo",
                    title: "Отправлять фото",
                    subtitle: "Обычные участники смогут слать картинки",
                    iconColor: Color(hex: 0x6366F1),
                    isOn: permissionBinding(
                        get: { $0.membersCanSendMedia },
                        patch: { .init(membersCanSendMedia: $0) },
                        apply: { $0.membersCanSendMedia = $1 }
                    ),
                    enabled: !busy
                )
                SettingsToggleRow(
                    icon: "pencil",
                    title: "Менять название и фото",
                    subtitle: "Обычные участники смогут править карточку беседы",
                    iconColor: Color(hex: 0xA855F7),
                    isOn: permissionBinding(
                        get: { $0.membersCanChangeInfo },
                        patch: { .init(membersCanChangeInfo: $0) },
                        apply: { $0.membersCanChangeInfo = $1 }
                    ),
                    enabled: !busy
                )
            }
        }
    }

    /// Тумблер прав: рисуем сразу, шлём PATCH, при отказе откатываем — без
    /// этого переключатель врал бы до следующей загрузки экрана.
    func permissionBinding(
        get: @escaping (GroupPermissionsDTO) -> Bool,
        patch: @escaping (Bool) -> GroupChatService.GroupPatch,
        apply: @escaping (inout GroupPermissionsDTO, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { detail.map { get($0.permissions) } ?? false },
            set: { value in
                guard var current = detail else { return }
                apply(&current.permissions, value)
                detail = current
                Task {
                    busy = true
                    notice = nil
                    let result = await service.patch(groupId: groupId, patch(value))
                    busy = false
                    if let result {
                        detail?.permissions = result.permissions
                    } else {
                        var reverted = current
                        apply(&reverted.permissions, !value)
                        detail = reverted
                        notice = service.errorMessage ?? "Права не сохранились — попробуй ещё раз."
                    }
                }
            }
        )
    }

    var dangerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: "Опасная зона")
            SettingsCard {
                SettingsNavRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Выйти из беседы",
                    subtitle: detail?.myRole == "owner"
                        ? "Владелец уходит — беседа остаётся у остальных"
                        : "Беседа исчезнет из вашего списка чатов",
                    iconColor: V4.danger,
                    showsChevron: false
                ) {
                    HapticManager.selection()
                    confirmLeave = true
                }
                if my?.canDeleteGroup == true {
                    SettingsNavRow(
                        icon: "trash.fill",
                        title: "Удалить беседу",
                        subtitle: "У всех участников, вместе со всеми сообщениями",
                        iconColor: V4.danger,
                        showsChevron: false
                    ) {
                        HapticManager.selection()
                        confirmDelete = true
                    }
                }
            }
        }
    }

    var footnote: some View {
        Text("Фото и название проходят ИИ-модерацию: NSFW и мат сервер не примет. «Без звука» — настройка этого устройства.")
            .font(.system(size: 11))
            .foregroundStyle(V4.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

// MARK: - Действия

private extension GroupInfoView {

    func reload() async {
        isLoading = true
        service.errorMessage = nil
        let loaded = await service.loadDetail(groupId: groupId)
        isLoading = false
        if let loaded {
            detail = loaded
        } else if detail == nil {
            notice = service.errorMessage
        }
    }

    func save(field: GroupInfoField, value: String) async -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if field == .title, trimmed.isEmpty {
            notice = "Название не может быть пустым."
            return false
        }
        busy = true
        notice = nil
        service.errorMessage = nil
        let patch: GroupChatService.GroupPatch = field == .title
            ? .init(title: trimmed)
            // Пустое описание — это стирание: null, а не отсутствие ключа.
            : .init(description: Optional.some(trimmed.isEmpty ? nil : trimmed))
        let result = await service.patch(groupId: groupId, patch)
        busy = false
        guard let result else {
            notice = service.errorMessage ?? "Изменения не сохранились."
            return false
        }
        detail?.title = result.title
        detail?.description = result.description
        HapticManager.notification(.success)
        return true
    }

    func uploadAvatar(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard !busy else { return }
        busy = true
        notice = nil
        service.errorMessage = nil
        defer { busy = false }

        guard let raw = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: raw) else {
            notice = "Не удалось прочитать картинку из галереи."
            return
        }
        guard let jpeg = GroupInfoView.squareJPEG(image) else {
            notice = "Не удалось обработать изображение."
            return
        }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        let result = await service.patch(groupId: groupId, .init(avatarData: Optional.some(dataURL)))
        guard let result else {
            notice = service.errorMessage ?? "Фото не загрузилось."
            return
        }
        detail?.avatarVersion = result.avatarVersion
        HapticManager.notification(.success)
    }

    func clearAvatar() async {
        guard !busy else { return }
        busy = true
        notice = nil
        service.errorMessage = nil
        // null в avatarData — «стереть фото», беседа вернётся к букве.
        let result = await service.patch(groupId: groupId, .init(avatarData: Optional.some(nil)))
        busy = false
        guard let result else {
            notice = service.errorMessage ?? "Фото не удалилось."
            return
        }
        detail?.avatarVersion = result.avatarVersion
        HapticManager.selection()
    }

    func setRole(_ member: GroupMemberDTO, role: String) async {
        busy = true
        notice = nil
        service.errorMessage = nil
        let ok = await service.setRole(groupId: groupId, userId: member.id, role: role)
        busy = false
        if ok {
            HapticManager.notification(.success)
            await reload()
        } else {
            notice = service.errorMessage ?? "Роль не изменилась."
        }
    }

    func remove(_ member: GroupMemberDTO) async {
        busy = true
        notice = nil
        service.errorMessage = nil
        let ok = await service.removeMember(groupId: groupId, userId: member.id)
        busy = false
        if ok {
            HapticManager.notification(.success)
            await reload()
        } else {
            notice = service.errorMessage ?? "Участник не исключён."
        }
    }

    func leave() async {
        busy = true
        notice = nil
        service.errorMessage = nil
        let ok = await service.leave(groupId: groupId)
        busy = false
        if ok {
            onLeft?()
            dismiss()
        } else {
            notice = service.errorMessage ?? "Выйти не получилось."
        }
    }

    func deleteGroup() async {
        busy = true
        notice = nil
        service.errorMessage = nil
        let ok = await service.deleteGroup(groupId: groupId)
        busy = false
        if ok {
            onLeft?()
            dismiss()
        } else {
            notice = service.errorMessage ?? "Беседу не удалось удалить."
        }
    }
}

// MARK: - Хелперы

private extension GroupInfoView {

    /// Аватар беседы режем в квадрат и жмём под лимит бэкенда (2 МБ байтов).
    static func squareJPEG(_ image: UIImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        let cropped: UIImage
        if let cg = image.cgImage, side > 0 {
            let scale = image.scale
            let rect = CGRect(
                x: ((image.size.width - side) / 2) * scale,
                y: ((image.size.height - side) / 2) * scale,
                width: side * scale,
                height: side * scale
            )
            cropped = cg.cropping(to: rect).map { UIImage(cgImage: $0, scale: scale, orientation: image.imageOrientation) } ?? image
        } else {
            cropped = image
        }
        // 512×512 хватает любому кругу в списках; больше — только вес.
        let target = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            cropped.draw(in: CGRect(origin: .zero, size: target))
        }
        var quality: CGFloat = 0.85
        var jpeg = resized.jpegData(compressionQuality: quality)
        while let data = jpeg, data.count > 1_400_000, quality > 0.3 {
            quality -= 0.15
            jpeg = resized.jpegData(compressionQuality: quality)
        }
        return jpeg
    }

    static func roleName(_ role: String) -> String {
        switch role {
        case "owner": return "Владелец"
        case "admin": return "Администратор"
        default: return "Участник"
        }
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    static func letter(_ name: String) -> String {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") { trimmed = String(trimmed.dropFirst()) }
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    /// Строка присутствия участника. Онлайн — коротко «в сети»: приписка про
    /// «можно смотреть вместе» из лички в списке из двадцати человек лишняя.
    static func presence(_ member: GroupMemberDTO) -> String {
        if member.isDeleted == true { return "аккаунт удалён" }
        if member.isOnline { return "в сети" }
        return FriendPresence.displayText(isOnline: false, lastSeenAt: member.lastSeenDate)
    }
}

// MARK: - Правка названия и описания

/// Одна форма на оба текстовых поля беседы: заголовок, счётчик символов,
/// сохранение. Отдельные экраны под «название» и «описание» отличались бы
/// только строкой — и разъехались бы при первой же правке.
private struct GroupFieldEditSheet: View {
    let field: GroupInfoField
    let initial: String
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var value: String = ""
    @State private var saving = false
    @FocusState private var focused: Bool

    private var trimmed: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        if saving { return false }
        if field == .title && trimmed.isEmpty { return false }
        return trimmed != initial.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        SettingsScaffold(
            title: field.label,
            subtitle: field.hint,
            eyebrow: "Беседа",
            showsClose: true
        ) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    if field.multiline {
                        TextField(field.placeholder, text: $value, axis: .vertical)
                            .lineLimit(3...7)
                            .font(.system(size: 15))
                            .foregroundStyle(V4.ink)
                            .focused($focused)
                    } else {
                        TextField(field.placeholder, text: $value)
                            .font(.system(size: 15))
                            .foregroundStyle(V4.ink)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit { if canSave { Task { await commit() } } }
                    }
                    HStack {
                        Spacer()
                        Text("\(value.count)/\(field.limit)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(value.count >= field.limit ? V4.amber : V4.muted)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }

            SettingsPrimaryButton(title: "Сохранить", isLoading: saving) {
                Task { await commit() }
            }
            .opacity(canSave ? 1 : 0.45)
            .disabled(!canSave)

            if field == .about && !trimmed.isEmpty {
                Button {
                    value = ""
                    Task { await commit() }
                } label: {
                    Text("Удалить описание")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(V4.danger)
                }
                .buttonStyle(.plain)
                .disabled(saving)
            }
        }
        .onAppear {
            value = String(initial.prefix(field.limit))
            focused = true
        }
        .onChange(of: value) { _, new in
            // Обрезаем на вводе, а не отказом при сохранении: лимит держит сервер.
            if new.count > field.limit {
                value = String(new.prefix(field.limit))
            }
        }
    }

    private func commit() async {
        saving = true
        let ok = await onSave(value)
        saving = false
        if ok { dismiss() }
    }
}

// MARK: - Добавление участников

/// Друзья, которых ещё нет в беседе. Тот же язык выбора, что в «Новой беседе».
private struct GroupAddMembersSheet: View {
    let groupId: String
    let existing: Set<String>
    let maxMembers: Int?
    let currentCount: Int
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = GroupChatService.shared
    @ObservedObject private var friendManager = FriendManager.shared
    @State private var selected: Set<String> = []
    @State private var adding = false
    @State private var notice: String?

    private var candidates: [Friend] {
        friendManager.friends
            .filter { !existing.contains($0.id) && !$0.deleted }
            .sorted { lhs, rhs in
                if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    private var slotsLeft: Int? {
        guard let maxMembers, maxMembers > 0 else { return nil }
        return max(0, maxMembers - currentCount)
    }

    var body: some View {
        SettingsScaffold(
            title: "Добавить участников",
            subtitle: subtitle,
            eyebrow: "Беседа",
            showsClose: true
        ) {
            if let notice {
                infoBanner(icon: "exclamationmark.triangle.fill", text: notice, tone: .warning)
            }
            if candidates.isEmpty {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Некого добавить")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(V4.ink)
                        Text("Все друзья уже в беседе. Добавьте друзей — и они появятся здесь.")
                            .font(.system(size: 13))
                            .foregroundStyle(V4.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
            } else {
                SettingsCard {
                    ForEach(candidates) { friend in
                        candidateRow(friend)
                    }
                }
                SettingsPrimaryButton(
                    title: selected.isEmpty ? "Выберите друзей" : "Добавить \(selected.count)",
                    isLoading: adding
                ) {
                    Task { await add() }
                }
                .opacity(selected.isEmpty || adding ? 0.45 : 1)
                .disabled(selected.isEmpty || adding)
            }
        }
        .task {
            if friendManager.friends.isEmpty { await friendManager.loadFriends() }
        }
    }

    private var subtitle: String {
        if let slotsLeft {
            return slotsLeft > 0 ? "Свободно ещё \(GroupCopy.slots(slotsLeft))" : "Беседа заполнена"
        }
        return "Из вашего списка друзей"
    }

    private func candidateRow(_ friend: Friend) -> some View {
        let picked = selected.contains(friend.id)
        return Button {
            HapticManager.selection()
            if picked {
                selected.remove(friend.id)
            } else if let slotsLeft, selected.count >= slotsLeft {
                notice = "Больше не поместится: лимит беседы \(GroupCopy.members(maxMembers ?? 0))."
            } else {
                selected.insert(friend.id)
                notice = nil
            }
        } label: {
            HStack(spacing: 12) {
                PlinkStableAvatar(
                    url: PlinkAvatarURL.stable(userId: friend.id, stored: friend.avatarURL),
                    letter: friend.initials,
                    size: 38,
                    userId: friend.id
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(1)
                    if let secondary = friend.secondaryLine {
                        Text(secondary.text)
                            .font(.system(size: 12))
                            .foregroundStyle(secondary.isOnline ? Color(hex: 0x22C55E) : V4.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                // Галочка — состояние выбора, единственное место темы на экране.
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(picked ? V4Theme.saved.accentColor : V4.muted.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func add() async {
        guard !selected.isEmpty else { return }
        adding = true
        notice = nil
        service.errorMessage = nil
        let ok = await service.addMembers(groupId: groupId, userIds: Array(selected))
        adding = false
        if ok {
            HapticManager.notification(.success)
            await onDone()
            dismiss()
        } else {
            notice = service.errorMessage ?? "Не получилось добавить участников."
        }
    }
}
