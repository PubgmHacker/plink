// Plink/Views/Home/ScheduleSessionSheet.swift
// Шторка планирования совместного сеанса — название, дата/время,
// напоминание и добавление в календарь. Список ближайших сеансов снизу.

import SwiftUI

struct ScheduleSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = ScheduledSessionsService.shared

    @State private var title = ""
    @State private var startsAt = Date().addingTimeInterval(3600)
    @State private var remindBefore = true
    @State private var addToCalendar = false
    @State private var saving = false

    private let accent = Color(red: 0.55, green: 0.45, blue: 1.0)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Название
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Что смотрим")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("Например: Интерстеллар с ребятами", text: $title)
                            .textFieldStyle(.plain)
                            .padding(14)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                    }

                    // Дата и время
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Когда")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        DatePicker(
                            "",
                            selection: $startsAt,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                        .tint(accent)
                        .padding(10)
                        .background(.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Опции
                    VStack(spacing: 0) {
                        Toggle(isOn: $remindBefore) {
                            Label("Напомнить за 15 минут", systemImage: "bell.badge")
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .tint(accent)
                        .padding(.vertical, 12)
                        Divider().overlay(.white.opacity(0.08))
                        Toggle(isOn: $addToCalendar) {
                            Label("Добавить в календарь", systemImage: "calendar.badge.plus")
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .tint(accent)
                        .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 14)
                    .background(.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Кнопка
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if saving { ProgressView().tint(.white) }
                            Text("Запланировать")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(titleTrimmed.isEmpty ? Color.gray.opacity(0.3) : accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(titleTrimmed.isEmpty || saving)

                    // Ближайшие сеансы
                    if !service.sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Запланировано")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                            ForEach(service.sessions) { session in
                                HStack(spacing: 12) {
                                    Image(systemName: "popcorn")
                                        .font(.system(size: 16))
                                        .foregroundStyle(accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(session.startsAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                    Spacer()
                                    Button {
                                        service.cancel(session.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                                .background(.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.09).ignoresSafeArea())
            .navigationTitle("Запланировать сеанс")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(accent)
                }
            }
        }
    }

    private var titleTrimmed: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard !titleTrimmed.isEmpty else { return }
        saving = true
        await service.schedule(
            ScheduledSession(title: titleTrimmed, startsAt: startsAt),
            remindMinutesBefore: remindBefore ? 15 : 0,
            addToCalendar: addToCalendar
        )
        saving = false
        title = ""
        HapticManager.impact(.medium)
    }
}
