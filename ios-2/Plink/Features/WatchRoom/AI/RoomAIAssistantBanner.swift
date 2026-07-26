// Plink/Features/WatchRoom/AI/RoomAIAssistantBanner.swift — GPT-5.6 §13
import SwiftUI

struct RoomAIAssistantBanner: View {
    let state: V4AIState
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(Cinema2026.accent)
            Text(stateText).font(.system(size: 13, weight: .medium)).foregroundStyle(Cinema2026.text)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Cinema2026.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16).padding(.top, 8)
    }
    private var stateText: String {
        switch state { case .idle: "ИИ готов помочь"; case .listening: "Слушаю..."; case .thinking: "Анализирую..."; case .speaking: "Отвечаю..."; case .moderating: "Модерация активна"; case .offline: "ИИ недоступен"; case .failed: "Ошибка ИИ" }
    }
}
