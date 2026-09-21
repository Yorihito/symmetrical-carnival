import SwiftUI
import StoreKit

/// 開発を応援する（投げ銭）画面。
/// 設定から開くほか、しばらく無事に使っている人には一度だけ案内から開く（`isModal`）。
struct SupportView: View {
    /// シートとして開いたとき true（閉じるボタンを出す）
    var isModal = false

    @Environment(SupportStore.self) private var store
    @Environment(\.localizedBundle) private var bundle
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var showingThanks = false
    @State private var showingFailure = false

    /// スクリーンショット撮影用（DEBUG ビルドで起動引数 `-uiDemoSupport`）。
    /// simctl から起動すると Xcode の StoreKit 設定（Products.storekit）が効かず商品を読み込めないため、
    /// StoreKit を使わずに 3 段を並べる。撮影手順は `scripts/capture-support-screenshot.sh`。
    /// 参照: upgraded-guacamole の `-uiDemo`
    static var isScreenshotDemo: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiDemoSupport")
        #else
        false
        #endif
    }

    var body: some View {
        List {
            headerSection
            tipsSection
            perkSection
        }
        .navigationTitle(localizedNavTitle("開発を応援する", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LS("閉じる", bundle)) { dismiss() }
                }
            }
        }
        .task {
            guard !Self.isScreenshotDemo else { return }
            if store.loadState == .idle || store.loadState == .unavailable {
                await store.loadProducts()
            }
        }
        .alert(Text("ありがとうございます！", bundle: bundle), isPresented: $showingThanks) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("応援していただき、本当にありがとうございます。今後の開発の励みになります。", bundle: bundle)
        }
        .alert(Text("購入を完了できませんでした", bundle: bundle), isPresented: $showingFailure) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("時間をおいてもう一度お試しください。", bundle: bundle)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: store.isSupporter ? "heart.fill" : "heart")
                    .font(.system(size: 44))
                    .foregroundStyle(.pink)
                Text(store.isSupporter ? "サポーターになっていただき、ありがとうございます" : "開発を応援する", bundle: bundle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("AVR Controller はすべての機能を無料で提供しています。応援していただいた分は、新機能の開発や対応機種の検証に使わせていただきます。", bundle: bundle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var tipsSection: some View {
        Section {
            if Self.isScreenshotDemo {
                ForEach(SupportStore.Tier.allCases) { tier in
                    Button { } label: {
                        tipRowLabel(productID: tier.rawValue, price: demoPrice(for: tier), purchasing: false)
                    }
                }
            } else {
                storeRows
            }
        } header: {
            Text("応援の金額を選ぶ", bundle: bundle)
        } footer: {
            Text("何度でも応援できます。応援しても機能は変わらず、すべての機能を引き続き無料でお使いいただけます。", bundle: bundle)
        }
    }

    @ViewBuilder
    private var storeRows: some View {
        switch store.loadState {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("読み込み中…", bundle: bundle)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
        case .unavailable:
            Text("現在、応援を受け付けできません。時間をおいてお試しください。", bundle: bundle)
                .foregroundStyle(.secondary)
            Button(LS("再読み込み", bundle)) {
                Task { await store.loadProducts() }
            }
        case .loaded:
            ForEach(store.products, id: \.id) { product in
                tipRow(product)
            }
        }
    }

    private var perkSection: some View {
        Section {
            Label {
                Text("応援してくださった方のご要望は、優先的に検討します。", bundle: bundle)
            } icon: {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.yellow)
            }
        } header: {
            Text("サポーター特典", bundle: bundle)
        } footer: {
            Text("「ご意見・ご要望を送る」から送ると、サポーターのご要望として届きます。", bundle: bundle)
        }
    }

    private func tipRow(_ product: Product) -> some View {
        Button {
            Task { await buy(product) }
        } label: {
            tipRowLabel(productID: product.id, price: product.displayPrice,
                        purchasing: store.purchasingID == product.id)
        }
        .disabled(store.purchasingID != nil)
    }

    private func tipRowLabel(productID: String, price: String, purchasing: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: productID))
                .foregroundStyle(.pink)
                .frame(width: 28)
            Text(title(for: productID), bundle: bundle)
                .foregroundStyle(.primary)
            Spacer()
            if purchasing {
                ProgressView()
            } else {
                Text(price)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func buy(_ product: Product) async {
        switch await store.purchase(product) {
        case .success:
            showingThanks = true
        case .failed:
            showingFailure = true
        case .pending, .cancelled:
            break
        }
    }

    // MARK: - Tier appearance

    /// 商品名は App Store Connect の表示名に頼らず、アプリ側の言語設定で出す
    private func title(for productID: String) -> LocalizedStringKey {
        switch SupportStore.Tier(rawValue: productID) {
        case .small:  "ちょっと応援"
        case .medium: "しっかり応援"
        case .large:  "たっぷり応援"
        case nil:     "応援する"
        }
    }

    /// 撮影用の表示価格。日本語は App Store Connect で設定する予定の価格、英語は Products.storekit の価格
    private func demoPrice(for tier: SupportStore.Tier) -> String {
        let japanese = locale.identifier.hasPrefix("ja")
        switch tier {
        case .small:  return japanese ? "¥160" : "$0.99"
        case .medium: return japanese ? "¥480" : "$2.99"
        case .large:  return japanese ? "¥980" : "$5.99"
        }
    }

    private func icon(for productID: String) -> String {
        switch SupportStore.Tier(rawValue: productID) {
        case .small:  "cup.and.saucer.fill"
        case .medium: "heart.fill"
        case .large:  "gift.fill"
        case nil:     "heart"
        }
    }
}
