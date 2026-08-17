// Plink/V4/PlinkV4PixelPerfect.swift — residual after module split
// Palette (`enum V4`, Color.oklch) lives in V4Theme.swift — do not redeclare.

import SwiftUI
import Foundation
import UserNotifications
import UIKit

extension PlinkAppDelegate {
    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
}

// plinkLiveThemeChanged notification
extension Notification.Name {
    static let plinkLiveThemeChanged = Notification.Name("plinkLiveThemeChanged")
}
