import Foundation

enum InputSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case phono       = "PHONO"
    case cd          = "CD"
    case tuner       = "TUNER"
    case dvd         = "DVD"
    case bluray      = "BD"
    case tv          = "TV"
    case cblSat      = "SAT/CBL"
    case mediaPlayer = "MPLAY"
    case game        = "GAME"
    case hdmi1       = "HDMI1"
    case hdmi2       = "HDMI2"
    case hdmi3       = "HDMI3"
    case hdmi4       = "HDMI4"
    case hdmi5       = "HDMI5"
    case hdmi6       = "HDMI6"
    case hdmi7       = "HDMI7"
    case hdmi8       = "HDMI8"
    case bluetooth   = "BT"
    case network     = "NET"
    case aux1        = "AUX1"
    case aux2        = "AUX2"

    var id: String { rawValue }

    /// Telnet コマンド文字列
    var command: String { "SI\(rawValue)" }

    var displayName: String {
        switch self {
        case .phono:       "PHONO"
        case .cd:          "CD"
        case .tuner:       "Tuner"
        case .dvd:         "DVD"
        case .bluray:      "Blu-ray"
        case .tv:          "TV Audio"
        case .cblSat:      "CBL/SAT"
        case .mediaPlayer: "Media Player"
        case .game:        "GAME"
        case .hdmi1:       "HDMI 1"
        case .hdmi2:       "HDMI 2"
        case .hdmi3:       "HDMI 3"
        case .hdmi4:       "HDMI 4"
        case .hdmi5:       "HDMI 5"
        case .hdmi6:       "HDMI 6"
        case .hdmi7:       "HDMI 7"
        case .hdmi8:       "HDMI 8"
        case .bluetooth:   "Bluetooth"
        case .network:     "Network"
        case .aux1:        "AUX 1"
        case .aux2:        "AUX 2"
        }
    }

    var systemImage: String {
        switch self {
        case .hdmi1, .hdmi2, .hdmi3, .hdmi4,
             .hdmi5, .hdmi6, .hdmi7, .hdmi8: "cable.connector"
        case .bluetooth:   "dot.radiowaves.left.and.right"
        case .network:     "network"
        case .tv:          "tv"
        case .bluray:      "opticaldisc"
        case .dvd:         "opticaldisc"
        case .cd:          "opticaldisc"
        case .phono:       "record.circle"
        case .tuner:       "antenna.radiowaves.left.and.right"
        case .game:        "gamecontroller"
        case .mediaPlayer: "play.circle"
        case .cblSat:      "tv.and.mediabox"
        case .aux1, .aux2: "headphones.circle"
        }
    }

    /// カスタム名ストアを参照した表示名。未設定なら displayName を使用。
    @MainActor
    func name(using store: InputNameStore) -> String {
        store.customName(for: self) ?? displayName
    }

    init?(rawCode: String) {
        self.init(rawValue: rawCode)
    }
}
