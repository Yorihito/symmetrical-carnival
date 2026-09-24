import Foundation

/// 入力・音量・サウンドモードの組み合わせ（アプリ内のプリセット）。
///
/// `input` と `surroundMode` はメーカーの ID 文字列（Denon は "BD" や "MOVIE"、Yamaha は "hdmi1" や "straight"）。
/// 1.1.x までは Denon の enum を Codable で保存していたが、その保存形式も rawValue の文字列なので、そのまま読める。
/// `brand` が nil のものは 1.1.x までに作った Denon / Marantz のプリセット。
struct Preset: Identifiable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var emoji: String
    var input: String
    var volumeDB: Double       // 実際の dB 値
    var surroundMode: String
    var brand: ReceiverBrand?

    /// このプリセットを、接続中の機器で使えるか（メーカーの通信方式が同じか）
    func isUsable(with brand: ReceiverBrand) -> Bool {
        (self.brand ?? .denon).usesDenonProtocol == brand.usesDenonProtocol
    }

    static let examples: [Preset] = [
        Preset(name: "Movie", emoji: "🎬",
               input: InputSource.hdmi1.rawValue, volumeDB: -30, surroundMode: SurroundMode.movie.rawValue),
        Preset(name: "Music", emoji: "🎵",
               input: InputSource.cd.rawValue, volumeDB: -35, surroundMode: SurroundMode.music.rawValue),
        Preset(name: "Game", emoji: "🎮",
               input: InputSource.hdmi2.rawValue, volumeDB: -32, surroundMode: SurroundMode.game.rawValue),
    ]
}
