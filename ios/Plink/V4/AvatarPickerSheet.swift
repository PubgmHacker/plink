//
//  AvatarPickerSheet.swift
//  Plink
//
//  Выбор аватара: PhotosUI → кроп → загрузка на сервер → локальное сохранение.
//  Вынесен из V4ProfileViewLive.swift: файл упёрся в лимит длины SwiftLint.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - AvatarPickerSheet (PhotosUI + server upload + local persist)

struct AvatarPickerSheet: View {
    var store: V4ProfileStore?
    /// Шит рисовался акцентом Cinema2026 — третьей палитрой,
    /// не связанной с темой приложения. Тема приходит от родителя.
    var theme: V4Theme = .electric
    var onAvatarChanged: ((URL) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var uploading = false
    @State private var uploadError: String?
    @State private var uploadOK = false
    @State private var photoItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var selectedDefault: String? = nil
    @State private var pendingImage: UIImage?
    @State private var showPhotosPicker = false
    @State private var photosDeniedAlert = false

    private let defaultAvatars = ["avatar_default", "avatar_blue", "avatar_purple"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview
                Group {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable().scaledToFill()
                    } else if let local = store?.localAvatarImage {
                        Image(uiImage: local)
                            .resizable().scaledToFill()
                    } else if let avatarURL = store?.avatarURL {
                        AsyncImage(url: avatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(V4.surface)
                                .overlay(Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(V4.muted))
                        }
                    } else {
                        Circle().fill(V4.surface)
                            .overlay(Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(V4.muted))
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(uploadOK ? Color.green : theme.accentColor, lineWidth: 3))

                if uploadOK {
                    Label("Сохранено на сервере", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                }

                Text(LocalizationManager.shared.string(.vpStandard)).font(.system(size: 13, weight: .bold)).foregroundStyle(V4.muted)
                HStack(spacing: 16) {
                    ForEach(defaultAvatars, id: \.self) { name in
                        Button {
                            selectedDefault = name
                            if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Avatars")
                                ?? Bundle.main.url(forResource: name, withExtension: "jpg"),
                               let data = try? Data(contentsOf: url),
                               let img = UIImage(data: data) {
                                previewImage = img
                                pendingImage = img
                                uploadOK = false
                                Task { await saveAndUpload(img) }
                            }
                        } label: {
                            presetThumb(name: name)
                        }
                        .buttonStyle(.plain)
                        .disabled(uploading)
                    }
                }

                Rectangle().fill(V4.line).frame(height: 0.5).padding(.horizontal, 24)

                // System iOS photo dialog (if first time) → then PhotosPicker
                // Вторичное действие — стекло; единственная белая CTA шита — «Готово».
                Button {
                    Task { await pickFromGallery() }
                } label: {
                    HStack(spacing: 8) {
                        if uploading {
                            ProgressView().tint(V4.ink)
                        } else {
                            Image(systemName: "photo.on.rectangle")
                        }
                        Text(uploading ? "Сохраняем…" : "Выбрать из галереи")
                    }
                }
                .buttonStyle(PlinkGlassButtonStyle(tint: theme.accentColor, height: 52, cornerRadius: 14))
                .padding(.horizontal, 24)
                .disabled(uploading)
                .photosPicker(isPresented: $showPhotosPicker, selection: $photoItem, matching: .images)
                .onChange(of: photoItem) { _, newItem in
                    Task { await loadPhoto(newItem) }
                }
                .alert("Фото недоступны", isPresented: $photosDeniedAlert) {
                    Button("Настройки") { PlinkPermissions.openAppSettings() }
                    Button("Отмена", role: .cancel) {}
                } message: {
                    Text(LocalizationManager.shared.string(.phPhotoLimited))
                }

                if let err = uploadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(V4.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                SettingsPrimaryButton(title: "Готово", isLoading: uploading) {
                    Task { await doneTapped() }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding(.top, 32)
            .background {
                ZStack {
                    V4.canvas
                    RadialGradient(
                        colors: [theme.accentColor.opacity(0.10), .clear],
                        center: UnitPoint(x: 0.5, y: 0),
                        startRadius: 0,
                        endRadius: 420
                    )
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Аватар")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func presetThumb(name: String) -> some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Avatars")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg"),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable().scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().stroke(selectedDefault == name ? theme.accentColor : V4.line, lineWidth: selectedDefault == name ? 3 : 1))
        } else {
            Circle()
                .fill(V4.surface)
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "person.fill").font(.system(size: 20)).foregroundStyle(V4.muted))
        }
    }

    private func doneTapped() async {
        // If user picked something but upload not finished / failed — retry then close
        if let pending = pendingImage, !uploadOK {
            await saveAndUpload(pending)
            if uploadOK { dismiss() }
            return
        }
        dismiss()
    }

    /// 1) If never asked → system iOS permission sheet immediately.
    /// 2) Then always open PhotosPicker (works even after «Не разрешать»).
    private func pickFromGallery() async {
        let access = await PlinkPermissions.preparePhotoPicker()
        switch access {
        case .authorized, .systemPickerOnly:
            // Small yield so the permission sheet can dismiss before PHPicker.
            try? await Task.sleep(nanoseconds: 150_000_000)
            showPhotosPicker = true
        case .blocked:
            photosDeniedAlert = true
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        uploading = true
        uploadError = nil
        uploadOK = false
        defer { uploading = false }
        selectedDefault = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                uploadError = "Не удалось загрузить фото"
                return
            }
            guard let image = UIImage(data: data) else {
                uploadError = "Неверный формат изображения"
                return
            }
            let resized = resizeToSquare(image, size: 512)
            previewImage = resized
            pendingImage = resized
            await saveAndUpload(resized)
        } catch {
            uploadError = "Ошибка: \(error.localizedDescription)"
        }
    }

    private func resizeToSquare(_ image: UIImage, size: CGFloat) -> UIImage {
        let originalSize = image.size
        let shortest = min(originalSize.width, originalSize.height)
        let offsetX = (originalSize.width - shortest) / 2
        let offsetY = (originalSize.height - shortest) / 2
        let cropRect = CGRect(x: offsetX, y: offsetY, width: shortest, height: shortest)
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return image }
        let cropped = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            cropped.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    /// Compress + POST /users/me/avatar + local persist via store.applyAvatar
    private func saveAndUpload(_ image: UIImage) async {
        uploading = true
        uploadError = nil
        defer { uploading = false }

        // Always keep local copy first so "Готово" never loses the photo
        var quality: CGFloat = 0.82
        var jpegData = image.jpegData(compressionQuality: quality)
        while let d = jpegData, d.count > 1_800_000, quality > 0.35 {
            quality -= 0.1
            jpegData = image.jpegData(compressionQuality: quality)
        }
        guard let jpegData else {
            uploadError = "Не удалось обработать изображение"
            return
        }

        let base64 = jpegData.base64EncodedString()
        guard let url = URL(string: PlinkConfig.apiURLString + "/users/me/avatar") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        if let token = AuthTokenStore.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            uploadError = "Не авторизован. Войдите заново."
            store?.applyAvatar(image: image, serverURL: nil)
            return
        }

        let body: [String: Any] = ["avatar": "data:image/jpeg;base64,\(base64)"]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                var serverURL: URL?
                if let respBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let avatarURLString = respBody["avatarURL"] as? String {
                    serverURL = URL(string: avatarURLString)
                }
                if serverURL == nil, let uid = AuthService.shared.currentUserValue?.id {
                    serverURL = URL(string: PlinkConfig.apiURLString + "/users/\(uid)/avatar")
                }
                await MainActor.run {
                    store?.applyAvatar(image: image, serverURL: serverURL)
                    if let busted = store?.avatarURL {
                        onAvatarChanged?(busted)
                    }
                    uploadOK = true
                    pendingImage = nil
                }
            } else if code == 401 {
                uploadError = "Сессия истекла. Войдите заново."
                store?.applyAvatar(image: image, serverURL: nil)
            } else if code == 413 {
                uploadError = "Фото слишком большое. Выберите другое."
            } else {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                uploadError = msg ?? "Ошибка сервера (\(code))"
                store?.applyAvatar(image: image, serverURL: nil)
            }
        } catch {
            uploadError = "Сеть: \(error.localizedDescription)"
            store?.applyAvatar(image: image, serverURL: nil)
        }
    }
}
