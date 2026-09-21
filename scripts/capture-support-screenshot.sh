#!/bin/bash
# App Review 用に「開発を応援する」画面（投げ銭 3 段）のスクリーンショットを撮る。
#
# iPhone 17 Pro Max シミュレータ（6.9" / 1320x2868）で、DEBUG ビルド限定の起動引数
# `-uiDemoSupport` を使う。simctl から起動すると Xcode の StoreKit 設定が効かず商品を
# 読み込めないため、このモードでは StoreKit を使わずに 3 段を並べる（日本語は予定価格、
# 英語は Products.storekit の価格）。
# 参照: upgraded-guacamole の scripts/capture-screenshots.sh
#
# 使い方: scripts/capture-support-screenshot.sh
# 出力:   build/screenshots/{ja,en}/support.png
#
# 撮影後は必ず画像を目で確認すること。起動直後は iOS の通知バナーが写り込むことがある。
set -euo pipefail

cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIM_NAME="${SIM_NAME:-iPhone 17 Pro Max}"
OUT_DIR="${OUT_DIR:-build/screenshots}"
BUNDLE_ID="cc.nyoyapoya.denoncontroller"
LOCALES=(ja en)
# 撮影中は自動接続を止める。シミュレータに保存済みの接続先があると、LAN 上の実機 AVR に
# 接続してしまい、接続時のダイアログで購入画面の表示が妨げられるため（設定値を起動時だけ上書き）
NO_CONNECT=(-autoConnect NO)

(cd DenonController && xcodegen generate >/dev/null)

UDID=$(xcrun simctl list devices available | grep "$SIM_NAME (" | head -1 | grep -oE '[0-9A-F-]{36}')
[ -n "$UDID" ] || { echo "simulator '$SIM_NAME' not found" >&2; exit 1; }

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

xcrun simctl install "$UDID" "$APP"

# インストール直後の初回起動は遅く、スプラッシュが写ってしまうので一度起動して温める。
# シミュレータを起動した直後は端末側の処理も重いので、長めに待つ
xcrun simctl launch "$UDID" "$BUNDLE_ID" "${NO_CONNECT[@]}" >/dev/null
sleep 15
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

for locale in "${LOCALES[@]}"; do
  mkdir -p "$OUT_DIR/$locale"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  region=$([ "$locale" = ja ] && echo JP || echo US)
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiDemoSupport "${NO_CONNECT[@]}" \
    -AppleLanguages "($locale)" -AppleLocale "${locale}_${region}" >/dev/null
  sleep 10  # 起動画面 → アプリ内スプラッシュ（1.5 秒）→ シートの表示
  xcrun simctl io "$UDID" screenshot "$OUT_DIR/$locale/support.png" >/dev/null
  echo "captured $OUT_DIR/$locale/support.png"
done

echo "screenshots in $OUT_DIR"
