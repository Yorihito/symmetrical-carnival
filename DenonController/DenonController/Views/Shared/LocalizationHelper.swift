import Foundation
import SwiftUI
/// SwiftUI の \.locale 環境値を使って正しい .lproj バンドルを取得し、
/// NSLocalizedString で文字列を解決する。
/// navigationTitle は macOS では AppKit 経由のため \.locale を無視するので、
/// String で渡すときにこの関数を使う。
func localizedNavTitle(_ key: String, locale: Locale) -> String {
    // iOS 17+ の Locale 構造に対応
    let identifier = locale.identifier.lowercased()
    let langCode = identifier.hasPrefix("ja") ? "ja" : (identifier.hasPrefix("en") ? "en" : "en")
    
    if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
    return NSLocalizedString(key, comment: "")
}

// MARK: - Mobile Localization Helpers

public func makeLocalizedBundle(for locale: Locale) -> Bundle {
    let identifier = locale.identifier.lowercased()
    let langCode = identifier.hasPrefix("ja") ? "ja" : (identifier.hasPrefix("en") ? "en" : "en")
    
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
