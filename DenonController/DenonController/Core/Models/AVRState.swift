import Foundation
import Observation

/// AVR-X3800H のリアルタイム状態を保持する Observable モデル。
/// HTTP ポーリングで得た AVRStatusSnapshot を apply(_:) で適用する。
@Observable
@MainActor
final class AVRState {

    // MARK: - Device Info
    var deviceInfo: DeviceInfo = .unknown

    // MARK: - Connection
    var isConnected = false

    // MARK: - Main Zone
    var isPoweredOn   = false
    var volumeDB:  Double = -60.0   // 実際の dB 値（-80 〜 +18）
    var isMuted       = false
    var input: InputSource   = .hdmi1
    var surroundMode: SurroundMode = .auto   // HTTP では取得不可 → コマンド送信時に追跡

    // MARK: - Zone 2
    var zone2Power:    Bool   = false
    var zone2VolumeDB: Double = -40.0
    var zone2Mute:     Bool   = false
    var zone2Input:    InputSource = .hdmi1

    // MARK: - Zone 3（HTTP API では音量のみポーリング不可 → コマンドのみ）
    var zone3Power:    Bool   = false
    var zone3VolumeDB: Double = -40.0
    var zone3Mute:     Bool   = false

    // MARK: - Computed

    /// Denon 表示単位（AVR 本体の表示と同じ 0–98 の整数）
    /// dB = unit − 80  なので:  -50 dB → 30, 0 dB → 80
    var volumeUnit: Int { Int((volumeDB + 80.0).rounded()) }
    var zone2VolumeUnit: Int { Int((zone2VolumeDB + 80.0).rounded()) }
    var zone3VolumeUnit: Int { Int((zone3VolumeDB + 80.0).rounded()) }

    /// AVR 本体と同じ表示（例: "30"）
    var volumeDBString: String { "\(volumeUnit)" }
    var zone2VolumeDBString: String { "\(zone2VolumeUnit)" }
    var zone3VolumeDBString: String { "\(zone3VolumeUnit)" }

    /// 参照用 dB 文字列（スライダーラベルなどに使用）
    var volumedBLabel: String {
        volumeDB.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f dB", volumeDB)
            : String(format: "%.1f dB", volumeDB)
    }

    // MARK: - Apply HTTP snapshot

    func apply(_ snap: AVRStatusSnapshot) {
        isPoweredOn  = snap.isPoweredOn
        volumeDB     = snap.volumeDB
        isMuted      = snap.isMuted

        if let src = InputSource(rawCode: snap.inputCode) {
            input = src
        }

        zone2Power    = snap.zone2Power
        zone2VolumeDB = snap.zone2VolumeDB
        zone2Mute     = snap.zone2Muted

        if let src = InputSource(rawCode: snap.zone2InputCode) {
            zone2Input = src
        }
    }

    // MARK: - Volume command helpers

    /// dB 値を Denon コマンド文字列に変換（例: -30.0 → "MV50", -30.5 → "MV495"）
    static func volumeCommand(forDB db: Double) -> String {
        let unit = db + 80.0   // -80dB → 0, 0dB → 80, +18dB → 98
        let clamped = max(0.0, min(98.0, unit))
        if clamped.truncatingRemainder(dividingBy: 1) == 0 {
            return "MV\(Int(clamped))"
        } else {
            // 例: 49.5 → "MV495"
            return "MV\(Int(clamped * 10))"
        }
    }
}
