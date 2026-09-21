#!/bin/bash
# スクリーンショットを日英で撮る。
#   dial    … App Store 用。音量ダイアル表示のダッシュボード（既存のストア画像に合わせてダークモード）
#   support … App Review 用。「開発を応援する」画面（投げ銭 3 段）
#
# DEBUG ビルド限定の起動引数を使う（参照: upgraded-guacamole の scripts/capture-screenshots.sh）。
#   -uiDemo        … AVR が無くても接続中の画面を再現する。通信は一切しない
#   -uiDemoSupport … 購入画面を直接開き、StoreKit を使わずに 3 段を並べる
#                    （simctl から起動すると Xcode の StoreKit 設定が効かず、商品を読み込めないため）
#
# 撮影専用のシミュレータ（無ければ作成）で、毎回アプリを入れ直してまっさらな状態から撮る。
# 普段のデバッグ用シミュレータに保存された接続先や設定の影響を受けないようにするため
# （保存済みの接続先があると、LAN 上の実機 AVR に接続してしまう）。
#
# 使い方: scripts/capture-screenshots.sh
# 出力:   build/screenshots/{ja,en}/{dial,support}.png
#
# 撮影後は必ず画像を目で確認すること。起動直後は iOS の通知バナーが写り込むことがある。
set -euo pipefail

cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIM_NAME="${SIM_NAME:-AVR Screenshots}"
DEVICE_TYPE="${DEVICE_TYPE:-iPhone 17 Pro Max}"   # 6.9" / 1320x2868
OUT_DIR="${OUT_DIR:-build/screenshots}"
BUNDLE_ID="cc.nyoyapoya.denoncontroller"
LOCALES=(ja en)
SHOTS=(dial support)

(cd DenonController && xcodegen generate >/dev/null)

UDID=$(xcrun simctl list devices available | grep "    $SIM_NAME (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)
if [ -z "$UDID" ]; then
  echo "== creating simulator '$SIM_NAME' ($DEVICE_TYPE) =="
  UDID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE")
fi

echo "== building for simulator =="
xcodebuild -project DenonController/DenonController.xcodeproj -scheme DenonControllerMobile \
  -configuration Debug -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build -quiet

APP="build/DerivedData/Build/Products/Debug-iphonesimulator/Denon Controller.app"

echo "== booting $SIM_NAME ($UDID) =="
xcrun simctl bootstatus "$UDID" -b >/dev/null
# 撮影用にステータスバーを整える
xcrun simctl status_bar "$UDID" override --time "9:41" \
  --batteryState charged --batteryLevel 100 --wifiMode active --wifiBars 3 \
  --cellularMode notSupported || true

# まっさらな状態から撮る（撮影専用のシミュレータなので、アプリのデータを消してよい）
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

# インストール直後の初回起動は遅く、スプラッシュが写ってしまうので一度起動して温める。
# シミュレータを起動した直後は端末側の処理も重いので、長めに待つ
xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiDemo >/dev/null
sleep 15
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

for locale in "${LOCALES[@]}"; do
  mkdir -p "$OUT_DIR/$locale"
  region=$([ "$locale" = ja ] && echo JP || echo US)
  for shot in "${SHOTS[@]}"; do
    case "$shot" in
      dial)    appearance=dark;  args=(-uiDemo -volumeControlStyle dial) ;;
      support) appearance=light; args=(-uiDemo -uiDemoSupport) ;;
    esac
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    # 外観を切り替えた直後は端末側の再描画でアプリの起動が遅れ、起動画面が写ってしまうので待つ
    xcrun simctl ui "$UDID" appearance "$appearance"
    sleep 4
    xcrun simctl launch "$UDID" "$BUNDLE_ID" "${args[@]}" \
      -AppleLanguages "($locale)" -AppleLocale "${locale}_${region}" >/dev/null
    sleep 10  # 起動画面 → アプリ内スプラッシュ（1.5 秒）→ 表示が落ち着くまで
    xcrun simctl io "$UDID" screenshot "$OUT_DIR/$locale/$shot.png" >/dev/null
    echo "captured $OUT_DIR/$locale/$shot.png"
  done
done

echo "screenshots in $OUT_DIR"
