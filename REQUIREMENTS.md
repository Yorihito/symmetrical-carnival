# Denon AVR Controller — 要件定義書

**対象機種:** Denon AVR-X3800H  
**プラットフォーム:** macOS 14 (Sonoma) 以上  
**アーキテクチャ:** SwiftUI + Swift Concurrency  
**最終更新:** 2026-04-12

---

## 1. プロダクトビジョン

Denon AVR-X3800H をネットワーク経由でフル制御できる、洗練されたネイティブ macOS アプリ。  
物理リモコン不要で、Mac から直感的に AVR を操作できる体験を提供する。

---

## 2. 技術概要

### 通信プロトコル

| プロトコル | 用途 | ポート |
|------------|------|--------|
| Telnet (TCP) | コマンド送受信（リアルタイム制御） | 23 |
| HTTP REST API | 状態取得・一部制御 | 80 |
| HEOS Protocol (TCP) | ストリーミング情報・HEOS制御 | 1255 |
| mDNS / Bonjour | 自動デバイス検出 | — |

### アーキテクチャ方針

- **MVVM + Combine / AsyncStream** によるリアクティブ設計
- **SwiftUI** によるモダン UI（AppKit 混在最小化）
- **Menu Bar App + メインウィンドウ** のデュアルモード
- ダーク／ライトモード完全対応
- **SF Symbols 5** をアイコンとして活用

---

## 3. 機能一覧

### 3.1 接続管理

| ID | 機能 | 優先度 |
|----|------|--------|
| CON-01 | mDNS / Bonjour による AVR 自動検出 | Must |
| CON-02 | IPアドレス手動入力による接続 | Must |
| CON-03 | 接続状態のリアルタイム表示（接続中 / 切断 / 再接続中） | Must |
| CON-04 | 切断時の自動再接続（指数バックオフ） | Must |
| CON-05 | 複数AVRの登録・切替（プロファイル機能） | Should |
| CON-06 | 接続履歴の保存 | Should |

---

### 3.2 電源制御

| ID | 機能 | コマンド例 | 優先度 |
|----|------|------------|--------|
| PWR-01 | メインゾーン 電源 ON/OFF | `PWON` / `PWSTANDBY` | Must |
| PWR-02 | Zone 2 電源 ON/OFF | `Z2ON` / `Z2OFF` | Should |
| PWR-03 | Zone 3 電源 ON/OFF | `Z3ON` / `Z3OFF` | Should |
| PWR-04 | 全ゾーン電源 OFF（スタンバイ） | `PWSTANDBY` | Should |
| PWR-05 | ECO モード切替（OFF / AUTO / ON） | `ECOAUTO` | Could |

---

### 3.3 音量制御

| ID | 機能 | コマンド例 | 優先度 |
|----|------|------------|--------|
| VOL-01 | マスターボリューム ステップアップ / ダウン | `MVUP` / `MVDOWN` | Must |
| VOL-02 | マスターボリューム 絶対値指定（0–98 dB） | `MV50` | Must |
| VOL-03 | ミュート ON/OFF | `MUON` / `MUOFF` | Must |
| VOL-04 | 現在の音量を dB 表示（例：−30.0 dB） | — | Must |
| VOL-05 | Zone 2 音量制御 | `Z2UP` / `Z2DOWN` / `Z2MU` | Should |
| VOL-06 | Zone 3 音量制御 | `Z3UP` / `Z3DOWN` / `Z3MU` | Should |
| VOL-07 | スクロールホイール / キーボード矢印キーによる音量調整 | — | Must |

---

### 3.4 入力ソース切替

| ID | 機能 | 対応入力 | 優先度 |
|----|------|----------|--------|
| INP-01 | メインゾーン 入力切替 | 下記18入力 | Must |
| INP-02 | Zone 2 入力切替 | 下記入力（Zone対応分） | Should |
| INP-03 | Zone 3 入力切替 | 下記入力（Zone対応分） | Should |
| INP-04 | 入力名のカスタマイズ（表示名変更） | — | Could |

**対応入力ソース一覧（AVR-X3800H）**

| 表示名 | コマンド | 表示名 | コマンド |
|--------|----------|--------|----------|
| PHONO | `SIPHONO` | HDMI1 | `SIHDMI1` |
| CD | `SICD` | HDMI2 | `SIHDMI2` |
| TUNER | `SITUNER` | HDMI3 | `SIHDMI3` |
| DVD | `SIDVD` | HDMI4 | `SIHDMI4` |
| Blu-ray | `SIBD` | HDMI5 | `SIHDMI5` |
| TV Audio | `SITV` | HDMI6 | `SIHDMI6` |
| CBL/SAT | `SISAT/CBL` | HDMI7 | `SIHDMI7` |
| Media Player | `SIMPLAY` | HDMI8 | `SIHDMI8` |
| GAME | `SIGAME` | Bluetooth | `SIBT` |
| AUX1 | `SIAUX1` | Network | `SINET` |

---

### 3.5 サラウンドモード

| ID | 機能 | 優先度 |
|----|------|--------|
| SUR-01 | サラウンドモード切替 | Must |
| SUR-02 | 現在のサラウンドモード表示 | Must |
| SUR-03 | PURE DIRECT / DIRECT モード | Must |
| SUR-04 | STEREO モード | Must |

**主要サラウンドモード**

| モード | コマンド |
|--------|----------|
| Movie | `MSMOVIE` |
| Music | `MSMUSIC` |
| Game | `MSGAME` |
| Pure Direct | `MSPURE DIRECT` |
| Direct | `MSDIRECT` |
| Stereo | `MSSTEREO` |
| Auto | `MSAUTO` |
| Dolby Surround | `MSDOLBY SURROUND` |
| DTS Neural:X | `MSDTS NEURAL:X` |
| Auro-3D | `MSAURO3D` |
| IMAX DTS | `MSIMAX DTS` |

---

### 3.6 オーディオ設定

| ID | 機能 | コマンド例 | 優先度 |
|----|------|------------|--------|
| AUD-01 | トーンコントロール（Bass / Treble） | `PSBAS UP` / `PSTRE DN` | Should |
| AUD-02 | ダイナミックEQ ON/OFF | `PSDYNEQ ON` | Should |
| AUD-03 | ダイナミックボリューム設定 | `PSDYNVOL MED` | Should |
| AUD-04 | Audyssey MultEQ XT32 切替 | `PSROOM SIZE` | Could |
| AUD-05 | ダイアログエンハンサー | `PSDIL` | Could |
| AUD-06 | ラウドネス管理 | `PSloudness` | Could |

---

### 3.7 チューナー制御

| ID | 機能 | コマンド例 | 優先度 |
|----|------|------------|--------|
| TUN-01 | FM / AM バンド切替 | `TMANFM` / `TMANAM` | Should |
| TUN-02 | プリセット局の呼び出し（1–56） | `TPAN01` | Should |
| TUN-03 | 周波数のステップアップ / ダウン | `TFANUP` / `TFANDN` | Should |
| TUN-04 | 現在の周波数・プリセット番号表示 | — | Should |

---

### 3.8 HEOS / ストリーミング情報

| ID | 機能 | 優先度 |
|----|------|--------|
| HEO-01 | 再生中トラック情報（曲名 / アーティスト / アルバム）表示 | Should |
| HEO-02 | アルバムアートワーク表示 | Should |
| HEO-03 | 再生 / 一時停止 / 前 / 次 | Should |
| HEO-04 | HEOS お気に入り呼び出し | Could |
| HEO-05 | インターネットラジオ（TuneIn / iHeartRadio）操作 | Could |

---

### 3.9 OSD / メニュー操作

| ID | 機能 | コマンド例 | 優先度 |
|----|------|------------|--------|
| OSD-01 | メニュー表示 ON/OFF | `MNMEN ON` | Could |
| OSD-02 | カーソル操作（上 / 下 / 左 / 右） | `MNCUP` / `MNCDN` | Could |
| OSD-03 | 決定 / 戻る | `MNENT` / `MNRTN` | Could |

---

### 3.10 プリセット / ショートカット

| ID | 機能 | 優先度 |
|----|------|--------|
| PRE-01 | 現在の設定（入力 + 音量 + サラウンド）をプリセット保存（最大10件） | Should |
| PRE-02 | プリセットにカスタム名・絵文字アイコンを設定 | Should |
| PRE-03 | ワンタップでプリセット呼び出し | Should |

---

### 3.11 キーボードショートカット

| ショートカット | 操作 |
|---------------|------|
| `⌘+↑` / `⌘+↓` | 音量 +/− |
| `⌘+M` | ミュート |
| `⌘+0` | スタンバイ |
| `⌘+1〜9` | プリセット呼び出し |
| `⌘+,` | 設定画面 |
| `Space` | HEOS 再生 / 一時停止 |

---

## 4. UI / UX 設計

### 4.1 ウィンドウ構成

```
┌─────────────────────────────────────────────────┐
│  [接続状態] AVR-X3800H  ●オンライン          [⚙] │
├─────────────┬───────────────────────────────────┤
│             │  🎵 現在の入力: HDMI2              │
│  サイドバー  │  🔊 −30.0 dB  [━━━━●────]  🔇    │
│  ─────────  │  🎬 Dolby Atmos                   │
│  📺 入力    ├───────────────────────────────────┤
│  🔊 音量    │  [タブパネル]                      │
│  🎬 サラウ  │  入力 | サラウンド | チューナー    │
│  📻 チュー  │  HEOS | ゾーン | プリセット       │
│  🎵 HEOS   │                                   │
│  🌐 ゾーン  │  [各タブのコンテンツ]              │
│  ⭐ プリセ  │                                   │
└─────────────┴───────────────────────────────────┘
```

### 4.2 メニューバーアイコン

- 常駐メニューバーアイコン（スピーカーアイコン）
- クリックでポップオーバー表示（音量 + ミュート + 入力切替 + 電源）
- メインウィンドウを開くボタン
- アプリ非表示時も制御可能

### 4.3 デザイン指針

- **カラースキーム:** macOS のシステムアクセントカラーに準拠
- **素材:** `NSVisualEffectView` によるすりガラス背景
- **アニメーション:** ボリュームスライダーの滑らかなトランジション
- **フォント:** SF Pro Rounded をアクセントに使用
- **アイコン:** SF Symbols 5 を全面採用

---

## 5. 非機能要件

| カテゴリ | 要件 |
|----------|------|
| パフォーマンス | コマンド応答 < 200ms（LAN内） |
| 再接続 | 切断後 5秒以内に自動再接続試行 |
| 状態同期 | AVR からのプッシュ通知を受信してUI即時反映 |
| オフライン | AVR 未接続時はUIをグレーアウトし操作を無効化 |
| セキュリティ | 認証情報は Keychain に保存 |
| サンドボックス | Mac App Store 配布を考慮したサンドボックス対応 |
| 最小OS | macOS 14 Sonoma 以上 |
| アーキテクチャ | Apple Silicon / Intel ユニバーサルバイナリ |

---

## 6. 開発ロードマップ

### Phase 1 — MVP（コア制御）
- [ ] TCP 接続 + Telnet コマンドエンジン
- [ ] mDNS 自動検出
- [ ] 電源 / 音量 / ミュート / 入力切替
- [ ] メインウィンドウ基本UI
- [ ] メニューバーアイコン + ポップオーバー

### Phase 2 — 拡張制御
- [ ] サラウンドモード選択
- [ ] Zone 2/3 制御
- [ ] チューナー制御
- [ ] プリセット機能
- [ ] キーボードショートカット

### Phase 3 — HEOS / 仕上げ
- [ ] HEOS プロトコル統合（再生情報・アートワーク）
- [ ] ストリーミング再生制御
- [ ] オーディオ詳細設定パネル
- [ ] OSD メニュー操作
- [ ] 設定エクスポート / インポート

---

## 7. ファイル構成（予定）

```
DenonController/
├── App/
│   ├── DenonControllerApp.swift      # エントリポイント
│   └── AppDelegate.swift             # メニューバー管理
├── Core/
│   ├── Network/
│   │   ├── TelnetClient.swift        # TCP接続・コマンド送受信
│   │   ├── HEOSClient.swift          # HEOSプロトコル
│   │   └── MDNSDiscovery.swift       # Bonjour自動検出
│   ├── Commands/
│   │   ├── PowerCommands.swift
│   │   ├── VolumeCommands.swift
│   │   ├── InputCommands.swift
│   │   ├── SurroundCommands.swift
│   │   └── TunerCommands.swift
│   └── Models/
│       ├── AVRState.swift            # AVRの現在状態モデル
│       ├── Preset.swift
│       └── AVRProfile.swift
├── ViewModels/
│   ├── MainViewModel.swift
│   ├── VolumeViewModel.swift
│   └── HEOSViewModel.swift
├── Views/
│   ├── MainWindow/
│   │   ├── ContentView.swift
│   │   ├── SidebarView.swift
│   │   └── Tabs/
│   │       ├── InputTabView.swift
│   │       ├── SurroundTabView.swift
│   │       ├── TunerTabView.swift
│   │       ├── HEOSTabView.swift
│   │       ├── ZoneTabView.swift
│   │       └── PresetTabView.swift
│   ├── MenuBar/
│   │   ├── MenuBarController.swift
│   │   └── MenuBarPopoverView.swift
│   └── Settings/
│       └── SettingsView.swift
└── Resources/
    └── Assets.xcassets
```

---

## 8. 参考ドキュメント

- [Denon AVR Control Protocol (RS-232C / IP)](https://assets.denon.com/documentmaster/us/denon_avr_protocol_v1.pdf)
- [HEOS CLI Protocol Specification](https://rn.dmglobal.com/euheos/HEOS_CLI_ProtocolSpecification.pdf)
- [Apple Human Interface Guidelines — macOS](https://developer.apple.com/design/human-interface-guidelines/macos)
- [SF Symbols 5](https://developer.apple.com/sf-symbols/)
