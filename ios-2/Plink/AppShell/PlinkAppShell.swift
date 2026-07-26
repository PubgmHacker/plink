// Plink/AppShell/PlinkAppShell.swift — GPT-5.6 V4 Pixel Perfect
//
// iPhone: PlinkApprovedV4Root (pixel-perfect V4 from spec)
// iPad: PlinkSidebarShell (existing)

import SwiftUI

struct PlinkAppShell: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: AppSection = .home
    @State private var createPresented: Bool = false
    @State private var createIntent: CreateRoomIntent?
    @State private var createdRoom: Room?

    let dependencies: AppDependencies

    var body: some View {
        Group {
            #if os(macOS)
            PlinkSidebarShell(
                selection: $selection,
                createPresented: $createPresented,
                dependencies: dependencies
            )
            #else
            if horizontalSizeClass == .regular {
                PlinkSidebarShell(
                    selection: $selection,
                    createPresented: $createPresented,
                    dependencies: dependencies
                )
            } else {
                // GPT-5.6 V4 Pixel Perfect: single root
                PlinkApprovedV4Root()
            }
            #endif
        }
        .sheet(item: $createIntent) { intent in
            RoomCreationView(
                onRoomCreated: { room in
                    createIntent = nil
                    createdRoom = room
                }
            )
            .environmentObject(dependencies.apiClient)
        }
        .fullScreenCover(item: $createdRoom) { room in
            // Always use session-hydrating container (correct userId keys + token)
            WatchRoomContainer(room: room)
        }
    }
}
