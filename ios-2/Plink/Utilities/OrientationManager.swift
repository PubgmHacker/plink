import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Orientation Manager
/// Управление ориентацией устройства.
/// Позволяет принудительно повернуть экран в ландшафт/портрет.
#if canImport(UIKit)
final class OrientationManager {
    static let shared = OrientationManager()
    private init() {}

    /// Принудительно повернуть в ландшафт.
    func forceLandscape() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        // macOS Catalyst / симулятор: через requestGeometryUpdate
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            // 🔧 iOS 16+: заменённый API вместо устаревшего attemptRotationToDeviceOrientation().
            // Просит UIKit пересчитать поддерживаемые ориентации для всех VC в сцене.
            for vc in scene.windows.compactMap({ $0.rootViewController }) {
                vc.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            // Fallback: старый API (для старых iOS) — на iOS 16+ выдаёт
            // "BUG IN CLIENT OF UIKIT: Setting UIDevice.orientation is not supported"
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    /// Принудительно повернуть в портрет.
    func forcePortrait() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            // 🔧 iOS 16+: заменённый API вместо устаревшего attemptRotationToDeviceOrientation().
            for vc in scene.windows.compactMap({ $0.rootViewController }) {
                vc.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    /// Текущая ориентация портретная?
    /// 🔧 FIX M9: Added explicit parentheses — `??` has lower precedence than `&&`,
    /// so the old expression parsed as `interfaceOrientation.isPortrait ?? (true && (...))`
    /// which returned true for landscape orientations when UIDevice was .unknown.
    var isPortrait: Bool {
        if UIDevice.current.orientation.isPortrait {
            return true
        }
        // Если UIDevice.unknown (лежит на столе) — проверяем window scene
        if UIDevice.current.orientation == .unknown ||
           UIDevice.current.orientation == .faceUp ||
           UIDevice.current.orientation == .faceDown {
            let windowIsPortrait = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .interfaceOrientation.isPortrait ?? true
            return windowIsPortrait
        }
        return false
    }

    // MARK: - Orientation Lock (fix v2)
    //
    // 🔧 FIX v2 (July 2026): AppDelegate-level orientation lock for RoomView.
    // See PlinkAppDelegate in RaveCloneApp.swift for the full rationale.
    //
    // Why both `lockOrientation(_:)` AND `forceLandscape()`/`forcePortrait()`:
    //   - `forceLandscape/Portrait` ROTATES the device NOW (imperative).
    //   - `lockOrientation(_:)` SETS the set of allowed orientations for future
    //     rotation events (declarative). UIKit consults
    //     `application(_:supportedInterfaceOrientationsFor:)` on every rotation
    //     request — if the requested orientation isn't in the lock, the rotation
    //     is suppressed.
    //
    // RoomView uses BOTH: on enter, lock + force the desired orientation; on
    // exit, unlock (.all) so the rest of the app can rotate freely.
    //
    // IMPORTANT: also call `setNeedsUpdateOfSupportedInterfaceOrientations()` on
    // all root VCs so UIKit re-queries the lock immediately rather than waiting
    // for the next rotation event.

    /// Lock the device to a specific set of orientations.
    /// Pass `.all` to release the lock (allow any orientation).
    func lockOrientation(_ mask: UIInterfaceOrientationMask) {
        PlinkAppDelegate.orientationLock = mask
        // Force UIKit to re-evaluate the supported orientations NOW.
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        for vc in scene.windows.compactMap({ $0.rootViewController }) {
            vc.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    private func callStack() -> String {
        let symbols = Thread.callStackSymbols
        // Skip [0]=callStack [1]=lockOrientation [2]=caller
        return symbols.dropFirst(2).prefix(8).joined(separator: " ← ")
    }

    /// Convenience: lock to portrait only.
    func lockToPortrait() {
        lockOrientation(.portrait)
        forcePortrait()
    }

    /// Convenience: lock to landscape only.
    func lockToLandscape() {
        lockOrientation(.landscape)
        forceLandscape()
    }

    /// Convenience: release all orientation locks (allow any orientation).
    func unlockOrientation() {
        lockOrientation(.all)
    }
}
#else
final class OrientationManager {
    static let shared = OrientationManager()
    private init() {}
    func forceLandscape() {}
    func forcePortrait() {}
    var isPortrait: Bool { true }
    func unlockOrientation() {}
    func lockToPortrait() {}
    func lockToLandscape() {}
}
#endif
