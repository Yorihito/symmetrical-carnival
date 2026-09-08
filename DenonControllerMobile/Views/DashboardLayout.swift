import SwiftUI

/// ダッシュボード上で並べ替えできるセクション。
/// 接続状態ピルと電源ヘッダーは常に最上部に固定するため、ここには含めない。
enum DashboardSection: String, CaseIterable, Identifiable {
    case volume
    case dial
    case input
    case surround

    var id: String { rawValue }

    /// ローカライズキー（開発言語が日本語のため、キー自体が日本語）
    var titleKey: LocalizedStringKey {
        switch self {
        case .volume:   "音量"
        case .dial:     "音量ダイアル"
        case .input:    "入力ソース"
        case .surround: "サラウンドモード"
        }
    }
}

/// ダッシュボードの並び順の保存と正規化。
/// スライダー表示とダイアル表示で構成セクションが異なるため、順序はスタイルごとに保持する。
enum DashboardLayout {
    static let sliderKey = "dashboardOrderSlider"
    static let dialKey   = "dashboardOrderDial"

    static let sliderDefault: [DashboardSection] = [.volume, .input, .surround]
    static let dialDefault:   [DashboardSection] = [.input, .surround, .volume, .dial]

    static var sliderDefaultRaw: String { encode(sliderDefault) }
    static var dialDefaultRaw:   String { encode(dialDefault) }

    /// そのスタイルで表示され得るセクション。ダイアルはダイアル表示のときだけ存在する。
    static func availableSections(isDial: Bool) -> [DashboardSection] {
        isDial ? [.volume, .dial, .input, .surround] : [.volume, .input, .surround]
    }

    static func defaultOrder(isDial: Bool) -> [DashboardSection] {
        isDial ? dialDefault : sliderDefault
    }

    static func storageKey(isDial: Bool) -> String {
        isDial ? dialKey : sliderKey
    }

    /// 保存文字列を、そのスタイルで有効なセクション列に正規化する。
    /// 不正値・重複は捨て、欠けているセクションは既定順で末尾に補う。
    static func decode(_ raw: String, isDial: Bool) -> [DashboardSection] {
        let allowed = availableSections(isDial: isDial)
        var result: [DashboardSection] = []
        for token in raw.split(separator: ",") {
            guard let section = DashboardSection(rawValue: String(token)),
                  allowed.contains(section),
                  !result.contains(section)
            else { continue }
            result.append(section)
        }
        for section in defaultOrder(isDial: isDial) where !result.contains(section) {
            result.append(section)
        }
        return result
    }

    static func encode(_ sections: [DashboardSection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }

    /// 設定リセット時に既定の並び順へ戻す。
    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: sliderKey)
        UserDefaults.standard.removeObject(forKey: dialKey)
    }
}

/// 設定画面から開く並べ替えリスト。
/// 現在選択中の音量コントロールに対応する並び順を編集する。
struct DashboardOrderView: View {
    @AppStorage("volumeControlStyle") private var volumeControlStyle = "slider"
    @AppStorage(DashboardLayout.sliderKey) private var sliderOrderRaw = DashboardLayout.sliderDefaultRaw
    @AppStorage(DashboardLayout.dialKey)   private var dialOrderRaw   = DashboardLayout.dialDefaultRaw

    @Environment(\.locale) private var locale
    @Environment(\.localizedBundle) private var bundle

    private var isDial: Bool { volumeControlStyle == "dial" }

    private var sections: [DashboardSection] {
        DashboardLayout.decode(isDial ? dialOrderRaw : sliderOrderRaw, isDial: isDial)
    }

    var body: some View {
        List {
            Section {
                ForEach(sections) { section in
                    Text(section.titleKey, bundle: bundle)
                }
                .onMove(perform: move)
            } header: {
                Text("表示順", bundle: bundle)
            } footer: {
                Text(isDial
                     ? "ダイアル表示のときの並び順です。ドラッグして入れ替えられます。"
                     : "スライダー表示のときの並び順です。ドラッグして入れ替えられます。",
                     bundle: bundle)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(localizedNavTitle("ダッシュボードの並び順", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    resetOrder()
                } label: {
                    Text("並び順をリセット", bundle: bundle)
                }
                .disabled(sections == DashboardLayout.defaultOrder(isDial: isDial))
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var current = sections
        current.move(fromOffsets: source, toOffset: destination)
        store(current)
    }

    private func resetOrder() {
        store(DashboardLayout.defaultOrder(isDial: isDial))
    }

    private func store(_ sections: [DashboardSection]) {
        let encoded = DashboardLayout.encode(sections)
        if isDial {
            dialOrderRaw = encoded
        } else {
            sliderOrderRaw = encoded
        }
    }
}
