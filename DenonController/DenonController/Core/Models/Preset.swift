import Foundation

struct Preset: Identifiable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var emoji: String        // e.g. "🎬", "🎵"
    var input: InputSource
    var volume: Double       // Denon units
    var surroundMode: SurroundMode

    static let examples: [Preset] = [
        Preset(name: "映画", emoji: "🎬",
               input: .hdmi1, volume: 55, surroundMode: .movie),
        Preset(name: "音楽", emoji: "🎵",
               input: .cd, volume: 50, surroundMode: .music),
        Preset(name: "ゲーム", emoji: "🎮",
               input: .hdmi2, volume: 48, surroundMode: .game),
    ]
}
