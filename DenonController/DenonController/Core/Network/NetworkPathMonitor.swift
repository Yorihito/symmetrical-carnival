import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkPathMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cc.nyoyapoya.NetworkMonitor")
    
    var isReachable: Bool = true
    var isWiFi: Bool = false
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            let isWiFi = path.usesInterfaceType(.wifi)
            Task { @MainActor in
                self?.isReachable = (status == .satisfied)
                self?.isWiFi = isWiFi
                print("[DenonLog] Network status changed: reachable=\(status == .satisfied), wifi=\(isWiFi)")
            }
        }
        monitor.start(queue: queue)
    }
    
    func stop() {
        monitor.cancel()
    }
}
