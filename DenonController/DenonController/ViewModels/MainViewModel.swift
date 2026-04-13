import SwiftUI

// MARK: - ConnectionStatus

enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: LocalizedStringKey {
        switch self {
        case .disconnected: "未接続"
        case .connecting:   "接続中..."
        case .connected:    "接続済み"
        case .error:        "エラー"
        }
    }

    var isConnected: Bool { self == .connected }
}

// MARK: - MainViewModel

/// UI と AVRHTTPClient を繋ぐ ViewModel。すべての AVR 操作はここ経由で行う。
@Observable
@MainActor
final class MainViewModel {

    // MARK: - Public state
    let avr = AVRState()
    let presetStore = PresetStore()
    let inputNames = InputNameStore()
    let discovery = MDNSDiscovery()

    var connectionStatus: ConnectionStatus = .disconnected
    var connectingDetail: String = ""   // 接続中の進捗メッセージ
    var errorMessage: String?
    var lastConnectedHost: String = ""

    // MARK: - Private
    private let client = AVRHTTPClient()
    private var updateTask: Task<Void, Never>?

    // MARK: - Connection

    func connect(host: String) async {
        guard !connectionStatus.isConnected else { return }
        connectionStatus = .connecting
        connectingDetail = ""
        errorMessage = nil

        do {
            var info = try await client.connect(host: host, port: 8080) { [weak self] step in
                Task { @MainActor [weak self] in
                    self?.connectingDetail = step
                }
            }
            // Zone 3 サポートを非同期で確認
            info.hasZone3 = await client.probeZone3()

            connectingDetail = ""
            connectionStatus = .connected
            avr.isConnected = true
            avr.deviceInfo  = info
            lastConnectedHost = host

            // Consume HTTP polling stream
            updateTask = Task { [weak self] in
                guard let self else { return }
                for await snapshot in await client.updates {
                    self.avr.apply(snapshot)
                }
                self.handleDisconnect()
            }

        } catch {
            connectingDetail = ""
            connectionStatus = .error(error.localizedDescription)
            avr.isConnected = false
        }
    }

    func disconnect() {
        updateTask?.cancel()
        updateTask = nil
        Task { await client.disconnect() }
        handleDisconnect()
    }

    private func handleDisconnect() {
        connectionStatus = .disconnected
        avr.isConnected = false
    }

    // MARK: - Power

    func setPower(_ on: Bool) {
        send(on ? "PWON" : "PWSTANDBY")
    }

    func togglePower() { setPower(!avr.isPoweredOn) }

    // MARK: - Volume

    func volumeUp()   { send("MVUP") }
    func volumeDown() { send("MVDOWN") }

    /// db: 実際の dB 値（-80 〜 +18）
    func setVolume(_ db: Double) {
        send(AVRState.volumeCommand(forDB: db))
    }

    func setMute(_ on: Bool) { send(on ? "MUON" : "MUOFF") }
    func toggleMute()        { setMute(!avr.isMuted) }

    // MARK: - Input

    func setInput(_ input: InputSource) {
        send(input.command)
    }

    // MARK: - Surround（HTTP では取得不可 → 送信してローカル追跡）

    func setSurroundMode(_ mode: SurroundMode) {
        send(mode.command)
        avr.surroundMode = mode   // ポーリングで取得できないのでローカル更新
    }

    // MARK: - Zone 2

    func setZone2Power(_ on: Bool) { send(on ? "Z2ON" : "Z2OFF") }
    func zone2VolumeUp()           { send("Z2UP") }
    func zone2VolumeDown()         { send("Z2DOWN") }
    func setZone2Mute(_ on: Bool)  { send(on ? "Z2MUON" : "Z2MUOFF") }

    // MARK: - Zone 3

    func setZone3Power(_ on: Bool) { send(on ? "Z3ON" : "Z3OFF") }
    func zone3VolumeUp()           { send("Z3UP") }
    func zone3VolumeDown()         { send("Z3DOWN") }

    // MARK: - Presets

    func applyPreset(_ preset: Preset) {
        setInput(preset.input)
        setVolume(preset.volumeDB)
        setSurroundMode(preset.surroundMode)
    }

    func saveCurrentAsPreset(name: String, emoji: String) {
        let preset = Preset(
            name: name, emoji: emoji,
            input: avr.input,
            volumeDB: avr.volumeDB,
            surroundMode: avr.surroundMode
        )
        presetStore.save(preset)
    }

    // MARK: - Private helper

    private func send(_ command: String) {
        Task { [weak self] in
            guard let self else { return }
            await client.send(command)
        }
    }
}
