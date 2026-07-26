//
//  PlinkSettingsComponents.swift
//  Plink
//
//  Shared settings UI components used by RoomSetupView, NotificationsView,
//  and other settings screens. Uses Cinema2026 design tokens.
//

import SwiftUI

// MARK: - PlinkSectionHeader

/// Section title with accent color, used above settings cards.
struct PlinkSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Cinema2026.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }
}

// MARK: - PlinkSettingsCard

/// Card container for grouping settings rows. Uses Cinema2026.surface
/// background with subtle divider between rows.
struct PlinkSettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(Cinema2026.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Cinema2026.divider.opacity(0.5), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - PlinkToggleRow

/// Toggle row with icon + title + subtitle + toggle switch.
/// Supports `enabled: false` state (dimmed, non-interactive).
struct PlinkToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let iconColor: Color
    @Binding var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(enabled ? Cinema2026.text : Cinema2026.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Cinema2026.secondary)
                }
            }

            Spacer()

            // Toggle
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Cinema2026.accent)
                .disabled(!enabled)
                .opacity(enabled ? 1.0 : 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
