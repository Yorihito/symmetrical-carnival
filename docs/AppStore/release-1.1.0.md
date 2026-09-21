# 1.1.0 審査提出チェックリスト

1.1.0 は、App Store 公開中の 1.0.5（2026-07-06 公開）以降の変更をすべて含む。初めての App 内課金
（投げ銭）と、初めて外部にデータを送る機能（ご意見・ご要望の送信）を含むため、通常の更新より確認項目が多い。

作成: 2026-09-21。完了したらチェックを入れて更新する。

## 0. 事前準備（コードと Worker）

- [x] PR #13（「ご意見・ご要望を送る」への名称変更）と PR #16（投げ銭）を main にマージ
- [x] Worker を再デプロイ（`supporter` ラベル対応。`cd server && npx wrangler deploy`）
- [ ] main を取り込んでプロジェクトを再生成する

  ```bash
  git checkout main && git pull
  cd DenonController && xcodegen generate
  ```

## 1. 契約の確認

- [ ] App Store Connect の「ビジネス」（契約／税金／口座情報）で、**有料 App 契約が「有効」**であること。
  無効だと IAP を作っても商品が読み込まれない

## 2. IAP を 3 つ作成

アプリ（AVR Controller for D）の左メニュー「収益化」→「App 内課金」→「＋」。**種類は「消耗型」**。

| 項目 | small | medium | large |
|---|---|---|---|
| 参照名（社内用） | Tip Small | Tip Medium | Tip Large |
| 製品 ID | `cc.nyoyapoya.denoncontroller.tip.small` | `cc.nyoyapoya.denoncontroller.tip.medium` | `cc.nyoyapoya.denoncontroller.tip.large` |
| 価格（例） | 160 円前後 | 480 円前後 | 980 円前後 |
| 表示名（日本語） | ちょっと応援 | しっかり応援 | たっぷり応援 |
| 表示名（英語） | Small Tip | Medium Tip | Large Tip |

- [ ] **製品 ID** を正確に入力する。一度作ると変更も再利用もできない。アプリ側の定義
  （`SupportStore.Tier`）と 1 文字でも違うと商品が表示されない
- [ ] **価格スケジュール**: 日本を基準に選ぶ（他の国は自動）。アプリは App Store Connect の価格を
  そのまま表示するので、後から変えてもよい
- [ ] **ローカリゼーション**: 日本語と英語（米国）。表示名は購入時の Apple の確認画面にも出るので、
  アプリ内の名前と揃える。説明（45 文字以内）は次の文面でよい
  - 日本語: `開発を応援する投げ銭です。機能は変わりません`
  - 英語: `A tip to support the developer.`
- [ ] **審査に関する情報**: 購入画面のスクリーンショットを 1 枚（3 つとも同じでよい）。撮影済みの
  `marketing/iap-review/en/support.png`（英語）か `marketing/iap-review/ja/support.png`（日本語）を使う。
  審査メモは「購入しても機能は解放されない投げ銭です」
  - 撮り直すときは `scripts/capture-screenshots.sh`。DEBUG ビルド限定の起動引数
    `-uiDemoSupport` で購入画面を直接開き、StoreKit を使わずに 3 段を並べる（日本語は予定価格の
    ¥160 / ¥480 / ¥980、英語は `Products.storekit` の価格）。価格を変えたら `SupportView.demoPrice` も直す
- [ ] 3 つともステータスが**「送信準備完了」**になったことを確認

## 3. TestFlight で本番の商品を試す（推奨）

Xcode から直接実行するとローカルのテスト用商品が使われる。App Store Connect の本物の商品が
読み込めるかは TestFlight で確認する。

- [ ] Xcode で接続先を「Any iOS Device」にして Product → Archive（Team はいつもどおり選択）。
  ビルド番号は git のコミット数から自動で付く
- [ ] Organizer → Distribute App → App Store Connect でアップロード
- [ ] TestFlight（内部テスト）で実機にインストールし、確認する
  - [ ] 設定 → 開発を応援する で、3 つの商品が**円の価格で**表示される
  - [ ] 購入でき、お礼が出る（TestFlight では**実際には課金されない**）
  - [ ] 「レビューを書く」で App Store のレビュー画面が開く
  - [ ] 応援後に「ご意見・ご要望を送る」から送ると、Issue に `supporter` ラベルが付く
    （**公開の Issue が作られる**ので、確認後に閉じる）

商品が出ない場合は、IAP が「送信準備完了」か、有料 App 契約が有効かを確認する。

## 4. 1.1.0 のバージョンを作って提出

App Store タブの「＋」→ iOS のバージョン **1.1.0** を作成する。

### 4-1. このバージョンの新機能

- [ ] 日本語

  ```
  ・音量ダイアル：アプリアイコンのようなダイアルを回して、音量を細かく調整できるようになりました（設定でスライダーと切り替えられます）
  ・ダッシュボードの並び順を、設定から入れ替えられるようになりました
  ・AVR の IP アドレスが変わったときの自動再接続を改善しました（アプリに戻ったときや操作中にも探し直します）
  ・「ご意見・ご要望を送る」から、不具合の報告や機能のリクエストを送れるようになりました
  ・アプリ内ヘルプとプライバシーポリシーへの導線を追加しました
  ・「開発を応援する」を追加しました。すべての機能は引き続き無料でお使いいただけます
  ```

- [ ] 英語

  ```
  • Volume dial: turn a dial inspired by the app icon for precise volume control (switch back to the slider in Settings)
  • Rearrange the dashboard sections from Settings
  • Improved automatic reconnection when your receiver's IP address changes (now also when you return to the app and during use)
  • Send bug reports and feature requests from "Send Feedback"
  • Added links to in-app help and the privacy policy
  • Added "Support Development" — every feature stays free
  ```

### 4-2. スクリーンショット

- [ ] （任意・推奨）音量ダイアルは見た目で伝わる変更なので、1 枚追加する。撮影済みの画像を使う。
  既存のストア画像と同じサイズ枠に並べること（日本語は iPhone 17 Pro の 6.3 インチ、英語は
  iPhone 17 Pro Max の 6.9 インチで撮られている）
  - 日本語: `marketing/appstore-screenshots/ja/dial-6.3.png`（6.9 インチ枠用は `dial-6.9.png`）
  - 英語: `marketing/appstore-screenshots/en/dial-6.9.png`（6.3 インチ枠用は `dial-6.3.png`）
  - 既存の画像に合わせて、ダークモードの素の画面。AVR に接続した状態は DEBUG ビルド限定の起動引数
    `-uiDemo` で再現している（実機には接続しない）。撮り直すときは `scripts/capture-screenshots.sh`、
    6.3 インチは `SIM_NAME="AVR Screenshots 6.3" DEVICE_TYPE="iPhone 17 Pro" scripts/capture-screenshots.sh`

### 4-3. ビルド

- [ ] 手順 3 でアップロードしたビルドを選ぶ

### 4-4. App 内課金とサブスクリプション（最重要）

- [ ] バージョンのページのこの欄で、**3 つの IAP を追加する**。最初の IAP はアプリのバージョンと
  一緒でないと審査に出せず、追加し忘れると IAP が審査に回らない

### 4-5. App のプライバシー（要判断）

1.1.0 は、このアプリで初めて外部にデータを送るバージョン（ご意見・ご要望の送信）。Apple の
「フォームから任意で送るデータは申告不要」という例外には「送信フォームにユーザー名やアカウント名が
表示されていること」という条件があり、匿名のフォームでは当てはまらない可能性が高い。次の内容で
申告するのが安全。

| データの種類 | 用途 | ユーザーとの紐づけ | トラッキング |
|---|---|---|---|
| ユーザーコンテンツ → カスタマーサポート（入力した本文） | App の機能 | なし | なし |
| 診断 → その他の診断データ（バージョン、OS、機種、ログ） | App の機能 | なし | なし |
| 購入 → 購入履歴（supporter の目印。厳密には該当） | App の機能 | なし | なし |

- [ ] 申告内容を決めて App Store Connect で公開する
- [ ] アプリ内のプライバシーマニフェスト（`DenonController/DenonController/Core/PrivacyInfo.xcprivacy`）の
  `NSPrivacyCollectedDataTypes` を申告内容に合わせる（現在は「収集データなし」の空配列）。
  **マニフェストの変更はビルドに入るので、手順 3 のアーカイブより前に行う**

### 4-6. App Review に関する情報

- [ ] [`ReviewNotes.md`](ReviewNotes.md) の内容をメモ欄に貼る（IAP の説明は追記済み）
- [ ] **実機デモ動画**（限定公開）のリンクを貼る。`ReviewNotes.md` では TODO のまま。同じ構造の
  TV REMOTE for B が 2026-07-02 に「外部ハードウェアの動作確認ができない」（Guideline 2.1）で
  リジェクトされているため、実機の iPhone と AVR が同じ画面に映る動画を用意する

### 4-7. URL

- [ ] サポート URL: `https://yorihito.github.io/symmetrical-carnival/`
- [ ] プライバシーポリシー URL: `https://yorihito.github.io/symmetrical-carnival/privacy.html`

（どちらも 2026-09-21 に表示を確認済み）

### 4-8. 提出

- [ ] 「審査用に追加」→「審査へ提出」
- [ ] リリース方法は「**手動でリリース**」にして、公開のタイミングを自分で決める

## 5. 審査中と公開後

- アプリと IAP は一緒に審査される。IAP に不備があると、アプリごと差し戻される
- 一度だけの支援のお願いは、接続成功 10 回以上かつ使い始めて 14 日以上の人に出るので、公開直後は
  誰にも表示されない（想定どおり）
- `supporter` ラベルの付いた Issue が優先対応の対象。ラベルは公開エンドポイント経由の自己申告なので、
  購入の証明ではなくトリアージの目安として扱う
- [ ] 公開後、この文書のチェックを埋め、`docs/playbook-alignment.md` の残タスク（IAP 登録）を完了にする
