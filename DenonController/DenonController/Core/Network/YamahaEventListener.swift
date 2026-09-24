import Foundation
import Darwin

/// Yamaha（YXC）の状態変化の通知を UDP で受け取る。
///
/// YXC のリクエストに `X-AppName` と `X-AppPort` のヘッダーを付けると、その後 10 分間、本体の状態が変わるたびに
/// そのポートへ JSON の通知が届く（10 分以内に次のリクエストを送れば延長される）。本体や付属リモコンでの操作を
/// すぐ画面に反映するため（Denon の Telnet の通知にあたる）。受け取るだけなのでマルチキャストの権限は要らない。
/// 仕様: Yamaha Extended Control API Specification (Basic) 10. Events
final class YamahaEventListener: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private(set) var port: UInt16 = 0

    /// 受信用のソケットを開き、空いているポートを割り当ててもらう。受け取った通知の本文を `onEvent` に渡す。
    /// `expectedHost` 以外から届いたものは捨てる
    func start(expectedHost: String, onEvent: @escaping @Sendable (Data) -> Void) -> UInt16? {
        stop()
        let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard s >= 0 else { return nil }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &len) }
        }
        guard bound == 0, named == 0 else { Darwin.close(s); return nil }
        // 受信を 1 秒ごとに区切り、止めたかどうかを確かめられるようにする
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let assigned = UInt16(bigEndian: addr.sin_port)
        lock.lock(); fd = s; port = assigned; lock.unlock()

        let expected = inet_addr(expectedHost)
        Thread.detachNewThread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 8192)
            while let self, self.currentFD == s {
                var from = sockaddr_in()
                var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(s, &buf, buf.count, 0, $0, &fromLen) }
                }
                guard n > 0 else { continue }   // タイムアウト（または止められた）
                guard expected == INADDR_NONE || from.sin_addr.s_addr == expected else { continue }
                onEvent(Data(buf[0..<n]))
            }
        }
        return assigned
    }

    func stop() {
        lock.lock()
        let s = fd
        fd = -1
        port = 0
        lock.unlock()
        if s >= 0 { Darwin.close(s) }
    }

    private var currentFD: Int32 {
        lock.lock(); defer { lock.unlock() }
        return fd
    }

    deinit { stop() }
}
