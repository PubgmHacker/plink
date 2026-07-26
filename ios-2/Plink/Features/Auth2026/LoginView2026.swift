//  Plink/Features/Auth2026/LoginView2026.swift
//  NEW: 1:1 with iOS reference design (Plink gradient logo, poster arc,
//  silhouette, glass card, Регистрация/Вход buttons, 4 floating orbs)

import SwiftUI
import AuthenticationServices

struct LoginView2026: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var isSignUp = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    var sessionMessage: String? = nil
    let onAuthenticated: () -> Void
    let onRegister: () -> Void

    var body: some View {
        ZStack {
            // ═══ Background: obsidian + 4 floating orbs ═══
            obsidianBackground

            // ═══ Content ═══
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    // ── Plink gradient logo ──
                    Text("Plink")
                        .font(.system(size: 54, weight: .heavy, design: .default))
                        .tracking(-1.8)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(hex: 0x2DE2E6).opacity(0.3), radius: 20)
                        .padding(.bottom, 10)

                    // ── Slogans ──
                    Text("Смотрим вместе")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                        .padding(.bottom, 4)

                    Text("Watch together. Anywhere. Together.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Cinema2026.secondary)
                        .padding(.bottom, 40)

                    // ── Poster arc (5 cinematic posters) ──
                    posterArc
                        .padding(.bottom, 36)

                    // ── Silhouette on platform ──
                    silhouetteOnPlatform
                        .padding(.bottom, 32)

                    // ── Auth card (glassmorphism) ──
                    authCard

                    if let sessionMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(hex: 0xD7A750))
                            Text(sessionMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Cinema2026.text)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xD7A750).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xD7A750).opacity(0.35), lineWidth: 1))
                        .padding(.top, 14)
                    }

                    // ── Toggle hint ──
                    HStack(spacing: 4) {
                        Text(isSignUp ? "Уже есть аккаунт?" : "Нет аккаунта?")
                            .foregroundStyle(Cinema2026.secondary)
                        Button(isSignUp ? "Войти" : "Создать") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isSignUp.toggle()
                                errorMessage = nil
                            }
                        }
                        .foregroundStyle(Color(hex: 0x2DE2E6))
                        .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private var obsidianBackground: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()

            // Radial gradient
            RadialGradient(
                colors: [Color(hex: 0x1A1F2E).opacity(0.5), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()

            // 4 orbs
            Circle().fill(Color(hex: 0x2DE2E6)).frame(width: 300, height: 300)
                .blur(radius: 70).opacity(0.32)
                .offset(x: -140, y: -200)

            Circle().fill(Color(red: 0.0, green: 0.6, blue: 1.0)).frame(width: 300, height: 300)
                .blur(radius: 70).opacity(0.32)
                .offset(x: 160, y: -180)

            Circle().fill(Color(hex: 0x26D9A4)).frame(width: 300, height: 300)
                .blur(radius: 70).opacity(0.32)
                .offset(x: -160, y: 100)

            Circle().fill(Color(red: 0.0, green: 1.0, blue: 0.4)).frame(width: 300, height: 300)
                .blur(radius: 70).opacity(0.25)
                .offset(x: 140, y: 120)
        }
    }

    // MARK: - Poster Arc

    private var posterArc: some View {
        HStack(spacing: 8) {
            ForEach(Array(posters.enumerated()), id: \.offset) { index, poster in
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [poster.1, poster.1.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 76, height: 114)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(hex: 0x2DE2E6).opacity(0.55), lineWidth: 1.5)
                            .shadow(color: Color(hex: 0x2DE2E6).opacity(0.25), radius: 4)
                    )
                    .overlay(alignment: .bottom) {
                        Text(poster.0)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.bottom, 6)
                    }
                    .rotationEffect(.degrees(Double(index - 2) * 6))
                    .offset(y: CGFloat(abs(index - 2)) * 8)
            }
        }
    }

    private let posters: [(String, Color)] = [
        ("Pari", Color(red: 0.55, green: 0.23, blue: 0.23)),
        ("October", Color(red: 1.0, green: 0.55, blue: 0.26)),
        ("Super 30", Color(red: 0.29, green: 0.29, blue: 0.29)),
        ("Hindi Medium", Color(red: 0.29, green: 0.44, blue: 0.65)),
        ("Ra.One", Color(red: 0.42, green: 0.27, blue: 0.76)),
    ]

    // MARK: - Silhouette

    private var silhouetteOnPlatform: some View {
        ZStack {
            Image(systemName: "person.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color(hex: 0x0A0E1A))
                .shadow(color: Color(hex: 0x2DE2E6).opacity(0.4), radius: 16)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x2DE2E6).opacity(0.4), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 22)
                .offset(y: 36)
        }
        .frame(height: 100)
    }

    // MARK: - Auth Card

    private var authCard: some View {
        VStack(spacing: 12) {
            if isSignUp {
                authField(icon: "person.fill", placeholder: "Имя пользователя", text: $username)
            }
            authField(icon: "envelope.fill", placeholder: "Email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
            authField(icon: "lock.fill", placeholder: "Пароль", text: $password, isSecure: true)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0xD14B45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await authenticate() }
                } label: {
                    Text(isSignUp ? "Регистрация" : "Вход")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0E1113))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: 0x26D9A4), Color(red: 0.0, green: 1.0, blue: 0.64)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: 0x26D9A4).opacity(0.4), radius: 12)
                }
                .disabled(isLoading)

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isSignUp.toggle()
                        errorMessage = nil
                    }
                } label: {
                    Text(isSignUp ? "Вход" : "Регистрация")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: 0x2DE2E6).opacity(0.08))
                        .overlay(Capsule().stroke(Color(hex: 0x2DE2E6).opacity(0.4), lineWidth: 1))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func authField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color(hex: 0x2DE2E6))
                .font(.system(size: 14))
            if isSecure {
                SecureField(placeholder, text: text)
                    .foregroundStyle(Cinema2026.text)
                    .autocapitalization(.none)
            } else {
                TextField(placeholder, text: text)
                    .foregroundStyle(Cinema2026.text)
                    .autocapitalization(.none)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Auth Logic

    private func authenticate() async {
        isLoading = true
        errorMessage = nil

        do {
            let authService = AuthService.shared
            if isSignUp {
                let _ = try await authService.signUp(
                    email: email, password: password,
                    username: username.isEmpty ? email.split(separator: "@").first.map(String.init) ?? "User" : username
                )
            } else {
                let _ = try await authService.signIn(email: email, password: password)
            }
            onAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
