import Foundation
import Observation

/// プリセットを UserDefaults に永続化する。
@Observable
@MainActor
final class PresetStore {

    private static let key = "com.ytada.DenonController.presets"

    var presets: [Preset] = []

    init() {
        load()
    }

    func save(_ preset: Preset) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
        } else {
            presets.append(preset)
        }
        persist()
    }

    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Private

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([Preset].self, from: data)
        else {
            presets = Preset.examples
            return
        }
        presets = decoded
    }

    /// すべてのプリセットを削除して初期値に戻す
    func reset() {
        presets = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
