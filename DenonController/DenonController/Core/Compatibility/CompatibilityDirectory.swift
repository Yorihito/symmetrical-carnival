import Foundation

/// ヘルプサイトの対応機種の一覧（`compatibility.json`、GitHub Actions が動作報告から作る）を読み、
/// 機種ごとの状態を返す。取れなくてもアプリの動作には影響しない（「分からない」として扱う）。
@MainActor
final class CompatibilityDirectory {
    static let shared = CompatibilityDirectory()

    static let url = URL(string: "https://yorihito.github.io/symmetrical-carnival/compatibility.json")!
    private static let cacheKey = "compatibilityDirectoryCache"
    private static let fetchedAtKey = "compatibilityDirectoryFetchedAt"
    /// 取り直す間隔（一覧は 1 日 1 回程度しか変わらない）
    private static let refreshInterval: TimeInterval = 12 * 3600

    private struct Entry: Decodable {
        var brand: String
        var model: String
        var status: String
        var reports: Int?
        var overall: [String: Int]?
    }
    private struct Document: Decodable {
        var models: [Entry]
    }

    private var entries: [Entry] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let doc = try? JSONDecoder().decode(Document.self, from: data) {
            entries = doc.models
        }
    }

    /// 開発者が実機で確かめた機種（help/data/verified.json と同じ）。一覧を取れない環境
    /// （インターネットにつながらない Wi-Fi など）でも、これらの機種には動作報告をお願いしない
    private static let builtInVerified: [(ReceiverBrand, String)] = [(.denon, "avr-x3800h"), (.yamaha, "rx-v581")]

    /// 機種の状態。「問題なく使える」の報告が 3 件以上あれば、報告のお願いはもう要らないものとして扱う
    func status(brand: ReceiverBrand, model: String) -> CompatibilityModelStatus {
        let key = Self.normalized(model)
        if Self.builtInVerified.contains(where: { $0.0 == brand && $0.1 == key }) { return .verified }
        guard !key.isEmpty,
              let entry = entries.first(where: { $0.brand == brand.rawValue && Self.normalized($0.model) == key })
        else { return .unknown }
        let status = CompatibilityModelStatus(rawValue: entry.status) ?? .unknown
        if status == .reported, (entry.overall?["works"] ?? 0) < 3 { return .partial }
        return status
    }

    /// 必要なら一覧を取り直す（インターネットに出るので URLSession を使う。LAN の機器とは関係ない）
    func refreshIfNeeded() async {
        let last = UserDefaults.standard.object(forKey: Self.fetchedAtKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > Self.refreshInterval else { return }
        var request = URLRequest(url: Self.url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let doc = try? JSONDecoder().decode(Document.self, from: data) else { return }
        entries = doc.models
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        UserDefaults.standard.set(Date(), forKey: Self.fetchedAtKey)
    }

    private static func normalized(_ model: String) -> String {
        model.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
