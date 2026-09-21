import Foundation
import Observation
import StoreKit

/// 開発支援（投げ銭）の IAP。消耗型を 3 段用意し、何度でも購入できる。
///
/// 購入しても機能は何も変わらない（すべての機能は無料のまま）。支援した事実だけを
/// `SupporterRecord` に残し、「ご意見・ご要望を送る」で優先的に検討する目印に使う。
///
/// StoreKit 2 の扱いは upgraded-guacamole の `StoreManager` を踏襲している。
/// 向こうは非消耗型の権利判定（`Transaction.currentEntitlements`）だが、こちらは消耗型なので
/// 購入完了時に記録するだけで、復元（`AppStore.sync`）は持たない。
@Observable
@MainActor
final class SupportStore {
    /// App Store Connect に登録する商品 ID。価格は App Store Connect 側で決める。
    enum Tier: String, CaseIterable, Identifiable {
        case small  = "cc.nyoyapoya.denoncontroller.tip.small"
        case medium = "cc.nyoyapoya.denoncontroller.tip.medium"
        case large  = "cc.nyoyapoya.denoncontroller.tip.large"

        var id: String { rawValue }
    }

    enum LoadState: Equatable {
        case idle, loading, loaded, unavailable
    }

    enum PurchaseOutcome {
        case success, pending, cancelled, failed
    }

    /// 価格の安い順
    private(set) var products: [Product] = []
    private(set) var loadState: LoadState = .idle
    /// 購入処理中の商品 ID（多重購入の防止と、行ごとのインジケーター表示用）
    private(set) var purchasingID: String?
    private(set) var isSupporter = SupporterRecord.isSupporter

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// 起動時に 1 回呼ぶ。取引の監視を始めてから商品を読み込む。
    /// 二重に呼ばれても監視を重ねない（参照: upgraded-guacamole review P3-1）。
    func start() async {
        guard updatesTask == nil else { return }
        updatesTask = listenForTransactions()
        await loadProducts()
    }

    func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let fetched = try await Product.products(for: Tier.allCases.map(\.rawValue))
            products = fetched.sorted { $0.price < $1.price }
            // App Store Connect に商品が未登録の間は空が返る
            loadState = products.isEmpty ? .unavailable : .loaded
        } catch {
            products = []
            loadState = .unavailable
        }
    }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        guard purchasingID == nil else { return .failed }
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return .failed }
                recordSupport()
                await transaction.finish()
                return .success
            case .pending:
                // 保護者の承認待ち（ファミリー共有の「承認と購入のリクエスト」）など。
                // 承認されると Transaction.updates に届き、そこで記録する。
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    // MARK: - Private

    private func recordSupport() {
        SupporterRecord.recordSupport()
        isSupporter = true
    }

    /// 承認待ちだった購入や、途中で中断された購入の完了はここに届く。
    /// 消耗型は finish しないと次回起動時にも届き続けるので、必ず finish する。
    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                if Tier(rawValue: transaction.productID) != nil, transaction.revocationDate == nil {
                    self?.recordSupport()
                }
                await transaction.finish()
            }
        }
    }
}
