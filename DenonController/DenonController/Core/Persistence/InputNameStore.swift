import Foundation
import Observation

/// 入力ソースのカスタム名と表示/非表示を管理する。
/// UserDefaults に保存し、アプリ再起動後も維持される。
@Observable
@MainActor
final class InputNameStore {

    private let namesKey  = "customInputNames"
    private let hiddenKey = "hiddenInputSources"

    /// InputSource.rawValue → カスタム表示名
    private(set) var names: [String: String] = [:]

    /// 非表示にする InputSource.rawValue の集合
    private(set) var hiddenRawValues: Set<String> = []

    init() {
        if let saved = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] {
            names = saved
        }
        if let saved = UserDefaults.standard.array(forKey: hiddenKey) as? [String] {
            hiddenRawValues = Set(saved)
        }
    }

    // MARK: - Names
    //
    // キーは入力 ID（Denon は "HDMI1"、Yamaha は "hdmi1" など）。メーカーごとに ID の書き方が違うので、
    // 同じ辞書に入れても混ざらない（1.1.x までの Denon の保存データもそのまま使える）。

    func customName(forID id: String) -> String? {
        names[id]
    }

    func setName(_ name: String, forID id: String) {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            names.removeValue(forKey: id)
        } else {
            names[id] = name
        }
        UserDefaults.standard.set(names, forKey: namesKey)
    }

    func customName(for source: InputSource) -> String? { customName(forID: source.rawValue) }
    func setName(_ name: String, for source: InputSource) { setName(name, forID: source.rawValue) }

    // MARK: - Visibility

    func isHidden(id: String) -> Bool {
        hiddenRawValues.contains(id)
    }

    func setHidden(_ hidden: Bool, id: String) {
        if hidden {
            hiddenRawValues.insert(id)
        } else {
            hiddenRawValues.remove(id)
        }
        UserDefaults.standard.set(Array(hiddenRawValues), forKey: hiddenKey)
    }

    func isHidden(_ source: InputSource) -> Bool { isHidden(id: source.rawValue) }
    func setHidden(_ hidden: Bool, for source: InputSource) { setHidden(hidden, id: source.rawValue) }

    /// 表示する入力ソースのみ（非表示でないもの）— Denon の固定一覧
    var visibleSources: [InputSource] {
        InputSource.allCases.filter { !isHidden($0) }
    }

    /// 接続中の機器の入力のうち、非表示にしていないもの
    func visible(_ inputs: [ReceiverInput]) -> [ReceiverInput] {
        inputs.filter { !isHidden(id: $0.id) }
    }

    /// すべてのカスタム名・非表示設定を初期値に戻す
    func reset() {
        names = [:]
        hiddenRawValues = []
        UserDefaults.standard.removeObject(forKey: namesKey)
        UserDefaults.standard.removeObject(forKey: hiddenKey)
    }
}
