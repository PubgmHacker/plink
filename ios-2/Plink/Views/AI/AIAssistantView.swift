
// Plink/Views/AI/AIAssistantView.swift -- AI Assistant (real chat + action cards)
import SwiftUI

// MARK: - Message model

struct AIChatMessage: Identifiable {
    let id = UUID()
    let role: AIChatRole
    let text: String
    let timestamp = Date()
}
enum AIChatRole { case user, assistant, system }

// MARK: - ViewModel

@MainActor
final class AIAssistantViewModel: ObservableObject {
    @Published var messages: [AIChatMessage] = []
    @Published var input: String = ""
    @Published var isLoading = false
    @Published var orbState: AIAssistantOrbState = .idle
    @Published var pendingAction: AIProposedAction? = nil
    @Published var errorText: String? = nil

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        input = ""
        messages.append(AIChatMessage(role: .user, text: text))
        Task { await reply(to: text) }
    }

    private func reply(to text: String) async {
        isLoading = true; orbState = .thinking; errorText = nil
        defer { isLoading = false }
        do {
            let history = messages.suffix(12).map {
                AIService.ChatMessage(role: $0.role == .user ? "user" : "assistant", content: $0.text)
            }
            let msgs = [AIService.ChatMessage(role: "system", content: AIService.strictSystemPrompt)] + history
            let raw = try await AIService.shared.chat(messages: msgs, temperature: 0.8)
            let reply = AIService.sanitizeResponse(raw)
            orbState = .speaking
            messages.append(AIChatMessage(role: .assistant, text: reply))
            // Fire parallel action-detection call with room_host mode
            await detectAction(for: text)
        } catch {
            let m: String
            if let e = error as? APIError {
                switch e {
                case .unauthorized: m = "Сессия истекла"
                case .serverError(429, _): m = "Перегрузка, подожди"
                case .serverError(503, _): m = "AI временно недоступен"
                default: m = "Ошибка соединения"
                }
            } else { m = "Ошибка" }
            errorText = m
            messages.append(AIChatMessage(role: .system, text: "⚠ " + m))
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        orbState = .idle
    }

    private func detectAction(for userText: String) async {
        guard let auth = KeychainHelper.read(for: "rave_auth_token"),
              let url = URL(string: PlinkConfig.apiURLString + "/ai/chat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + auth, forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "messages": [["role": "user", "content": userText]],
            "mode": "room_host"
        ])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
        struct R: Decodable {
            struct PA: Decodable {
                let type: String?; let confirmationId: String?; let expiresAt: String?
                struct Pv: Decodable { let title: String?; let privacy: String?; let queueCount: Int? }
                let payloadPreview: Pv?
            }
            let proposedAction: PA?
        }
        guard let d = try? JSONDecoder().decode(R.self, from: data),
              let pa = d.proposedAction, let t = pa.type, let cid = pa.confirmationId else { return }
        let pv = pa.payloadPreview.map { AIPayloadPreview(title: $0.title, privacy: $0.privacy, queueCount: $0.queueCount) }
        pendingAction = AIProposedAction(type: t, confirmationId: cid, expiresAt: pa.expiresAt, payloadPreview: pv)
    }

    func confirmAction() {
        guard let a = pendingAction else { return }
        pendingAction = nil
        Task {
            await AIActionExecutor(roomModel: nil).execute(a)
            messages.append(AIChatMessage(role: .system, text: "✅ " + (a.payloadPreview?.title ?? a.type)))
        }
    }
    func dismissAction() { pendingAction = nil }
    func clear() { messages = []; pendingAction = nil; errorText = nil }
}

enum AIAssistantOrbState: Equatable {
    case idle, listening, thinking, speaking
    var metal: OrbState {
        switch self {
        case .idle: return .idle
        case .listening: return .listening
        case .thinking: return .thinking
        case .speaking: return .speaking
        }
    }
}

// MARK: - View

struct AIAssistantView: View {
    @StateObject private var vm = AIAssistantViewModel()
    @FocusState private var focused: Bool

    private let chips: [(String, String)] = [
        ("film", "Что посмотреть вечером?"),
        ("person.2", "Комедия для компании"),
        ("sparkles", "Топ фантастики 2024"),
        ("play.rectangle", "Создай комнату для просмотра"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            navBar
            if vm.messages.isEmpty { welcome } else { chat }
            if let a = vm.pendingAction {
                AIActionCard(action: a, onConfirm: vm.confirmAction, onDismiss: vm.dismissAction)
                    .padding(.horizontal, 12).padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            composer
        }
        .background(Color(red:0.035,green:0.04,blue:0.06).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(.spring(response:0.35,dampingFraction:0.85), value: vm.pendingAction != nil)
    }

    // NAV
    private var navBar: some View {
        HStack(spacing: 10) {
            AssistantOrbView(state: vm.orbState.metal)
                .frame(width: 38, height: 38).clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Plink AI").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(caption).font(.system(size: 11)).foregroundStyle(capColor)
            }
            Spacer()
            if !vm.messages.isEmpty {
                Button { vm.clear() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.45))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // WELCOME
    private var welcome: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 12)
                AssistantOrbView(state: vm.orbState.metal).frame(width: 130, height: 130)
                Text("Привет! Я Plink AI
Помогу выбрать фильм и создам комнату.")
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                VStack(spacing: 8) {
                    ForEach(chips, id: \.1) { icon, label in
                        Button { vm.input = label; vm.send() } label: {
                            Label(label, systemImage: icon)
                                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(red:0.10,green:0.12,blue:0.17), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.07)))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
                Spacer(minLength: 90)
            }
        }
    }

    // CHAT
    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.messages) { m in AIChatBubble(msg: m) }
                    if vm.isLoading { TypingDots().padding(.leading, 10) }
                    Color.clear.frame(height: 1).id("bot")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .onChange(of: vm.messages.count) { _, _ in withAnimation { proxy.scrollTo("bot", anchor: .bottom) } }
            .onChange(of: vm.isLoading) { _, _ in withAnimation { proxy.scrollTo("bot", anchor: .bottom) } }
        }
    }

    // COMPOSER
    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Спроси про фильмы и комнаты...", text: $vm.input, axis: .vertical)
                .font(.system(size: 15)).foregroundStyle(.white)
                .lineLimit(1...4).focused($focused)
                .submitLabel(.send).onSubmit { vm.send() }
            Button { focused = false; vm.send() } label: {
                Image(systemName: vm.isLoading ? "ellipsis" : "arrow.up")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(vm.isLoading ? Color.gray : Color(red:0.20,green:0.82,blue:0.92), in: Circle())
            }.buttonStyle(.plain)
             .disabled(vm.isLoading || vm.input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }
        .padding(11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.09)))
        .padding(.horizontal, 12).padding(.bottom, 10)
    }

    private var caption: String {
        switch vm.orbState {
        case .idle: return "Готов"
        case .listening: return "Слушаю..."
        case .thinking: return "Думаю..."
        case .speaking: return "Отвечаю..."
        }
    }
    private var capColor: Color {
        switch vm.orbState {
        case .idle: return Color(red:0.35,green:0.70,blue:1.0)
        case .listening: return Color(red:0.25,green:0.92,blue:1.0)
        case .thinking: return Color(red:1.0,green:0.30,blue:0.88)
        case .speaking: return Color(red:0.28,green:1.0,blue:0.72)
        }
    }
}

// MARK: - Bubble
struct AIChatBubble: View {
    let msg: AIChatMessage
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if msg.role == .user { Spacer(minLength: 48) }
            if msg.role != .user {
                Circle()
                    .fill(LinearGradient(colors: [Color(red:0.20,green:0.82,blue:0.92),Color(red:0.28,green:1.0,blue:0.72)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: msg.role == .system ? "info.circle" : "sparkles")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.black))
            }
            Text(msg.text).font(.system(size: 15)).foregroundStyle(msg.role == .system ? .white.opacity(0.55) : .white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(bgColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if msg.role != .user { Spacer(minLength: 48) }
        }
    }
    private var bgColor: Color {
        switch msg.role {
        case .user: return Color(red:0.20,green:0.82,blue:0.92).opacity(0.22)
        case .assistant: return Color(red:0.10,green:0.12,blue:0.18)
        case .system: return .white.opacity(0.04)
        }
    }
}

// MARK: - Typing dots
struct TypingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.38, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.white.opacity(phase == i ? 0.9 : 0.28))
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.4 : 1.0)
                    .animation(.easeInOut(duration: 0.28), value: phase)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(red:0.10,green:0.12,blue:0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
