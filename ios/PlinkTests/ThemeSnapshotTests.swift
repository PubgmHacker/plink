// pixel-level UI regression tests.
//
// Guards against visual regressions in the theme catalog (the «пропали
// Amber/Electric» incident). Snapshot tests render real UI and depend on the
// simulator model, so they are opt-in: they only run when SNAPSHOT_TESTS=1.
//
// Workflow:
//   1) First run records reference images and FAILS with "No reference" —
//      commit the generated __Snapshots__ folder next to this file.
//   2) Subsequent runs compare pixel-perfect against the references.
//
// Run locally:
//   SNAPSHOT_TESTS=1 xcodebuild test -project Plink.xcodeproj -scheme Plink \
//     -destination 'platform=iOS Simulator,name=iPhone 16'

import XCTest
import SwiftUI
import SnapshotTesting
@testable import Plink

@MainActor
final class ThemeSnapshotTests: XCTestCase {
    private func requireSnapshotsEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SNAPSHOT_TESTS"] == "1",
            "Set SNAPSHOT_TESTS=1 to run snapshot tests (results depend on simulator model)."
        )
    }

    func testV4ThemeSwatchCatalog() throws {
        try requireSnapshotsEnabled()
        let view = VStack(spacing: 12) {
            ForEach(V4Theme.allCases, id: \.self) { theme in
                HStack(spacing: 10) {
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 24, height: 24)
                    Text(theme.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(Color.black)

        assertSnapshot(of: UIHostingController(rootView: view), as: .image(on: .iPhone13))
    }

    func testPlinkPlusLiveThemeSwatchCatalog() throws {
        try requireSnapshotsEnabled()
        let view = VStack(spacing: 12) {
            ForEach(PlinkPlusLiveTheme.allCases) { theme in
                HStack(spacing: 10) {
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 24, height: 24)
                    Text(theme.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(Color.black)

        assertSnapshot(of: UIHostingController(rootView: view), as: .image(on: .iPhone13))
    }
}
