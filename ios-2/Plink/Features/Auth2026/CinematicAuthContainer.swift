// Plink/Features/Auth2026/CinematicAuthContainer.swift — §8 Final Unified
//
// Adaptive auth container: poster mosaic on top, form below.
// iPhone: vertical scroll. iPad/Mac: side-by-side.

import SwiftUI

struct CinematicAuthContainer<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 760 {
                // iPad/Mac: side-by-side
                HStack(spacing: 0) {
                    artwork
                        .frame(width: proxy.size.width * 0.55)
                    form
                }
            } else {
                // iPhone: vertical scroll
                ScrollView {
                    VStack(spacing: 0) {
                        artwork
                            .frame(height: min(410, proxy.size.height * 0.47))
                        form
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(Cinema2026.background.ignoresSafeArea())
        .foregroundStyle(Cinema2026.text)
    }

    private var artwork: some View {
        ZStack(alignment: .top) {
            AnimatedPosterMosaic()
            Text(title)
                .font(.headline.weight(.semibold))
                .padding(.top, 18)
        }
    }

    private var form: some View {
        content
            .frame(maxWidth: 430)
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Auth button styles

struct AuthPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Cinema2026.background)
            .frame(maxWidth: .infinity)
            .frame(height: CompactPhoneMetrics.primaryButtonHeight)
            .background(Cinema2026.text, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct AuthProviderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Cinema2026.text)
            .frame(maxWidth: .infinity)
            .frame(height: CompactPhoneMetrics.primaryButtonHeight)
            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Cinema2026.divider, lineWidth: 0.5)
            )
    }
}

// MARK: - Auth components

struct CompactAuthField: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType?
    var secure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Cinema2026.secondary)
            if secure {
                SecureField("", text: $text, prompt: Text(title).foregroundStyle(Cinema2026.secondary))
                    .textContentType(contentType)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))
            } else {
                TextField("", text: $text, prompt: Text(title).foregroundStyle(Cinema2026.secondary))
                    .textContentType(contentType)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))
            }
        }
    }
}

struct AuthDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Cinema2026.divider).frame(height: 0.5)
            Text(text)
                .font(.caption)
                .foregroundStyle(Cinema2026.secondary)
            Rectangle().fill(Cinema2026.divider).frame(height: 0.5)
        }
    }
}

struct LegalConsentFooter: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Продолжая, вы принимаете")
                .font(.system(size: 11))
                .foregroundStyle(Cinema2026.secondary)
            HStack(spacing: 4) {
                Link("Условия", destination: URL(string: "https://plink.app/terms")!)
                Text("·")
                Link("Конфиденциальность", destination: URL(string: "https://plink.app/privacy")!)
            }
            .font(.system(size: 11))
            .foregroundStyle(Cinema2026.secondary)
        }
    }
}
