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
    var isEthernet: Bool = false
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            let isWiFi = path.usesInterfaceType(.wifi)
            let isEthernet = path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor in
                self?.isReachable = (status == .satisfied)
                self?.isWiFi = isWiFi
                self?.isEthernet = isEthernet
                print("[DenonLog] Network status: reachable=\(status == .satisfied), wifi=\(isWiFi), eth=\(isEthernet)")
            }
        }
        monitor.start(queue: queue)
    }
    
    func stop() {
        monitor.cancel()
    }
}
