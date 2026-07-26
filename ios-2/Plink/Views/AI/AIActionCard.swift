// Plink/Views/AI/AIActionCard.swift
//
// AI Companion Pro — Confirm Actions UI Component
// Uses AIProposedAction from V4/PlinkV4BackendBridge.swift (single source of truth).

import SwiftUI

// MARK: - AI Action Card View (uses V4 AIProposedAction)

struct AIActionCard: View {
    let action: AIProposedAction
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            // AI orb icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: actionIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0E1113))
            }
            .accessibilityHidden(true)

            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text("AI предлагает")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2DE2E6))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(action.payloadPreview?.title ?? action.type)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Cinema2026.text)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            // Buttons
            HStack(spacing: 6) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .accessibilityLabel("Отклонить")
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0E1113))
                        .frame(width: 30, height: 30)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                }
                .accessibilityLabel("Подтвердить")
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(hex: 0x2DE2E6).opacity(0.3), lineWidth: 1)
                )
        )
        .transition(
            reduceMotion
                ? .opacity
                : .move(edge: .bottom).combined(with: .opacity)
        )
    }

    // MARK: - Action icon (based on V4 string type)

    private var actionIcon: String {
        switch action.type {
        case "seek", "create_room": return "forward.fill"
        case "pause": return "pause.fill"
        case "play": return "play.fill"
        case "build_queue": return "list.bullet.rectangle"
        default: return "sparkles"
        }
    }
}

// MARK: - AI Action Executor

/// Executes confirmed AI actions on the room model.
@MainActor
final class AIActionExecutor {
    weak var roomModel: WatchRoomModel?

    init(roomModel: WatchRoomModel?) {
        self.roomModel = roomModel
    }

    func execute(_ action: AIProposedAction) async {
        guard let roomModel else { return }

        switch action.type {
        case "seek":
            await roomModel.sendSeekCommand(to: 0)
            AnalyticsService.shared.trackAIActionExecuted(type: "seek", timestamp: 0)

        case "pause":
            roomModel.sendPauseCommand()
            AnalyticsService.shared.trackAIActionExecuted(type: "pause", timestamp: nil)

        case "play":
            await roomModel.sendPlayCommand()
            AnalyticsService.shared.trackAIActionExecuted(type: "play", timestamp: nil)

        default:
            break
        }

        // Confirm with backend if confirmationId exists
        if !action.confirmationId.isEmpty {
            await confirmWithBackend(confirmationId: action.confirmationId)
        }
    }

    private func confirmWithBackend(confirmationId: String) async {
        guard let url = URL(string: PlinkConfig.apiURLString + "/ai/confirm-action") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.read(for: "rave_auth_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["confirmationId": confirmationId])
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: - Analytics Extension

extension AnalyticsService {
    func trackAIActionExecuted(type: String, timestamp: TimeInterval?) {
        var params: [String: Any] = ["action_type": type]
        if let timestamp {
            params["timestamp"] = timestamp
        }
        track("ai_action_executed", parameters: params)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AI Action Card") {
    AIActionCard(
        action: AIProposedAction(
            type: "seek",
            confirmationId: "test-id",
            expiresAt: nil,
            payloadPreview: AIPayloadPreview(title: "Перемотать на 20:34?", privacy: nil, queueCount: nil)
        ),
        onConfirm: {},
        onDismiss: {}
    )
    .padding()
    .background(Cinema2026.background)
    .preferredColorScheme(.dark)
}
#endif
