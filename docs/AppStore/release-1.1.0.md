# 1.1.0 審査提出チェックリスト

> **結果**: 2026-09-21 に提出 → Guideline 5.2.1 / 4.1(a)（メーカー名）で却下 → 名前を「AVR Controller: Volume Dial」に変えて
> ビルド 175 で再提出（[resubmit-1.1.0.md](resubmit-1.1.0.md)）→ **2026-09-24 に IAP 3 種とともに承認**。自動リリース。

1.1.0 は、App Store 公開中の 1.0.5（2026-07-06 公開）以降の変更をすべて含む。初めての App 内課金
（投げ銭）と、初めて外部にデータを送る機能（ご意見・ご要望の送信）を含むため、通常の更新より確認項目が多い。

作成: 2026-09-21。完了したらチェックを入れて更新する。

## 0. 事前準備（コードと Worker）

- [x] PR #13（「ご意見・ご要望を送る」への名称変更）と PR #16（投げ銭）を main にマージ
- [x] Worker を再デプロイ（`supporter` ラベル対応。`cd server && npx wrangler deploy`）
- [x] main を取り込んでプロジェクトを再生成する

  ```bash
  git checkout main && git pull
  cd DenonController && xcodegen generate
  ```

App Store Connect は英語表示の前提で、メニューやボタンの名前は画面どおり英語で書く
（画面の更新で多少変わることがある）。

## 1. 契約の確認

- [x] トップページの **Business** →「Agreements」で、**Paid Apps** の契約が **Active** であること。
  有効でないと IAP を作っても商品が読み込まれない

## 2. IAP を 3 つ作成

アプリ（AVR Controller for D）の左メニュー **Monetization** → **In-App Purchases** → **＋**。
**Type** は **Consumable**、**Reference Name** と **Product ID** を入れて **Create**。

| 項目 | small | medium | large |
|---|---|---|---|
| Reference Name（社内用） | Tip Small | Tip Medium | Tip Large |
| Product ID | `cc.nyoyapoya.denoncontroller.tip.small` | `cc.nyoyapoya.denoncontroller.tip.medium` | `cc.nyoyapoya.denoncontroller.tip.large` |
| Display Name（Japanese） | ちょっと応援 | しっかり応援 | たっぷり応援 |
| Display Name（English (U.S.)） | Small Tip | Medium Tip | Large Tip |

作成後の画面で、次の欄を埋めて右上の **Save** を押す。右上の **Add for Review** は、バージョンの
準備がすべて整ってから 4-8 で押す（最初の消耗型 IAP はアプリのバージョンと一緒に提出する必要があり、
その提出をこのボタンから作るため）。

- [x] **Product ID** を正確に入力する。一度作ると変更も再利用もできない。アプリ側の定義
  （`SupportStore.Tier`）と 1 文字でも違うと商品が表示されない
- [x] **Availability** → **Set Up Availability** → すべての国と地域
- [x] **Price Schedule** → **Add Pricing** → **Base Country or Region** は **United States (USD)**
  （ダウンロードの半分が米国のため）。他の国の価格は自動で計算され、為替などに応じて Apple が調整する。
  アプリは App Store Connect の価格をそのまま表示するので、後から変えてもよい
- [x] **App Store Localization** → **＋** → ダイアログで言語（Japanese と English (U.S.)）ごとに
  **Display Name** と **Description**（45 文字以内）を入れる。表示名は購入時の Apple の確認画面にも
  出るので、アプリ内の名前と揃える。Description は次の文面でよい
  - Japanese: `開発を応援する投げ銭です。機能は変わりません`
  - English (U.S.): `A tip to support the developer.`
- [x] **Review Information** → **Screenshot** に購入画面を 1 枚（3 つとも同じでよい）。
  `marketing/iap-review/en/support.png`（英語、ダークモード）を使う。**Review Notes** は次の文面でよい

  ```
  This is a tip to support the developer. It does not unlock any features or content; all features remain free. It is available from Settings > Support Development, which can be opened without connecting to an AV receiver.
  ```

  - 撮り直すときは `scripts/capture-screenshots.sh`。DEBUG ビルド限定の起動引数
    `-uiDemoSupport` で購入画面を直接開き、StoreKit を使わずに 3 段を並べる（日本語は予定価格の
    ¥160 / ¥480 / ¥980、英語は `Products.storekit` の価格）。価格を変えたら `SupportView.demoPrice` も直す
- [x] 一覧（**In-App Purchases** → **Drafts**）で 3 つとも Status が **Prepare for Submission** であること。
  これは「作成済みで、まだ提出に入れていない」状態で、項目が埋まってもこの表示のまま。
  **Add for Review** で **Ready for Review**、提出すると **Waiting for Review** に変わる
  （https://developer.apple.com/help/app-store-connect/reference/in-app-purchase-statuses ）

## 3. TestFlight で本番の商品を試す（推奨）

Xcode から直接実行するとローカルのテスト用商品が使われる。App Store Connect の本物の商品が
読み込めるかは TestFlight で確認する。

- [x] Xcode で実行先を **Any iOS Device (arm64)** にして **Product** → **Archive**
  （Team はいつもどおり選択）。ビルド番号は git のコミット数から自動で付く
- [x] Organizer → **Distribute App** → **App Store Connect** → **Upload**
- [x] App Store Connect の **TestFlight** タブ → **Internal Testing** で実機にインストールし、確認する
  - [x] 設定 → 開発を応援する で、3 つの商品が small → medium → large の順に、端末のストアの通貨で表示される
  - [x] 購入でき、お礼が出る（TestFlight では**実際には課金されない**）
  - [x] 「レビューを書く」で App Store のレビュー画面が開く
  - [x] 応援後に「ご意見・ご要望を送る」から送ると、Issue に `supporter` ラベルが付く
    （**公開の Issue が作られる**ので、確認後に閉じる）

商品が出ない、または価格の変更が反映されない場合: App Store Connect で保存してから TestFlight に
届くまで数分〜1 時間ほどかかることがある。アプリは起動時に一度だけ商品を読み込むので、
App スイッチャーから完全に終了して開き直す。

## 4. 1.1.0 のバージョンを作って提出

**Distribution** タブの左メニュー **iOS App** → **1.1.0**（作成済み）を開く。説明文や画像は言語ごとの
設定なので、ページ右上の言語メニュー（例: **English (U.S.)**）で切り替えて入力する。

### 4-1. 新機能の説明（What's New in This Version）

- [x] 日本語

  ```
  ・音量ダイアル：アプリアイコンのようなダイアルを回して、音量を細かく調整できるようになりました（設定でスライダーと切り替えられます）
  ・ダッシュボードの並び順を、設定から入れ替えられるようになりました
  ・AVR の IP アドレスが変わったときの自動再接続を改善しました（アプリに戻ったときや操作中にも探し直します）
  ・「ご意見・ご要望を送る」から、不具合の報告や機能のリクエストを送れるようになりました
  ・アプリ内ヘルプとプライバシーポリシーへの導線を追加しました
  ・「開発を応援する」を追加しました。すべての機能は引き続き無料でお使いいただけます
  ```

- [x] 英語

  ```
  • Volume dial: turn a dial inspired by the app icon for precise volume control (switch back to the slider in Settings)
  • Rearrange the dashboard sections from Settings
  • Improved automatic reconnection when your receiver's IP address changes (now also when you return to the app and during use)
  • Send bug reports and feature requests from "Send Feedback"
  • Added links to in-app help and the privacy policy
  • Added "Support Development" — every feature stays free
  ```

### 4-2. スクリーンショット

既存のストア画像はライトとダーク、画面の種類もサイズごとにばらばらだったので、**英語版をすべて
ダークモードで撮り直した**（2026-09-21）。

**Previews and Screenshots** → **View All Sizes in Media Manager** を開き、サイズごとに **Delete All** で
既存の画像を消してから、**Choose File** でファイル名の番号順にアップロードする。

- [x] **iPhone 6.9" Display**: `marketing/appstore-screenshots/en/iphone-6.9/` の 7 枚
- [x] **iPhone 6.5" Display**: **Using 6.9" Display** のままでよい
- [x] **iPhone 6.3" Display**: `marketing/appstore-screenshots/en/iphone-6.3/` の 7 枚
- [x] **iPad 13" Display**: `marketing/appstore-screenshots/en/ipad-13/` の 5 枚

| 番号 | 画面 | iPhone | iPad |
|---|---|---|---|
| 01 | ダッシュボード（音量ダイアル） | ○ | ○ |
| 02 | ダッシュボード（スライダー） | ○ | ○ |
| 03 | 入力ソース | ○ | （ダッシュボードに含まれる） |
| 04 | チューナー | ○ | ○ |
| 05 | リモコン | ○ | ○ |
| 06 | 設定 | ○ | ○ |
| 07 | 接続設定（AVR の自動検出） | ○ | ― |

（iPad は入力ソースと接続設定が無いため、ファイル番号は 01〜05 に詰めてある）

- 日本語のローカリゼーションに独自のスクリーンショットが残っていると、日本のストアではそちらが
  表示される。英語版に揃えるなら、右上の言語メニューで **Japanese** に切り替え、Media Manager で
  日本語側の画像を削除する（画像の無いローカリゼーションは主言語の画像を使う）
- AVR に接続した状態は DEBUG ビルド限定の起動引数 `-uiDemo` で再現している（実機には接続しない）。
  撮り直すときは `LOCALES=en scripts/capture-screenshots.sh`（端末を絞るなら `DEVICES=iphone69` など）

### 4-3. ビルド

- [x] **Build** 欄の **Add Build**（＋）→ 手順 3 でアップロードしたビルドを選んで **Done**

### 4-4. App 内課金（最重要）

バージョンのページには IAP を追加する欄は無い。IAP のページの **Add for Review** から提出（submission）を
作り、そこに 1.1.0 を含める。バージョン側の入力（4-1〜4-7）がすべて終わってから、4-8 でまとめて行う。

### 4-5. App のプライバシー（App Privacy）（申告する）

1.1.0 は、このアプリで初めて外部にデータを送るバージョン（ご意見・ご要望の送信）。送った内容は
公開の GitHub Issue として残るので、Apple の定義する「収集」（リアルタイムの処理に必要な期間を
超えてアクセスできる形で端末の外に送ること）に当たる。

Apple には申告を省略できる例外（Optional Disclosure）があるが、条件の 1 つが「**送信フォームに
ユーザー名またはアカウント名が目立つように表示されていること**」で、匿名のこのフォームは
当てはまらない（2026-09-21 に https://developer.apple.com/app-store/app-privacy-details/ で確認）。
そのため次の内容で申告する。

| データの種類 | 用途 | ユーザーとの紐づけ | トラッキング |
|---|---|---|---|
| ユーザーコンテンツ → カスタマーサポート（入力した本文） | App の機能 | なし | なし |
| 診断 → その他の診断データ（バージョン、OS、機種、ログ） | App の機能 | なし | なし |
| 購入 → 購入履歴（投げ銭をしたかどうか。supporter の目印） | App の機能 | なし | なし |

- [x] アプリ内のプライバシーマニフェスト（`DenonController/DenonController/Core/PrivacyInfo.xcprivacy`）の
  `NSPrivacyCollectedDataTypes` を上の表に合わせた。**ビルドに含まれるので、この変更の入った main から
  アーカイブする**
- [x] App Store Connect で申告して公開する
  1. 左メニュー **App Privacy**（**Trust & Safety** の下）→ **Get Started**（または **Edit**）
  2. データを収集しているかに **Yes, we collect data from this app**
  3. 次の 3 つにチェックして **Save**
     - **User Content** → **Customer Support**
     - **Diagnostics** → **Other Diagnostic Data**
     - **Purchases** → **Purchase History**
  4. それぞれの **Set Up** で、用途は **App Functionality**、身元との紐づけ（linked to the user's identity）は
     **No**、トラッキング（tracking purposes）は **No** にして **Save**
  5. **Publish**。App Privacy はバージョンではなくアプリ単位の設定で、公開した時点でストアの表示に
     反映される（1.1.0 の公開前に 1.0.5 のページにも出るが、多めの申告なので問題ない）

### 4-6. App Review Information

- [x] バージョンのページ下部の **App Review Information** → **Notes** に
  [`ReviewNotes.txt`](ReviewNotes.txt) の内容をそのまま貼る（英語のプレーンテキスト。IAP の説明と、AVR が無くても
  設定画面を開ける場所の説明を含む）。**Sign-in required** はオフのまま
- [x] **実機デモ動画**は過去の提出で提出済み（審査通過）だが、**1.1.0 では Notes も Attachment も空だった**
  （前のバージョンから引き継がれない）。Notes の `[PASTE THE DEMO VIDEO LINK HERE]` を実際のリンクに
  差し替える。ファイルで出す場合は **Attachment** の **Choose File (Optional)** で添付し、Notes の
  `Demo video` の 2 行は `A demo video is attached.` に書き換える

### 4-7. URL

- [x] **Support URL**（バージョンのページ、言語ごと）: `https://yorihito.github.io/symmetrical-carnival/`
- [x] **Privacy Policy URL**（左メニュー **App Privacy** のページ）: `https://yorihito.github.io/symmetrical-carnival/privacy.html`

（どちらも 2026-09-21 に表示を確認済み）

### 4-8. 提出（IAP と 1.1.0 をまとめて）

- [x] **App Store Version Release** で **Automatically release this version** を選ぶ（審査を通ったらすぐ公開。
  累計 1,200 ダウンロードほどの規模なので、手動リリースや Phased Release は使わないと決めた）
- [x] 1.1.0 のページ右上の **Save** で、ここまでの入力を保存する
- [x] 左メニュー **Monetization** → **In-App Purchases** → **Tip Small** → 右上の **Add for Review**。
  **Draft Submission** が作られる。この時点では「Unable to Submit for Review（Your first consumable in-app
  purchase must be submitted with a new app version.）」と出るが、1.1.0 がまだ入っていないだけなので正常。
  右上の **✕** で閉じる（Draft Submission は残る）
- [x] **Tip Medium**、**Tip Large** も **Add for Review** を押し、同じ Draft Submission に追加する
- [x] **Distribution** → **iOS App** → **1.1.0** の**右上の Add for Review** で、1.1.0 を同じ Draft Submission に
  追加する（IAP の画面ではバージョンを選べない）。入力漏れがあるとここで指摘されるので直す
- [x] Draft Submission に 1.1.0 と IAP 3 つが並び、警告が消えたら **Submit for Review**。
  Draft Submission を後から開くときは、左メニュー **General** → **App Review**
- [x] 送信後、IAP の Status が **Waiting for Review** になっていることを確認

（手順は https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase ）

## 5. 審査中と公開後

- アプリと IAP は一緒に審査される。IAP に不備があると、アプリごと差し戻される
- 一度だけの支援のお願いは、接続成功 10 回以上かつ使い始めて 14 日以上の人に出るので、公開直後は
  誰にも表示されない（想定どおり）
- `supporter` ラベルの付いた Issue が優先対応の対象。ラベルは公開エンドポイント経由の自己申告なので、
  購入の証明ではなくトリアージの目安として扱う
- [x] 公開後、この文書のチェックを埋め、`docs/playbook-alignment.md` の残タスク（IAP 登録）を完了にする
