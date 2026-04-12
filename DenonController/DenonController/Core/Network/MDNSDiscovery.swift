import Network
import Foundation
import Observation

// MARK: - Discovered Device

struct DiscoveredDevice: Identifiable, Sendable {
    let id: String          // service name (unique)
    let name: String        // human-readable label
    let endpoint: NWEndpoint
}

// MARK: - MDNSDiscovery

/// Bonjour で LAN 上の Denon / HEOS デバイスを検出する。
@Observable
@MainActor
final class MDNSDiscovery {

    var devices: [DiscoveredDevice] = []
    var isSearching = false

    private var browser: NWBrowser?

    func start() {
        guard !isSearching else { return }
        isSearching = true
        devices = []

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: "_denon-heos._tcp",
            domain: nil
        )
        let browser = NWBrowser(for: descriptor, using: .tcp)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found: [DiscoveredDevice] = results.compactMap { result in
                guard case .service(let name, let type, let domain, _) = result.endpoint else {
                    return nil
                }
                let endpoint = NWEndpoint.service(
                    name: name, type: type, domain: domain, interface: nil
                )
                return DiscoveredDevice(id: name, name: name, endpoint: endpoint)
            }
            Task { @MainActor [weak self] in
                self?.devices = found
            }
        }

        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor [weak self] in
                    self?.isSearching = false
                }
            }
        }

        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }
}
