// Plink/Services/PlinkPermissions.swift
// Central iOS permission prompts — photo library (avatar) + microphone (voice).
//
// Photos (iOS 14+ / 2024–2026):
// • System dialog appears only while status is `.notDetermined` — call
//   `requestAuthorization` on the user action (tap «из галереи»), not later.
// • `PhotosPicker` / PHPicker does NOT require full library access; even after
//   Deny, the system picker still works. Never force users into Settings for
//   simple avatar/cover picks.
// • Settings is only for features that need full/limited library re-grant.

import Foundation
import Photos
import AVFoundation
import UIKit

@MainActor
enum PlinkPermissions {

    private enum Keys {
        static let didPromptPhotos = "plink.perm.photos.prompted"
        static let didPromptMic = "plink.perm.mic.prompted"
        static let postAuthPhotosNudge = "plink.perm.photos.postAuthNudge"
    }

    // MARK: - Photos (avatar / gallery)

    /// Outcome for opening the system photo UI (avatar / cover).
    enum PhotoPickerAccess: Sendable {
        /// Full or limited library grant.
        case authorized
        /// Full library denied/restricted, but system PHPicker still works.
        case systemPickerOnly
        /// Device policy blocks any photo access (rare).
        case blocked
    }

    /// Current authorization for reading the photo library.
    static var photosStatus: PHAuthorizationStatus {
        if #available(iOS 14, *) {
            return PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        return PHPhotoLibrary.authorizationStatus()
    }

    static var isPhotosAuthorized: Bool {
        let s = photosStatus
        if #available(iOS 14, *) {
            return s == .authorized || s == .limited
        }
        return s == .authorized
    }

    /// Whether the user can still open the system Photos picker without
    /// full-library permission (always true on iOS 14+ for PHPicker).
    static var canPresentSystemPhotoPicker: Bool {
        if #available(iOS 14, *) {
            // PHPicker is privacy-preserving and works even when status is denied.
            return photosStatus != .restricted
        }
        return isPhotosAuthorized || photosStatus == .notDetermined
    }

    /// Call on the user tap that needs gallery (avatar / cover).
    /// 1) If `.notDetermined` → shows the **system iOS permission alert** immediately.
    /// 2) Always allows presenting `PhotosPicker` unless the device is restricted.
    /// Returns whether the UI should present the picker (almost always true).
    @discardableResult
    static func requestPhotosIfNeeded() async -> Bool {
        let outcome = await preparePhotoPicker()
        return outcome != .blocked
    }

    /// Prefer this over a bare Bool — distinguishes full grant vs picker-only.
    static func preparePhotoPicker() async -> PhotoPickerAccess {
        let current = photosStatus

        switch current {
        case .authorized:
            return .authorized
        case .limited:
            return .authorized
        case .restricted:
            return .blocked
        case .denied:
            // System PHPicker still works without re-granting in Settings.
            return canPresentSystemPhotoPicker ? .systemPickerOnly : .blocked
        case .notDetermined:
            // ── This is the only moment iOS will show the system sheet ──
            UserDefaults.standard.set(true, forKey: Keys.didPromptPhotos)
            let status: PHAuthorizationStatus
            if #available(iOS 14, *) {
                // `.readWrite` triggers the standard «Allow Full Access /
                // Limit Access / Don't Allow» dialog (iOS 14–18+).
                status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            } else {
                status = await withCheckedContinuation { cont in
                    PHPhotoLibrary.requestAuthorization { cont.resume(returning: $0) }
                }
            }
            switch status {
            case .authorized, .limited:
                return .authorized
            case .restricted:
                return .blocked
            default:
                // User tapped Don't Allow — still open PHPicker for one-shot pick.
                return .systemPickerOnly
            }
        @unknown default:
            return .systemPickerOnly
        }
    }

    /// After first successful login — remember we may soft-explain photos later.
    /// Does **not** auto-fire the system dialog (App Store HIG: only on user action).
    static func markPostAuthSession() {
        UserDefaults.standard.set(true, forKey: Keys.postAuthPhotosNudge)
    }

    static var shouldExplainPhotos: Bool {
        UserDefaults.standard.bool(forKey: Keys.postAuthPhotosNudge)
            && !isPhotosAuthorized
            && photosStatus == .notDetermined
    }

    /// True only when full library was denied and you truly need Settings
    /// (not for ordinary PhotosPicker avatar flow).
    static var needsPhotosSettings: Bool {
        photosStatus == .denied
    }

    // MARK: - Microphone (voice notes / room voice)

    static var isMicAuthorized: Bool {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return AVAudioSession.sharedInstance().recordPermission == .granted // deprecated fallback for iOS < 17
    }

    /// Request mic once — first voice note or room voice toggle. Shows system dialog.
    @discardableResult
    static func requestMicrophoneIfNeeded() async -> Bool {
        if isMicAuthorized { return true }

        UserDefaults.standard.set(true, forKey: Keys.didPromptMic)

        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// Open Settings when user previously denied and a feature truly requires re-grant.
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
