// PlinkTests/DesignAuditShots.swift — offscreen renders of real screens for design review.
//
// This is NOT a regression test: nothing is compared pixel by pixel. The case builds
// live product screens with mock data and writes PNGs to disk, so the design can be
// judged by eye without driving the whole app by hand — room creation, service
// search, settings, the paywall, onboarding and the admin panel would otherwise each
// need a live backend and a paid account to reach.
//
// The mechanism and its limits are copied from MarketingShots.swift, which explains
// why the flag file lives in /tmp rather than ~/Desktop: under ~/Desktop, macOS TCC
// hangs the test on a system permission prompt that no one is there to answer.
//
// To run, from `ios/`:
//   xcodegen generate
//   echo /tmp/plink-audit-output > /tmp/plink-design-audit
//   xcodebuild test -scheme Plink \
//     -destination 'platform=iOS Simulator,name=iPhone 17' \
//     -only-testing:PlinkTests/DesignAuditShots
//   rm /tmp/plink-design-audit

import XCTest
import SwiftUI
import UIKit
@testable import Plink

@MainActor
final class DesignAuditShots: XCTestCase {

    private static let canvas = CGSize(width: 393, height: 852)
    private static let scale: CGFloat = 2
    private static let screenSafeArea = UIEdgeInsets(top: 44, left: 0, bottom: 20, right: 0)

    private static let flagFile = URL(fileURLWithPath: "/tmp/plink-design-audit")

    private static var flagContents: String? {
        guard let raw = try? String(contentsOf: flagFile, encoding: .utf8) else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["DESIGN_AUDIT"] == "1" { return true }
        return flagContents != nil
    }

    private func requireEnabled() throws {
        try XCTSkipUnless(
            Self.isEnabled,
            "Audit frames are captured on demand: set DESIGN_AUDIT=1 or create the file /tmp/plink-design-audit."
        )
    }

    private var outputDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["DESIGN_AUDIT_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let flag = Self.flagContents, !flag.isEmpty {
            return URL(fileURLWithPath: flag, isDirectory: true)
        }
        return URL(fileURLWithPath: "/tmp/plink-audit-output", isDirectory: true)
    }

    override func setUp() async throws {
        try await super.setUp()
        guard Self.isEnabled else { return }
        LocalizationManager.shared.currentLanguage = .russian
    }

    // MARK: - Screens

    func testRoomCreationShot() throws {
        try requireEnabled()
        try shoot(RoomCreationView(), named: "01-room-creation")
    }

    func testServiceBrowserShot() throws {
        try requireEnabled()
        try shoot(
            ServiceBrowserView(service: .youtube, onCreateRoom: { _, _ in }),
            named: "02-service-browser"
        )
    }

    func testPaywallShot() throws {
        try requireEnabled()
        try shoot(PlinkPlusPaywall(trigger: .theme), named: "03-paywall")
    }

    func testOnboardingShot() throws {
        try requireEnabled()
        try shoot(OnboardingFlow(onFinish: {}, onSkip: {}), named: "04-onboarding")
    }

    /// The second and third onboarding screens. A swipe cannot be reproduced in an
    /// offscreen render, so the scenes are captured directly.
    func testOnboardingScenesShot() throws {
        try requireEnabled()
        try shoot(OnboardingScene(page: .rooms), named: "04b-onboarding-rooms")
        try shoot(OnboardingScene(page: .chats), named: "04c-onboarding-chats")
    }

    /// Стена первого экрана с настоящими постерами. В симуляторе под VPN без
    /// DNS URLSession не резолвит api.ivi.ru, поэтому постеры для кадра
    /// скачивает хост в каталог из DESIGN_AUDIT_POSTERS (по умолчанию
    /// /tmp/plink-posters), а стена получает их как file://-ссылки через
    /// `OnboardingCatalogWall.posterSource`. Вёрстка и AsyncImage — те же, что
    /// в проде; отличается только транспорт.
    func testOnboardingWallPostersShot() throws {
        try requireEnabled()
        let env = ProcessInfo.processInfo.environment["DESIGN_AUDIT_POSTERS"] ?? ""
        let directory = URL(fileURLWithPath: env.isEmpty ? "/tmp/plink-posters" : env, isDirectory: true)
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try XCTSkipIf(files.isEmpty, "No posters in \(directory.path): download them on the host first.")

        let live = OnboardingCatalogWall.posterSource
        OnboardingCatalogWall.posterSource = { files }
        defer { OnboardingCatalogWall.posterSource = live }
        try shoot(OnboardingScene(page: .catalog), named: "04a-onboarding-wall-posters")
    }

    func testAppearanceShot() throws {
        try requireEnabled()
        try shoot(
            AppearanceHost(),
            named: "05-appearance"
        )
    }


    func testIdentityRingsShot() throws {
        try requireEnabled()
        try shoot(IdentityRingsBoard(), named: "06-identity-rings")
    }


    func testFriendsShot() throws {
        try requireEnabled()
        try shoot(
            V4FriendsViewLive(theme: .electric, store: nil, roomsStore: nil, isActive: true),
            named: "07-friends"
        )
    }

    /// The whole Home screen — the only way to see it without a live backend: the
    /// funnel UI test signs up first, and signup needs a database.
    func testHomeShot() throws {
        try requireEnabled()
        try shoot(
            V4HomeViewLive(
                theme: .electric,
                searchStore: V4SearchStore(),
                roomsStore: nil,
                openRoom: {}
            ),
            named: "08-home"
        )
    }

    // MARK: - Sign-in and first launch
    //
    // These frames exist so a redesign can be judged by eye: the funnel UI test does
    // reach the sign-in screens, but going past them needs a live database.

    /// Sign-in — the default mode of the combined screen.
    func testAuthSignInShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(onAuthenticated: {})
                .environmentObject(APIClient.shared),
            named: "10-auth-signin"
        )
    }

    /// Sign-up — the same screen with the toggle in the other position.
    func testAuthSignUpShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(initialMode: .signUp, onAuthenticated: {})
                .environmentObject(APIClient.shared),
            named: "11-auth-signup"
        )
    }

    /// Sign-in, filled — the primary button in its active state. The empty form is
    /// visible in 10-auth-signin, but a user spends most of their time looking at the
    /// filled one, so button contrast has to be judged on this frame.
    func testAuthFilledShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared),
            named: "12-auth-filled"
        )
    }

    /// The sign-in screen carrying an expired-session notice.
    func testAuthSessionNoticeShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                sessionMessage: "Сессия истекла. Войдите заново — это защищает ваш аккаунт.",
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared),
            named: "13-auth-session-notice"
        )
    }

    // MARK: Accessibility
    //
    // The sign-in background is six layers (a mosaic of frames, a light beam, grain),
    // and every one of them must switch off under Reduce Transparency / Reduce Motion.
    // This is exactly the kind of code that breaks silently: the ordinary frames look
    // fine, while somebody with the setting enabled gets either mush or an empty black
    // screen. Hence both states are captured separately.

    /// Reduce Transparency: the mosaic, beam and grain must go; the base and vignette
    /// must stay. The screen must be neither empty nor transparent.
    func testAuthReduceTransparencyShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared)
            .environment(
                \.plinkAccessibilityOverride,
                PlinkAccessibilityOverride(reduceTransparency: true)
            ),
            named: "14-auth-reduce-transparency"
        )
    }

    /// Reduce Motion: the mosaic becomes a static frame (no TimelineView) but stays
    /// where it is — the movement goes away, the picture does not.
    func testAuthReduceMotionShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared)
            .environment(
                \.plinkAccessibilityOverride,
                PlinkAccessibilityOverride(reduceMotion: true)
            ),
            named: "15-auth-reduce-motion"
        )
    }

    /// Large Dynamic Type: the fields and the button use minHeight rather than a
    /// fixed height — this checks that labels are not clipped.
    func testAuthLargeTypeShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared)
            .environment(\.dynamicTypeSize, .accessibility2),
            named: "16-auth-large-type"
        )
    }

    // MARK: - Infrastructure


    /// A showcase of the tiers: rings, badges and chips side by side, so the system
    /// can be seen whole rather than one screen at a time.
    ///
    /// The labels below stay Russian on purpose — they are rendered into the frame,
    /// and these screenshots are reviewed as the Russian-language product.
    private struct IdentityRingsBoard: View {
        private let levels: [(Bool, Bool, String)] = [
            (false, false, "Обычный"),
            (true, false, "Админ"),
            (false, true, "Plink+"),
            (true, true, "Админ + Plink+")
        ]

        var body: some View {
            VStack(spacing: 30) {
                Text("Кольца и бейджи")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(V4.ink)

                HStack(spacing: 20) {
                    ForEach(levels, id: \.2) { admin, plus, label in
                        VStack(spacing: 10) {
                            PlinkIdentityAvatar(
                                diameter: 64,
                                isAdmin: admin,
                                isPremium: plus,
                                isOnline: true
                            ) {
                                Circle().fill(V4.raised).overlay(
                                    Text("А").font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(V4.ink)
                                )
                            }
                            Text(label)
                                .font(.system(size: 10))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(V4.muted)
                                .frame(width: 76)
                        }
                    }
                }

                HStack(spacing: 10) {
                    PlinkIdentityChip(kind: .admin)
                    PlinkIdentityChip(kind: .plus)
                    PlinkIdentityChip(kind: .verified)
                    LiveBadge()
                }

                HStack(spacing: 18) {
                    ForEach([28.0, 40.0, 56.0], id: \.self) { d in
                        PlinkIdentityAvatar(
                            diameter: d,
                            isAdmin: false,
                            isPremium: true
                        ) {
                            Circle().fill(V4.raised)
                        }
                    }
                }

                Spacer()
            }
            .padding(.top, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(V4.canvas)
        }
    }

    /// `V4AppearanceView` needs bindings, so wrap it in a state holder.
    private struct AppearanceHost: View {
        @State private var theme: V4Theme = .electric
        @State private var presented = true
        var body: some View {
            V4AppearanceView(theme: $theme, presented: $presented)
        }
    }

    private func shoot<V: View>(_ view: V, named name: String) throws {
        let window: UIWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
            .map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: Self.canvas))

        window.frame = CGRect(origin: .zero, size: Self.canvas)
        window.backgroundColor = .black
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .normal + 10

        let host = UIHostingController(
            rootView: view
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
                // Animations off: the render has to be deterministic.
                .environment(\.plinkFreezeAnimations, true)
                .transaction { $0.disablesAnimations = true }
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        window.rootViewController = host

        window.isHidden = false
        window.makeKeyAndVisible()
        host.view.frame = window.bounds

        let ambient = host.view.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(
            top: max(0, Self.screenSafeArea.top - ambient.top),
            left: 0,
            bottom: max(0, Self.screenSafeArea.bottom - ambient.bottom),
            right: 0
        )
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Let SwiftUI run .task/.onAppear. A nested RunLoop is wrong here — it holds
        // the main thread (see MarketingShots).
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        CATransaction.flush()

        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.scale
        format.opaque = true
        let bounds = CGRect(origin: .zero, size: Self.canvas)

        func render() -> UIImage {
            UIGraphicsImageRenderer(size: Self.canvas, format: format).image { ctx in
                UIColor.black.setFill()
                ctx.fill(bounds)
                host.view.drawHierarchy(in: bounds, afterScreenUpdates: false)
            }
        }

        // One render, with no "wait for it to settle" loop. Both alternatives were
        // tried here and both were worse, which is why this looks too simple:
        //
        //   - A fixed 1.2s pause. The screen animates in on a 0.62s spring, and roughly
        //     every third frame captured mid-transition. It read as a real regression —
        //     "the button went dark, the logo faded" — when nothing had changed.
        //   - A "render until two frames match" loop. Worse: the background animates
        //     FOREVER, so the frames never converge, the loop ran to its ceiling, and
        //     repeated `drawHierarchy` calls in one pass sometimes returned an empty
        //     image — a frame with no form and no logo at all.
        //
        // The answer is not to outwait the animations but to switch them off:
        // `plinkFreezeAnimations` puts the scene straight into its final state. One
        // render is then enough, and the result is reproducible byte for byte.
        let image = render()

        guard let data = image.pngData() else {
            XCTFail("Could not encode PNG for \(name)")
            return
        }
        let directory = outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(name).png")
        try data.write(to: file, options: .atomic)
        print("AUDIT_SHOT \(file.path) \(data.count) bytes")

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
