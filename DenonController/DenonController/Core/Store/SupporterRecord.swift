import Foundation
import Security

/// 開発を応援（投げ銭）してくれた記録。
///
/// 投げ銭は消耗型 IAP なので、購入の履歴は StoreKit に残らない（iOS 17 では完了済みの消耗型は
/// `Transaction.all` に含まれない）。そこで「支援した」という事実だけをキーチェーンに保存する。
/// `kSecAttrSynchronizable` を付けるので、iCloud キーチェーンが有効なら再インストール後や
/// 同じ Apple ID の別の端末でも残る。
///
/// 保存するのは初めて支援した日時だけで、金額や回数は保存しない。
enum SupporterRecord {
    private static let service = "cc.nyoyapoya.denoncontroller.supporter"
    private static let account = "supporter"

    /// 支援したことがあるか
    static var isSupporter: Bool { firstSupportDate != nil }

    /// 初めて支援した日時
    static var firstSupportDate: Date? {
        var query = lookupQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let seconds = Double(String(decoding: data, as: UTF8.self))
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// 支援を記録する。既に記録があれば初回の日時をそのまま残す。
    static func recordSupport(at date: Date = Date()) {
        guard !isSupporter else { return }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            // iCloud キーチェーンで同期させるため ThisDeviceOnly は使わない
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(String(date.timeIntervalSince1970).utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    #if DEBUG
    /// テスト用: 支援の記録を消す
    static func debugClear() {
        SecItemDelete(lookupQuery as CFDictionary)
    }
    #endif

    /// 同期される項目とされない項目の両方を対象にする検索条件
    private static var lookupQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }
}
