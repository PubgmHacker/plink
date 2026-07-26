// Plink/Design/Cinematic/DynamicTypeSupport.swift
//
// Dynamic Type helpers for iOS — accessibility text scaling.
// Use these modifiers on all text elements to support VoiceOver users
// who need larger text.

import SwiftUI

// MARK: - Dynamic Type Support

extension View {
    /// Apply Dynamic Type support with min scale factor.
    /// Use on all text containers to prevent truncation at largest sizes.
    func plinkDynamicType() -> some View {
        self
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .minimumScaleFactor(0.75)
    }

    /// Apply for body text (smaller scaling range)
    func plinkBodyDynamicType() -> some View {
        self
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .minimumScaleFactor(0.8)
    }

    /// Apply for headlines (no scaling beyond xxxLarge)
    func plinkHeadlineDynamicType() -> some View {
        self
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .minimumScaleFactor(0.85)
    }
}

// MARK: - Adaptive Text Styles

/// Use these instead of hardcoded font sizes for Dynamic Type support.
enum PlinkFont {
    static func largeTitle() -> Font {
        .system(size: 34, weight: .heavy, design: .default)
    }

    static func title1() -> Font {
        .system(size: 28, weight: .bold, design: .default)
    }

    static func title2() -> Font {
        .system(size: 22, weight: .semibold, design: .default)
    }

    static func title3() -> Font {
        .system(size: 20, weight: .semibold, design: .default)
    }

    static func body() -> Font {
        .system(size: 17, weight: .regular, design: .default)
    }

    static func callout() -> Font {
        .system(size: 16, weight: .regular, design: .default)
    }

    static func subheadline() -> Font {
        .system(size: 15, weight: .regular, design: .default)
    }

    static func footnote() -> Font {
        .system(size: 13, weight: .regular, design: .default)
    }

    static func caption() -> Font {
        .system(size: 12, weight: .regular, design: .default)
    }
}

// MARK: - Layout-Safe Containers

/// Container that adapts spacing for larger Dynamic Type sizes.
struct AdaptiveVStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        VStack(spacing: size.isAccessibilitySize ? spacing * 1.2 : spacing, content: content)
    }
}

/// Container that adapts horizontal padding for larger Dynamic Type sizes.
struct AdaptiveHPadding<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        content()
            .padding(.horizontal, size.isAccessibilitySize ? padding * 0.7 : padding)
    }
}

// MARK: - Usage Examples (documentation)
//
// Instead of:
//   Text("Смотрим вместе").font(.system(size: 34, weight: .bold))
//
// Use:
//   Text("Смотрим вместе")
//     .font(PlinkFont.largeTitle())
//     .plinkDynamicType()
//
// For layout containers:
//   AdaptiveVStack(spacing: 16) {
//     Text("Title").font(PlinkFont.title1())
//     Text("Body").font(PlinkFont.body())
//   }
//
// For HStack with fixed labels (prevents overflow):
//   HStack {
//     Text("Email:").layoutPriority(1)
//     Text(user.email).truncationMode(.middle)
//   }
//   .plinkBodyDynamicType()
