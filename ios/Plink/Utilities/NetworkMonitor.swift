import Foundation
import Network
import SwiftUI

// MARK: - NetworkMonitor
// Отслеживает доступность сети без poll-опросов.
// Использует NWPathMonitor (Apple Networking framework)
// — более точный и энергоэффективный, чем Reachability.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: ConnectionType = .unknown

    enum ConnectionType {
        case wifi, cellular, wired, unknown
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "plink.network.monitor", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let type: ConnectionType = {
                if path.usesInterfaceType(.wifi) { return .wifi }
                if path.usesInterfaceType(.cellular) { return .cellular }
                if path.usesInterfaceType(.wiredEthernet) { return .wired }
                return .unknown
            }()
            Task { @MainActor [weak self] in
                self?.isConnected = connected
                self?.connectionType = type
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - Offline Banner
/// Прозрачный баннер появляется поверх любого View когда нет сети.
struct OfflineBannerModifier: ViewModifier {
    @ObservedObject private var net = NetworkMonitor.shared

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if !net.isConnected {
                OfflineBannerView()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: net.isConnected)
    }
}

struct OfflineBannerView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .semibold))
            Text(LocalizationManager.shared.string(.offlineTitle))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.88))
        .ignoresSafeArea(edges: .top)
    }
}

extension View {
    /// Добавь на любой View, чтобы показывать оффлайн-баннер автоматически.
    func withOfflineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}
