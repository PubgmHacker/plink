// Plink/AppShell/PlinkAppShell.swift — root view; selects the shell per device.
//
// iPhone: PlinkApprovedV4Root (pixel-perfect V4 layout)
// iPad / macOS: PlinkSidebarShell

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PlinkAppShell: View {
    @State private var selection: AppSection = .home
    @State private var createPresented: Bool = false
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
            // Выбор шелла по устройству, а не по size class.
            // На iPhone Max/Plus в landscape horizontalSizeClass становится .regular:
            // поворот живьём пересобирал корневой шелл (V4Root ↔ Sidebar), убивая
            // все @State-сторы и дисмисся fullScreenCover открытой комнаты.
            if UIDevice.current.userInterfaceIdiom == .pad {
                PlinkSidebarShell(
                    selection: $selection,
                    createPresented: $createPresented,
                    dependencies: dependencies
                )
            } else {
                // Single root view on iPhone.
                PlinkApprovedV4Root()
            }
            #endif
        }
        // Лист висел на $createIntent, который никто не
        // выставлял, — кнопка «Создать комнату» в сайдбаре iPad/Mac (она пишет
        // в createPresented) не открывала ничего. Теперь лист слушает тот же
        // флаг, а мёртвый createIntent убран.
        .sheet(isPresented: $createPresented) {
            RoomCreationView(
                onRoomCreated: { room in
                    createPresented = false
                    // Закрытие листа и открытие fullScreenCover в одной
                    // транзакции — SwiftUI теряет вторую презентацию, и комната
                    // создаётся «в пустоту». На iPhone (PlinkApprovedV4Root:132)
                    // ровно для этого стоит аналогичная задержка.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        createdRoom = room
                    }
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
