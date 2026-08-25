//
//  JoinRoomSheet.swift
//  Plink
//
//  Join room by code — accessible from Rooms tab header.
//

import SwiftUI

struct JoinRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var apiClient: APIClient
    var onJoined: (Room) -> Void
    var initialCode: String = ""
    var startWithPassword: Bool = false

    @State private var roomCode = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?
    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            Cinema2026.background.ignoresSafeArea().overlay {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizationManager.shared.string(.jrCode))
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.1)
                            .foregroundStyle(Cinema2026.secondary)
                        TextField("ABC123", text: $roomCode)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Cinema2026.text)
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 20)
                            .frame(minHeight: 64)
                            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Cinema2026.divider, lineWidth: 0.5))
                            .onChange(of: roomCode) { _, new in
                                roomCode = String(new.prefix(6)).uppercased()
                            }
                    }

                    if showPassword {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LocalizationManager.shared.string(.jrPassword))
                                .font(.system(size: 11, weight: .heavy))
                                .tracking(1.1)
                                .foregroundStyle(Cinema2026.secondary)
                            SecureField("Пароль", text: $password)
                                .font(.system(size: 16))
                                .foregroundStyle(Cinema2026.text)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 52)
                                .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))
                        }
                    }

                    if !showPassword {
                        Button {
                            withAnimation { showPassword = true }
                        } label: {
                            Text(LocalizationManager.shared.string(.jrHasPassword))
                                .font(.system(size: 13))
                                .foregroundStyle(Cinema2026.accent)
                        }
                    }

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Cinema2026.danger)
                            .padding(12)
                            .background(Cinema2026.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }

                    Spacer()

                    Button {
                        Task { await join() }
                    } label: {
                        HStack {
                            if loading {
                                ProgressView().tint(Cinema2026.background)
                            }
                            Text(LocalizationManager.shared.string(.jrJoin))
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Cinema2026.background)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(roomCode.count == 6 ? Cinema2026.accent : Cinema2026.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(roomCode.count != 6 || loading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .navigationTitle("Войти по коду")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
            }
            .onAppear {
                if roomCode.isEmpty, !initialCode.isEmpty {
                    roomCode = String(initialCode.prefix(6)).uppercased()
                }
                if startWithPassword { showPassword = true }
            }
        }
    }

    private func join() async {
        loading = true
        error = nil
        defer { loading = false }

        do {
            let room = try await RoomService(api: apiClient).joinRoom(
                code: roomCode,
                password: password.isEmpty ? nil : password
            )
            HapticManager.roomJoined()
            onJoined(room)
            dismiss()
        } catch let err {
            HapticManager.errorOccurred()
            if JoinRoomErrorCopy.isPasswordRequired(err) {
                showPassword = true
            }
            self.error = JoinRoomErrorCopy.message(for: err)
        }
    }
}

enum JoinRoomErrorCopy {
    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .notFound:
                return "Нет комнаты с таким кодом. Проверьте код и попробуйте снова."
            case .conflict:
                return "Комната заполнена."
            case .networkError, .invalidResponse, .decodingError:
                return "Нет сети или сервер не отвечает. Попробуйте ещё раз."
            case .serverError(_, let message):
                return humanize(message)
            case .invalidCredentials(let message):
                return humanize(message)
            default:
                return humanize(apiError.localizedDescription)
            }
        }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "Нет подключения к интернету."
        }
        return humanize(error.localizedDescription)
    }

    static func isPasswordRequired(_ error: Error) -> Bool {
        let text = ((error as? APIError)?.localizedDescription ?? error.localizedDescription).lowercased()
        return text.contains("парол") || text.contains("password")
    }

    private static func humanize(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.localizedCaseInsensitiveContains("не найден") || text.localizedCaseInsensitiveContains("not found") {
            return "Нет комнаты с таким кодом. Проверьте код и попробуйте снова."
        }
        if text.localizedCaseInsensitiveContains("заполнен") || text.localizedCaseInsensitiveContains("full") {
            return "Комната заполнена."
        }
        if text.localizedCaseInsensitiveContains("друзей") || text.localizedCaseInsensitiveContains("friends") {
            return "Комната только для друзей хозяина."
        }
        if text.localizedCaseInsensitiveContains("неверный пароль") {
            return "Неверный пароль комнаты."
        }
        if text.localizedCaseInsensitiveContains("требуется пароль") {
            return "У комнаты есть пароль. Введите его ниже."
        }
        if text.isEmpty || text.localizedCaseInsensitiveContains("unknown") {
            return "Не удалось войти в комнату. Проверьте код и попробуйте снова."
        }
        return text
    }
}

