import Foundation
import Observation

// MARK: - ConnectionStatus

enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected:    "未接続"
        case .connecting:      "接続中..."
        case .connected:       "接続済み"
        case .error(let msg):  "エラー: \(msg)"
        }
    }

    var isConnected: Bool { self == .connected }
}

// MARK: - MainViewModel

/// UI と TelnetClient を繋ぐ ViewModel。すべての AVR 操作はここ経由で行う。
@Observable
@MainActor
final class MainViewModel {

    // MARK: - Public state
    let avr = AVRState()
    let presetStore = PresetStore()
    let discovery = MDNSDiscovery()

    var connectionStatus: ConnectionStatus = .disconnected
    var errorMessage: String?
    var lastConnectedHost: String = ""

    // MARK: - Private
    private let client = TelnetClient()
    private var updateTask: Task<Void, Never>?

    // MARK: - Connection

    func connect(host: String, port: UInt16 = 23) async {
        guard !connectionStatus.isConnected else { return }
        connectionStatus = .connecting
        errorMessage = nil

        do {
            try await client.connect(host: host, port: port)
            connectionStatus = .connected
            avr.isConnected = true
            lastConnectedHost = host

            // Consume update stream
            updateTask = Task { [weak self] in
                guard let self else { return }
                for await line in await client.updates {
                    self.avr.apply(line)
                }
                // Stream ended → disconnected
                self.handleDisconnect()
            }

            // Sync current AVR state
            for cmd in AVRState.queryCommands {
                try? await client.send(cmd)
                try? await Task.sleep(for: .milliseconds(60))
            }

        } catch {
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

    /// value: Denon units 0–98
    func setVolume(_ value: Double) {
        let intVal = Int(value.rounded())
        let clamped = max(0, min(98, intVal))
        send("MV\(clamped)")
    }

    func setMute(_ on: Bool) { send(on ? "MUON" : "MUOFF") }
    func toggleMute()        { setMute(!avr.isMuted) }

    // MARK: - Input

    func setInput(_ input: InputSource) { send(input.command) }

    // MARK: - Surround

    func setSurroundMode(_ mode: SurroundMode) { send(mode.command) }

    // MARK: - Zone 2

    func setZone2Power(_ on: Bool) { send(on ? "Z2ON" : "Z2OFF") }
    func zone2VolumeUp()           { send("Z2UP") }
    func zone2VolumeDown()         { send("Z2DOWN") }
    func setZone2Mute(_ on: Bool)  { send(on ? "Z2MUON" : "Z2MUOFF") }

    // MARK: - Zone 3

    func setZone3Power(_ on: Bool) { send(on ? "Z3ON" : "Z3OFF") }
    func zone3VolumeUp()           { send("Z3UP") }
    func zone3VolumeDown()         { send("Z3DOWN") }
    func setZone3Mute(_ on: Bool)  { send(on ? "Z3MUON" : "Z3MUOFF") }

    // MARK: - Presets

    func applyPreset(_ preset: Preset) {
        setInput(preset.input)
        setVolume(preset.volume)
        setSurroundMode(preset.surroundMode)
    }

    func saveCurrentAsPreset(name: String, emoji: String) {
        let preset = Preset(
            name: name, emoji: emoji,
            input: avr.input,
            volume: avr.volume,
            surroundMode: avr.surroundMode
        )
        presetStore.save(preset)
    }

    // MARK: - Private helper

    private func send(_ command: String) {
        Task { [weak self] in
            guard let self else { return }
            try? await client.send(command)
        }
    }
}
