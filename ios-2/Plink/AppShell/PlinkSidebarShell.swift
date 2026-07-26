// Plink/AppShell/PlinkSidebarShell.swift — §4 Final Architecture
// iPad/Mac sidebar shell. Uses AppSection enum (home/rooms/ai/friends/profile).

import SwiftUI

struct PlinkSidebarShell: View {
    @Binding var selection: AppSection
    @Binding var createPresented: Bool
    let dependencies: AppDependencies

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    Label("Plink", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Cinema2026.text)
                        .listRowBackground(Color.clear)
                }

                Section("Смотреть") {
                    nav(.home)
                    nav(.rooms)
                    nav(.ai)
                    nav(.friends)
                }

                Section {
                    Button {
                        createPresented = true
                    } label: {
                        Label("Создать комнату", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Cinema2026.accent)
                }

                Section {
                    nav(.profile)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
            .scrollContentBackground(.hidden)
            .background(Cinema2026.background)
        } detail: {
            detail(for: selection)
        }
        .navigationSplitViewStyle(.balanced)
        .environmentObject(dependencies.apiClient)
    }

    private func nav(_ section: AppSection) -> some View {
        NavigationLink(value: section) {
            Label(section.title, systemImage: section.symbol)
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .home:
            DiscoveryHomeView(dependencies: dependencies)
        case .rooms:
            VStack { Text("Комнаты").font(.title) }
        case .ai:
            AIAssistantView()
        case .friends:
            FriendsView()
        case .profile:
            ProfileView(
                viewModel: ProfileViewModel(authService: dependencies.authService),
                onSignOut: { Task { try? await dependencies.authService.signOut() } }
            )
        }
    }
}
