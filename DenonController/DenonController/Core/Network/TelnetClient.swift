import Network
import Foundation

// MARK: - TelnetClient

/// AVR との TCP 接続を管理する Actor。
/// コマンドを送信し、AVR からのレスポンスを AsyncStream で配信する。
actor TelnetClient {

    // MARK: Public stream

    nonisolated let updates: AsyncStream<String>
    private nonisolated let continuation: AsyncStream<String>.Continuation

    // MARK: Private state

    private var connection: NWConnection?
    private var receiveBuffer = ""

    // MARK: Init / Deinit

    init() {
        let (stream, cont) = AsyncStream<String>.makeStream()
        updates = stream
        continuation = cont
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Connect

    func connect(host: String, port: UInt16 = 23) async throws {
        await internalDisconnect()

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let conn = NWConnection(to: endpoint, using: .tcp)
        connection = conn

        // ResumeOnce prevents double-resume when NWConnection fires multiple state events
        final class ResumeOnce: @unchecked Sendable {
            private var done = false
            private let lock = NSLock()
            func resume(with cont: CheckedContinuation<Void, Error>, result: Result<Void, Error>) {
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                switch result {
                case .success:  cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
        }

        // 10秒タイムアウト付きで接続を待つ
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    let once = ResumeOnce()
                    conn.stateUpdateHandler = { [weak self] state in
                        switch state {
                        case .ready:
                            once.resume(with: cont, result: .success(()))
                            Task { await self?.scheduleReceive() }
                        case .failed(let err):
                            once.resume(with: cont, result: .failure(err))
                        // .waiting = NWConnection が経路を探している過渡状態。
                        // 有線+WiFi 混在環境で一時的に発生するが、そのまま .ready に進む。
                        // ここでエラーにすると NIC が複数ある Mac で必ず失敗する。
                        case .waiting:
                            break
                        default:
                            break
                        }
                    }
                    conn.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw AVRError.connectionFailed("タイムアウト（10秒）")
            }
            // どちらか先に完了したらもう一方をキャンセル
            try await group.next()!
            group.cancelAll()
        }
    }

    // MARK: - Send

    func send(_ command: String) async throws {
        guard let conn = connection else { throw AVRError.notConnected }
        let data = Data((command + "\r").utf8)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        await internalDisconnect()
    }

    private func internalDisconnect() async {
        connection?.cancel()
        connection = nil
        receiveBuffer = ""
    }

    // MARK: - Receive loop

    private func scheduleReceive() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            Task { [weak self] in
                guard let self else { return }
                if let data, let str = String(data: data, encoding: .ascii) {
                    await self.processReceived(str)
                }
                if error == nil && !isComplete {
                    await self.scheduleReceive()
                }
            }
        }
    }

    private func processReceived(_ str: String) {
        receiveBuffer += str
        // Denon uses \r as line terminator
        let parts = receiveBuffer.components(separatedBy: "\r")
        receiveBuffer = parts.last ?? ""
        for line in parts.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                continuation.yield(trimmed)
            }
        }
    }
}
