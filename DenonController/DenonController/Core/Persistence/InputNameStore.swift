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

    func customName(for source: InputSource) -> String? {
        names[source.rawValue]
    }

    func setName(_ name: String, for source: InputSource) {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            names.removeValue(forKey: source.rawValue)
        } else {
            names[source.rawValue] = name
        }
        UserDefaults.standard.set(names, forKey: namesKey)
    }

    // MARK: - Visibility

    func isHidden(_ source: InputSource) -> Bool {
        hiddenRawValues.contains(source.rawValue)
    }

    func setHidden(_ hidden: Bool, for source: InputSource) {
        if hidden {
            hiddenRawValues.insert(source.rawValue)
        } else {
            hiddenRawValues.remove(source.rawValue)
        }
        UserDefaults.standard.set(Array(hiddenRawValues), forKey: hiddenKey)
    }

    /// 表示する入力ソースのみ（非表示でないもの）
    var visibleSources: [InputSource] {
        InputSource.allCases.filter { !isHidden($0) }
    }
}
