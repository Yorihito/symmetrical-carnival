import Foundation

// メーカーをまたいで使う型。メーカーごとの違いは ReceiverCapabilities に集め、画面はそれを見て出し分ける。
// 設計: docs/yamaha-support-design.md 3.3

enum ReceiverBrand: String, Codable, Sendable, CaseIterable {
    case denon, marantz, yamaha

    var displayName: String {
        switch self {
        case .denon:   "Denon"
        case .marantz: "Marantz"
        case .yamaha:  "Yamaha"
        }
    }

    /// Denon と Marantz は同じ通信方式（/goform と Telnet）
    var usesDenonProtocol: Bool { self != .yamaha }

    init(brandName: String) {
        switch brandName.lowercased() {
        case "marantz": self = .marantz
        case "yamaha":  self = .yamaha
        default:        self = .denon
        }
    }
}

/// 入力ソース。id はメーカーの入力 ID（Denon は "HDMI1"、Yamaha は "hdmi1" など）で、そのまま保存にも使う
struct ReceiverInput: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let systemImage: String

    /// カスタム名ストアを参照した表示名。未設定なら displayName を使用。
    @MainActor
    func name(using store: InputNameStore) -> String {
        store.customName(forID: id) ?? displayName
    }
}

/// サウンドモード（Denon のサラウンドモード、Yamaha のサウンドプログラム）
struct SoundModeOption: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let systemImage: String
}

/// 接続中の機器でできること。接続時に決まり、画面の出し分けに使う
struct ReceiverCapabilities: Sendable, Equatable {
    var brand: ReceiverBrand
    var inputs: [ReceiverInput]
    var soundModes: [SoundModeOption]
    var volumeRangeDB: ClosedRange<Double>
    /// Denon 本体と同じ「Vol 47.5」（dB + 80）の副表示を出すか
    var showsNativeVolumeScale: Bool
    var hasZone2: Bool
    var hasZone3: Bool
    /// チューナー入力の ID（なければ nil）
    var tunerInputID: String?
    var tunerBands: [TunerBand]
    /// プリセットを 1 件ずつ選んで読み取る方式か（Denon）。false なら一括で取れる（Yamaha）
    var tunerPresetsNeedScan: Bool
    var tunerPresetCount: Int
    /// リモコン画面（OSD）の操作ができるか
    var supportsRemote: Bool

    static let denon = ReceiverCapabilities(
        brand: .denon,
        inputs: InputSource.allCases.map(\.receiverInput),
        soundModes: SurroundMode.selectableModes.map(\.option),
        volumeRangeDB: -80...18,
        showsNativeVolumeScale: true,
        hasZone2: true,
        hasZone3: false,
        tunerInputID: InputSource.tuner.rawValue,
        tunerBands: [.fm, .am],
        tunerPresetsNeedScan: true,
        tunerPresetCount: 56,
        supportsRemote: true
    )

    /// 入力 ID の表示用情報。一覧にない ID も、読める形で返す
    func input(for id: String) -> ReceiverInput {
        if let found = inputs.first(where: { $0.id == id }) { return found }
        switch brand {
        case .yamaha: return YamahaCatalog.input(id: id, customName: nil)
        default:
            return InputSource(rawValue: id)?.receiverInput
                ?? ReceiverInput(id: id, displayName: id, systemImage: "square.grid.2x2")
        }
    }

    /// サウンドモード ID の表示用情報。選択肢にないモード（AVR 側で切り替えたものなど）も表示できるようにする
    func soundMode(for id: String) -> SoundModeOption {
        if let found = soundModes.first(where: { $0.id == id }) { return found }
        switch brand {
        case .yamaha: return YamahaCatalog.soundProgram(id: id, customName: nil)
        default:
            return SurroundMode(rawCode: id)?.option
                ?? SoundModeOption(id: id, displayName: id, systemImage: "waveform")
        }
    }

    func isTunerInput(_ id: String) -> Bool {
        guard let tunerInputID else { return false }
        return id == tunerInputID
    }
}

extension InputSource {
    var receiverInput: ReceiverInput {
        ReceiverInput(id: rawValue, displayName: displayName, systemImage: systemImage)
    }
}

extension SurroundMode {
    var option: SoundModeOption {
        SoundModeOption(id: rawValue, displayName: displayName, systemImage: systemImage)
    }
}
