import Foundation
import Observation

/// 接続中の AV レシーバーのリアルタイム状態を保持する Observable モデル（メーカー共通）。
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
    /// 選択中の入力 ID（Denon は "HDMI1"、Yamaha は "hdmi1" など）
    var inputID: String = InputSource.hdmi1.rawValue
    
    /// 最後にアンプから正常に応答を受け取った時刻。
    /// 数値に変化がなくても更新されるため、UI の同期完了検知に使用する。
    var lastUpdate = Date()
    /// 選択中のサウンドモード ID。Denon は HTTP では取得できないので、コマンド送信時と Telnet の通知で追跡する
    var soundModeID: String = SurroundMode.auto.rawValue

    /// Denon の入力（1.1.x までの画面・macOS 版との互換用）
    var input: InputSource {
        get { InputSource(rawValue: inputID) ?? .hdmi1 }
        set { inputID = newValue.rawValue }
    }

    /// Denon のサラウンドモード（1.1.x までの画面・macOS 版との互換用）
    var surroundMode: SurroundMode {
        get { SurroundMode(rawCode: soundModeID) ?? .auto }
        set { soundModeID = newValue.rawValue }
    }

    // MARK: - Zone 2
    var zone2Power:    Bool   = false
    var zone2VolumeDB: Double = -40.0
    var zone2Mute:     Bool   = false
    var zone2InputID:  String = InputSource.hdmi1.rawValue

    // MARK: - Zone 3（HTTP API では音量のみポーリング不可 → コマンドのみ）
    var zone3Power:    Bool   = false
    var zone3VolumeDB: Double = -40.0
    var zone3Mute:     Bool   = false

    // MARK: - Tuner
    var tunerBand:        TunerBand = .fm
    var tunerFrequency:   String    = ""   // "87.50" or "558"
    var tunerPreset:      Int       = 0    // 0 = プリセット外
    var tunerStationName: String    = ""   // AVR に登録された局名

    // MARK: - Computed

    /// AVR 本体と同じ表示（例: "30", "30.5"）
    private static func unitString(_ db: Double) -> String {
        String(format: "%.1f", db + 80.0)
    }
    var volumeDBString: String { Self.unitString(volumeDB) }
    var zone2VolumeDBString: String { Self.unitString(zone2VolumeDB) }
    var zone3VolumeDBString: String { Self.unitString(zone3VolumeDB) }

    /// 参照用 dB 文字列（スライダーラベルなどに使用）
    var volumedBLabel: String { String(format: "%.1f dB", volumeDB) }

    // MARK: - Apply HTTP snapshot

    func apply(_ snap: AVRStatusSnapshot) {
        lastUpdate = Date()
        
        if self.volumeDB != snap.volumeDB {
            print("[DenonLog] AVRState: Applying new volume: \(snap.volumeDB) (Old: \(self.volumeDB))")
        }
        isPoweredOn  = snap.isPoweredOn
        volumeDB     = snap.volumeDB
        isMuted      = snap.isMuted

        if !snap.inputCode.isEmpty { inputID = snap.inputCode }

        zone2Power    = snap.zone2Power
        zone2VolumeDB = snap.zone2VolumeDB
        zone2Mute     = snap.zone2Muted

        if !snap.zone2InputCode.isEmpty { zone2InputID = snap.zone2InputCode }

        // Tuner（チューナー XML を取得でき、かつ周波数が確定しているときだけ更新）
        // tunerBand は HTTP から更新しない — XML は切替直後に古いバンドを返すことがある。
        // バンド状態は setTunerBand の楽観的更新と Telnet の parseTelnetLine で管理する。
        if snap.tunerDataFetched && !snap.tunerFrequency.isEmpty {
            tunerFrequency   = snap.tunerFrequency
            tunerPreset      = snap.tunerPreset
            tunerStationName = snap.tunerStationName
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
