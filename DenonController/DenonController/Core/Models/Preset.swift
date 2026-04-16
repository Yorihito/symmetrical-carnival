import Foundation

struct Preset: Identifiable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var emoji: String
    var input: InputSource
    var volumeDB: Double       // 実際の dB 値（-80 〜 +18）
    var surroundMode: SurroundMode

    static let examples: [Preset] = [
        Preset(name: "Movie", emoji: "🎬",
               input: .hdmi1, volumeDB: -30, surroundMode: .movie),
        Preset(name: "Music", emoji: "🎵",
               input: .cd, volumeDB: -35, surroundMode: .music),
        Preset(name: "Game", emoji: "🎮",
               input: .hdmi2, volumeDB: -32, surroundMode: .game),
    ]
}
