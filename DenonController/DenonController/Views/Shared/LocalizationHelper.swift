import Foundation
import SwiftUI
/// SwiftUI の \.locale 環境値を使って正しい .lproj バンドルを取得し、
/// NSLocalizedString で文字列を解決する。
/// navigationTitle は macOS では AppKit 経由のため \.locale を無視するので、
/// String で渡すときにこの関数を使う。
func localizedNavTitle(_ key: String, locale: Locale) -> String {
    let langCode = locale.language.languageCode?.identifier ?? "en"
    if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
    // 開発言語（Japanese）はキーがそのまま表示されるのでフォールバック不要
    return NSLocalizedString(key, bundle: Bundle.main, comment: "")
}

// MARK: - Mobile Localization Helpers

public func makeLocalizedBundle(for locale: Locale) -> Bundle {
    let langCode = locale.language.languageCode?.identifier ?? "en"
    if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle
    }
    return Bundle.main
}

public struct LocalizedBundleKey: EnvironmentKey {
    public static let defaultValue: Bundle = .main
}

public extension EnvironmentValues {
    var localizedBundle: Bundle {
        get { self[LocalizedBundleKey.self] }
        set { self[LocalizedBundleKey.self] = newValue }
    }
}

public func LS(_ key: String, _ bundle: Bundle) -> String {
    NSLocalizedString(key, bundle: bundle, comment: "")
}
