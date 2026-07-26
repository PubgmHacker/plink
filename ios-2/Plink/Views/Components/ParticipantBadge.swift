import SwiftUI

// MARK: - ParticipantBadge
/// 🔧 Reusable glass badge showing participant count with person icon.
/// Small, visible, glass-styled. Place in any corner of any card.
///
/// Usage:
///   ParticipantBadge(count: room.participantCount)
///     .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
struct ParticipantBadge: View {
    let count: Int
    var alignment: BadgeAlignment = .trailing

    enum BadgeAlignment {
        case leading, trailing
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 9))
            Text(formattedCount)
                .font(.system(size: 11, weight: .heavy).monospacedDigit())
        }
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    /// Formats: 999 → "999", 1200 → "1.2k"
    private var formattedCount: String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
