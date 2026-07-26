//  AccountDeletionView.swift
//  Plink — M39
//
//  Guideline 5.1.1(v). Мы честно говорим, что будет потеряно, и отдельно —
//  что подписка Apple НЕ отменяется автоматически. Скрывать это — верный способ
//  получить волну единиц в App Store.

import SwiftUI
import UIKit

struct AccountDeletionView: View {
    enum Step { case explain, confirm, done }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .explain
    @State private var confirmationText = ""
    @State private var isWorking = false
    @State private var errorText: String?

    private let losses = [
        "Список друзей и приглашения",
        "Всю переписку и реакции",
        "Список «Посмотреть позже» и историю комнат",
        "Подписка Plink+ НЕ отменяется автоматически — отмените её в настройках Apple ID",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background.ignoresSafeArea()
                switch step {
                case .explain: explainStep
                case .confirm: confirmStep
                case .done: doneStep
                }
            }
            .navigationTitle("Удаление аккаунта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .done {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }.foregroundStyle(V4.muted)
                    }
                }
            }
        }
    }

    private var explainStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Что будет удалено")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(V4.ink)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(losses, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(V4.danger)
                            Text(item)
                                .font(.system(size: 14))
                                .foregroundStyle(V4.ink)
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(V4.cardBG))

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(V4.accent)
                    Text("У вас будет 7 дней, чтобы вернуться — просто войдите снова. После этого данные удаляются безвозвратно.")
                        .font(.system(size: 13))
                        .foregroundStyle(V4.muted)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(V4.raised))

                Text("Альтернативы")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(V4.ink)

                Button {
                    Task { await exportData() }
                } label: {
                    Label("Скачать мои данные", systemImage: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(V4.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(V4.cardBG))
                }

                NavigationLink {
                    BlockedUsersView()
                } label: {
                    Label("Заблокировать кого-то вместо удаления", systemImage: "hand.raised")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(V4.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(V4.cardBG))
                }

                Button {
                    Haptics.warning()
                    step = .confirm
                } label: {
                    Text("Всᄅ равно удалить аккаунт")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 15).stroke(V4.danger, lineWidth: 1))
                        .foregroundStyle(V4.danger)
                }
                .padding(.top, 8)
            }
            .padding(18)
        }
    }

    private var confirmStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(V4.danger)
            Text("Введите слово УДАЛИТЬ")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(V4.ink)
            TextField("УДАЛИТЬ", text: $confirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(V4.cardBG))
                .foregroundStyle(V4.ink)
                .padding(.horizontal, 40)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13))
                    .foregroundStyle(V4.danger)
            }

            Button {
                Task { await deleteAccount() }
            } label: {
                HStack {
                    if isWorking { ProgressView().tint(.white) }
                    Text("Удалить навсегда").font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 15)
                    .fill(confirmationText == "УДАЛИТЬ" ? V4.danger : V4.line))
                .foregroundStyle(.white)
            }
            .disabled(confirmationText != "УДАЛИТЬ" || isWorking)
            .padding(.horizontal, 22)
            Spacer()
        }
    }

    private var doneStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(V4.muted)
            Text("Аккаунт удалён")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(V4.ink)
            Text("Если передумаете — войдите снова в течение 7 дней.")
                .font(.system(size: 14))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button("Закрыть") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(V4.accent)
                .padding(.top, 6)
        }
    }

    private func exportData() async {
        guard let url = URL(string: APIConfig.baseURL + "/api/users/me/export") else { return }
        var request = URLRequest(url: url)
        if let token = AuthTokenStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("plink-data.json")
        try? data.write(to: file)

        await MainActor.run {
            let controller = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.keyWindow?.rootViewController?
                .present(controller, animated: true)
        }
    }

    private func deleteAccount() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        guard let url = URL(string: APIConfig.baseURL + "/api/users/me") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = AuthTokenStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 20

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                errorText = "Не удалось удалить аккаунт. Попробуйте позже."
                return
            }
            await PushNotificationService.shared.unregister()
            AuthTokenStore.shared.clear()
            Haptics.success()
            step = .done
        } catch {
            errorText = "Нет связи с сервером."
        }
    }
}
