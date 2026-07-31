// Plink/V4/V4AIView.swift — AI companion tab with 3D state sphere

import SwiftUI
import PhotosUI
import UIKit
import Foundation

// Аудит 26.07.2026: V4MorphOrb использовался только удалённым макетом
// V4AIView — удалён вместе с ним.

// Аудит 26.07.2026: здесь был статический макет с захардкоженными данными
// (0 инстанцирований по всему проекту) — удалён, живой экран ниже.

struct V4AIViewLive: View {
    let theme: V4Theme
    @Bindable var store: V4AIStore
    @State private var input = ""
    @State private var showManualCreate = false
    @State private var confirmingAction: AIProposedAction?
    @State private var presentedRoom: Room?
    @State private var speakingPulseUntil: Date = .distantPast
    @State private var keyboard = KeyboardObserver()
    @StateObject private var speech = V4SpeechRecognizer()  // M34: реальный STT

    private var orbState: AIOrbState {
        let s = store.state.lowercased()
        if s.contains("ошиб") || s.contains("error") || s.contains("не удалось") { return .error }
        if store.state == "Думаю…" || s.contains("дума") { return .thinking }
        if store.state == "Слушаю…" || s.contains("слуша") { return .listening }
        if keyboard.isVisible && !input.trimmingCharacters(in: .whitespaces).isEmpty { return .listening }
        if Date() < speakingPulseUntil { return .speaking }
        return .idle
    }

    private var stateCaption: String {
        switch orbState {
        case .idle: return store.state.isEmpty ? "Готов помочь" : store.state
        case .listening: return "Слушаю…"
        case .thinking: return "Думаю…"
        case .speaking: return "Отвечаю…"
        case .error: return store.state
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                AICompanionModel(theme: theme, size: 44, glow: 20, state: orbState)
                    .frame(width: 48, height: 48)
                    .clipped()
                VStack(alignment:.leading,spacing:2) {
                    Text("Plink AI").font(.system(size:16,weight:.bold))
                    Text(stateCaption)
                        .font(.system(size:11.04, weight: .medium))
                        .foregroundStyle(headerStateColor)
                        .lineLimit(1)
                }
                Spacer()
                // M34: очистить историю чата
                if store.messages.count > 1 {
                    Button {
                        HapticManager.impact(.light)
                        withAnimation { store.clearHistory() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(V4.muted)
                            .frame(width: 44, height: 44)
                            .background(V4.raised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить историю чата")
                }
                Button {
                    showManualCreate = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(LocalizationManager.shared.string(.roomLabel))
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.buttonTextColor)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(theme.accentColor)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Создать комнату вручную")
            }
            .frame(height:61)
            .padding(.horizontal,17)
            .accessibilityIdentifier("screen.ai")

            // 3D AI sphere zone — collapses when keyboard is visible
            ZStack(alignment:.bottom) {
                // Soft radial stage under the orb (does not block living theme completely)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                headerStateColor.opacity(0.18),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 140
                        )
                    )
                    .frame(width: 280, height: 280)
                    .offset(y: -20)
                    .allowsHitTesting(false)

                AICompanionModel(theme: theme, size: 200, glow: 70, state: orbState)
                    .offset(y: -18)

                VStack(spacing: 4) {
                    Text(LocalizationManager.shared.string(.aiWhatToday))
                        .font(.system(size: 17, weight: .bold))
                    Text(stateCaption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(headerStateColor.opacity(0.95))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(headerStateColor.opacity(0.12), in: Capsule())
                }
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: keyboard.isVisible ? 0 : 290)
            .clipped()
            .animation(.easeInOut(duration: 0.3), value: keyboard.isVisible)
            .animation(.easeInOut(duration: 0.35), value: orbState)

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView(showsIndicators:false) {
                    VStack(alignment:.leading,spacing:8) {
                        ForEach(store.messages) { msg in
                            if msg.isBot {
                                VStack(alignment:.leading,spacing:3) {
                                    Text("PLINK AI").font(.system(size:13.28,weight:.bold))
                                    Text(msg.text).font(.system(size:13.28)).lineSpacing(5.31)

                                    // P0.4: show confirm button if proposedAction exists
                                    if let action = msg.proposedAction {
                                        AIActionButton(action: action, store: store, presentedRoom: $presentedRoom, confirmingAction: $confirmingAction)
                                    }
                                }
                                .padding(.vertical,11).padding(.horizontal,13)
                                .background(V4.botBG)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .id(msg.id)
                            } else {
                                HStack {
                                    Spacer()
                                    Text(msg.text)
                                        .font(.system(size:13.28))
                                        .padding(.vertical,11).padding(.horizontal,13)
                                        .background(theme.accentColor.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                        .id(msg.id)
                                }
                            }
                        }
                        // Chips — M34: динамические подсказки после ответа ИИ
                        HStack(spacing:7) {
                            if store.lastSuggestions.isEmpty {
                                chip("Очередь","Собери очередь на вечер")
                                chip("У друзей","Что смотрят друзья?")
                                chip("Через AI","Создай комнату с Inception")
                            } else {
                                ForEach(store.lastSuggestions.prefix(3), id: \.self) { s in
                                    chip(String(s.prefix(18)), s)
                                }
                            }
                        }
                    }
                    .padding(.horizontal,16)
                    .padding(.top,8)
                    .padding(.bottom,100)
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let last = store.messages.last, last.isBot {
                        speakingPulseUntil = Date().addingTimeInterval(2.5)
                    }
                    if let lastID = store.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }

            // Composer — full width, no side gaps
            HStack(spacing:6) {
                Button {
                    HapticManager.impact(.light)
                    // M34: реальный STT — SFSpeechRecognizer (ru-RU)
                    if speech.isRecording {
                        speech.stop()
                        store.setStatus("Готов помочь")
                        let text = input.trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty {
                            input = ""
                            Task { await store.send(text) }
                        }
                    } else {
                        speech.start()
                        store.setStatus("Слушаю…")
                    }
                } label: {
                    Image(systemName: orbState == .listening ? "mic.fill" : "mic")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(orbState == .listening ? theme.buttonTextColor : V4.ink)
                }
                .frame(width:44,height:44)
                .background(orbState == .listening ? theme.accentColor : V4.raised)
                .clipShape(RoundedRectangle(cornerRadius:14))
                .accessibilityLabel("Голосовой ввод")

                TextField("Спроси про фильмы и комнаты", text:$input)
                    .foregroundStyle(V4.ink)
                    .font(.system(size: 14))

                Button {
                    let text = input
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    input = ""
                    HapticManager.impact(.light)
                    Task { await store.send(text) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.buttonTextColor)
                }
                .frame(width:44,height:44)
                .background(theme.accentColor)
                .clipShape(RoundedRectangle(cornerRadius:14))
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Отправить сообщение")
            }
            .padding(8)
            .frame(minHeight:62)
            .background(V4.composerBG)
            .clipShape(RoundedRectangle(cornerRadius:22))
            .overlay(RoundedRectangle(cornerRadius:22).stroke(V4.line))
            .padding(.horizontal,13)
            .padding(.bottom,90) // above tab bar
        }
        .foregroundStyle(V4.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity) // full screen
        .onChange(of: speech.transcript) { _, t in
            // M34: partial results прямо в поле ввода
            if speech.isRecording && !t.isEmpty { input = t }
        }
        .sheet(isPresented: $showManualCreate) {
            RoomCreationView(
                onRoomCreated: { _ in showManualCreate = false }
            )
            .environmentObject(APIClient.shared)
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $presentedRoom) { room in
            WatchRoomContainer(room: room)
        }
    }

    private var headerStateColor: Color {
        switch orbState {
        case .idle: return theme.accentColor
        case .listening: return Color(red: 0.45, green: 0.55, blue: 1.0)
        case .thinking: return Color(red: 0.85, green: 0.4, blue: 1.0)
        case .speaking: return Color(red: 0.25, green: 0.9, blue: 0.7)
        case .error: return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }

    private func chip(_ label:String,_ prompt:String)->some View {
        Button {
            input = prompt
            HapticManager.impact(.light)
            Task { await store.send(prompt) }
        } label: {
            Text(label)
                .font(.system(size:11.52, weight: .semibold))
                .foregroundStyle(V4.ink)
                .padding(.horizontal,12)
                .frame(minHeight:44)
                .background(V4.surface.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).stroke(V4.line))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AIActionButton (P0.4)

struct AIActionButton: View {
    let action: AIProposedAction
    let store: V4AIStore
    @Binding var presentedRoom: Room?
    @Binding var confirmingAction: AIProposedAction?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preview
            if let preview = action.payloadPreview {
                VStack(alignment: .leading, spacing: 4) {
                    if let title = preview.title {
                        Text("📝 \(title)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(V4.ink)
                    }
                    if let privacy = preview.privacy {
                        Text("🔒 \(privacy)")
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    }
                    if let count = preview.queueCount {
                        Text("📋 \(count) в очереди")
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    }
                }
                .padding(10)
                .background(V4.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 8) {
                Button {
                    Task { await confirm() }
                } label: {
                    HStack(spacing: 4) {
                        if loading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(LocalizationManager.shared.string(.rcCreate))
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(loading)

                Button {
                    confirmingAction = nil
                } label: {
                    Text(LocalizationManager.shared.string(.aiCancel))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(V4.surface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if let err = error {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(V4.danger)
            }
        }
        .padding(.top, 6)
    }

    private func confirm() async {
        loading = true
        error = nil
        if let room = await store.confirmAction(action) {
            HapticManager.roomJoined()
            presentedRoom = room
        } else {
            HapticManager.errorOccurred()
            error = "Не удалось создать комнату"
        }
        loading = false
    }
}


enum AIOrbState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error
}

// AICompanionModel is defined in AI3DCompanionSphere.swift (real SceneKit 3D orb)

