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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
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
            self.error = "Не удалось войти: \(err.localizedDescription)"
        }
    }
}
