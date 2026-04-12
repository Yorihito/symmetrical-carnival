import Foundation

enum SurroundMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case movie         = "MOVIE"
    case music         = "MUSIC"
    case game          = "GAME"
    case pureDirect    = "PURE DIRECT"
    case direct        = "DIRECT"
    case stereo        = "STEREO"
    case auto          = "AUTO"
    case dolbySurround = "DOLBY SURROUND"
    case dtsNeuralX    = "DTS NEURAL:X"
    case auro3D        = "AURO3D"
    case imaxDTS       = "IMAX DTS"

    var id: String { rawValue }

    var command: String { "MS\(rawValue)" }

    var displayName: String {
        switch self {
        case .movie:         "Movie"
        case .music:         "Music"
        case .game:          "Game"
        case .pureDirect:    "Pure Direct"
        case .direct:        "Direct"
        case .stereo:        "Stereo"
        case .auto:          "Auto"
        case .dolbySurround: "Dolby Surround"
        case .dtsNeuralX:    "DTS:X"
        case .auro3D:        "Auro-3D"
        case .imaxDTS:       "IMAX DTS"
        }
    }

    var systemImage: String {
        switch self {
        case .movie:         "film"
        case .music:         "music.note"
        case .game:          "gamecontroller"
        case .pureDirect:    "waveform.path.ecg"
        case .direct:        "arrow.right.circle"
        case .stereo:        "speaker.2"
        case .auto:          "sparkles"
        case .dolbySurround: "dot.radiowaves.left.and.right"
        case .dtsNeuralX:    "brain"
        case .auro3D:        "cube"
        case .imaxDTS:       "tv.badge.wifi"
        }
    }

    init?(rawCode: String) {
        // Try exact match first; then prefix match for partial responses
        if let exact = SurroundMode(rawValue: rawCode) {
            self = exact
            return
        }
        for mode in SurroundMode.allCases where rawCode.hasPrefix(mode.rawValue) {
            self = mode
            return
        }
        return nil
    }
}
