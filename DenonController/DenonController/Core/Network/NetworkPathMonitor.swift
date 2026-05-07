import Foundation
import Network
import Observation

@Observable
final class NetworkPathMonitor: Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cc.nyoyapoya.NetworkMonitor")
    
    var isReachable: Bool = true
    var isWiFi: Bool = false
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isReachable = (path.status == .satisfied)
                self?.isWiFi = path.usesInterfaceType(.wifi)
                print("[DenonLog] Network status changed: reachable=\(path.status == .satisfied), wifi=\(path.usesInterfaceType(.wifi))")
            }
        }
        monitor.start(queue: queue)
    }
    
    func stop() {
        monitor.cancel()
    }
}
