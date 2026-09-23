# 1.1.0 再提出の手順（Guideline 5.2.1 / 4.1(a) 対応）

2026-09-21 に 1.1.0 (167) が次の理由で却下された。

- **5.2.1**: メーカーの許可なく、そのメーカーのハードウェアを操作するアプリとして宣伝している
- **4.1(a)**: メタデータにメーカーを連想させる表記がある（旧名 *AVR Controller for D*）

対応方針と新しい文面は [Metadata_iOS.md](Metadata_iOS.md) を参照。
手順は Apple のヘルプ（2026-09-23 時点）で確認済み:
[Manage a submission with unresolved issues](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/manage-a-submission-with-unresolved-issues)、
[Reply to App Review messages](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages)。

メニュー名は App Store Connect の英語表示のまま書く。上から順に 1 回ずつ操作する。

## 1. 新しいビルドをアップロードする

アプリ内の文言からブランド名を外したので、新しいビルドが必要（メタデータだけの却下なら同じビルドで再提出できるが、今回は違う）。

1. Xcode の **Window > Organizer** でアーカイブを選び、**Distribute App > App Store Connect > Upload**
2. App Store Connect の **TestFlight** タブに新しいビルドが出て、処理（Processing）が終わるまで待つ

## 2. アプリ名とサブタイトルを変える（App Information）

1. **Apps** > このアプリ > サイドバーの **General > App Information**
2. 右上の言語メニューで **Japanese** を選び、**Name** と **Subtitle** を Metadata_iOS.md の日本語の値にする
3. 言語を **English (U.S.)** に切り替え、同じく英語の値にする
4. **Save**

> 「AVR Controller」単体は他のアプリが使っているので、コロン以降まで含めて入れる。
> 名前が使えないと言われたら、そこで止めて相談する。

## 3. 審査中の提出物を開いて、バージョンを編集する

1. **Apps** > このアプリ。ページ上部の **unresolved issues** のリンク（または **View App Review Issues & Messages**）
2. **In Progress** の提出物の **Resolve**
3. 却下された **App Version**（1.1.0）の **Edit**。バージョンのページが開く
4. 言語ごと（**Japanese** と **English (U.S.)**）に次を差し替える:
   - **Promotional Text**、**Description**、**Keywords**: Metadata_iOS.md の値を全文貼り直す
   - **iPhone / iPad** のスクリーンショット: 画像を全部消して、`marketing/appstore-screenshots/en/` の新しい画像を入れ直す
     （6.9"、6.3"（使っていれば）、13" iPad。日本語のダイアル画像は `marketing/appstore-screenshots/ja/`）
5. **Build**: 167 を外して、1. でアップロードした新しいビルドを選ぶ
6. **App Review Information > Notes**: 手元の `docs/AppStore/ReviewNotes.txt`（デモ動画の URL 入り）を全文貼り直す
7. **Save**、続けて **Add for Review**

> 提出物の中の項目を編集できるのは、再提出までに 1 回だけ。上の変更はまとめて行う。
> IAP（投げ銭 3 種）が却下されていなければ触らない。

## 4. App Review に返信する

再提出すると返信できなくなるので、先に返信する。

1. **Resolve** の画面で **Reply to App Review**
2. 下の文面を **Reply** 欄に貼る（`<BUILD>` を新しいビルド番号に置き換える）
3. **Reply**

```
Hello,

Thank you for the review. We do not have authorization from the receiver manufacturer, so we have removed its name from the app and the metadata:

- The app name has changed from "AVR Controller for D" to "AVR Controller: Volume Dial" (Japanese: "AVR Controller – AVアンプ リモコン").
- The manufacturer's name has been removed from the subtitle, keywords, promotional text, screenshots, and all in-app text (new build 1.1.0 (<BUILD>)).
- The description now presents the app as a controller for network-enabled AV receivers. It keeps one sentence naming the model the app was tested on, together with a notice that the app is unofficial and not affiliated with any manufacturer, so customers can check compatibility. If this sentence is still not acceptable, please let us know and we will remove it.

The app contains no third-party logos, artwork, or other content.

Thank you.
```

## 5. 再提出する

1. 提出物の詳細画面で **Resubmit to App Review**
2. ステータスが **Waiting for Review** になれば完了

## 再び却下された場合

説明文の【対応機種】を、Metadata_iOS.md の「予備」の文面に差し替えて（機種名なし）、3〜5 をやり直す。
ビルドは同じものでよい。
