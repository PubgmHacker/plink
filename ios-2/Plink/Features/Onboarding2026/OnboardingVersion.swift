// Plink/Features/Onboarding2026/OnboardingVersion.swift — §9 Final Unified
//
// Versioned onboarding: shown after first registration or when
// completed version is stale. Not on every launch.

import Foundation

enum OnboardingVersion {
    static let current = 3
}

protocol OnboardingStoring {
    var completedVersion: Int { get }
    func markCompleted(version: Int)
}

extension OnboardingStoring {
    var needsCurrentOnboarding: Bool {
        completedVersion < OnboardingVersion.current
    }
}

// MARK: - UserDefaults implementation

struct UserDefaultsOnboardingStore: OnboardingStoring {
    private let key = "plink_onboarding_version"

    var completedVersion: Int {
        UserDefaults.standard.integer(forKey: key)
    }

    func markCompleted(version: Int) {
        UserDefaults.standard.set(version, forKey: key)
    }
}
