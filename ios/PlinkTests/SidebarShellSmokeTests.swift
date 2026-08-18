//  SidebarShellSmokeTests.swift
//  iPad-шелл схлопнут на живой V4-стек. У владельца нет
//  физического iPad, поэтому рендер-смоук фиксирует, что PlinkSidebarShell
//  монтируется со всеми пятью секциями без крэша: инстанцирование V4-экранов
//  внутри detail(for:) и bootstrap-цепочка сторов выполняются при layout.

import XCTest
import SwiftUI
@testable import Plink

@MainActor
final class SidebarShellSmokeTests: XCTestCase {

    private func makeDependencies() -> AppDependencies {
        let api = APIClient.shared
        return AppDependencies(
            apiClient: api,
            authService: AuthService.shared,
            roomService: RoomService(api: api)
        )
    }

    /// Каждая из пяти секций монтируется и проходит layout в окне iPad-размера.
    func testSidebarShell_mountsEverySection() throws {
        for section in AppSection.allCases {
            var selection = section
            let shell = PlinkSidebarShell(
                selection: Binding(get: { selection }, set: { selection = $0 }),
                createPresented: .constant(false),
                dependencies: makeDependencies()
            )
            let host = UIHostingController(rootView: shell)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1194, height: 834))
            window.rootViewController = host
            window.isHidden = false
            host.view.layoutIfNeeded()
            XCTAssertNotNil(host.view.window, "Секция \(section) не смонтировалась")
            window.isHidden = true
            window.rootViewController = nil
        }
    }
}
