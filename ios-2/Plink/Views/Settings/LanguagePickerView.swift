import SwiftUI

// MARK: - Language Picker View (Premium)
/// 🔧 REDESIGNED: Full-screen language switcher with instant runtime switching.
/// Changes the ENTIRE app language immediately — all localized strings update.
struct LanguagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        ZStack {
            Cinema2026.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // ── Section Header ──
                    PlinkSectionHeader(text: "Выберите язык приложения")
                        .padding(.horizontal, 16)

                    // ── Language Cards ──
                    PlinkSettingsCard {
                        ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { index, lang in
                            languageRow(lang)
                            if index < AppLanguage.allCases.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // ── Info ──
                    Text("Язык изменится мгновенно. Все тексты в приложении переключатся на выбранный язык.")
                        .font(.system(size: 11))
                        .foregroundColor(Cinema2026.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    Spacer(minLength: 32)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Язык")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Language Row

    @ViewBuilder
    private func languageRow(_ lang: AppLanguage) -> some View {
        Button {
            HapticManager.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                loc.currentLanguage = lang
            }
            // Brief delay so the user sees the checkmark animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                dismiss()
            }
        } label: {
            HStack(spacing: 14) {
                // Flag emoji in rounded square
                Text(lang.flag)
                    .font(.system(size: 24))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.nativeName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Cinema2026.text)
                    Text(lang.englishName)
                        .font(.system(size: 12))
                        .foregroundColor(Cinema2026.secondary)
                }

                Spacer()

                // Selection checkmark
                Image(systemName: loc.currentLanguage == lang ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(loc.currentLanguage == lang ? Cinema2026.accent : Cinema2026.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
