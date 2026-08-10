#!/usr/bin/env bash
# Собирает .app-бандл из SPM-таргета. Xcode на машине нет, поэтому бандл клеим руками:
# swift build -> Contents/MacOS -> Info.plist -> codesign.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="clipstack"
CONFIG="${1:-release}"
IDENTITY="${CLIPSTACK_SIGN_IDENTITY:-clipstack-dev}"
BUNDLE="$ROOT/build/$APP_NAME.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
[ -x "$BIN" ] || { echo "нет бинаря: $BIN" >&2; exit 1; }

echo "==> сборка бандла"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/"

echo "==> подпись"
# Стабильная идентичность критична: TCC привязывает выданное разрешение Универсального
# доступа к designated requirement. При ad-hoc подписи DR завязан на cdhash бинаря, то есть
# ЛЮБАЯ пересборка сбрасывает разрешение и его приходится выдавать заново.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
	codesign --force --sign "$IDENTITY" "$BUNDLE"
	echo "    подписано '$IDENTITY'"
else
	codesign --force --sign - "$BUNDLE"
	echo "    ВНИМАНИЕ: идентичность '$IDENTITY' не найдена, подписано ad-hoc."
	echo "    Разрешение Универсального доступа будет слетать после каждой пересборки."
	echo "    Лечится: Scripts/make-cert.sh"
fi

codesign --verify --strict "$BUNDLE" && echo "==> готово: $BUNDLE"
codesign -dvv "$BUNDLE" 2>&1 | grep -E "^(Identifier|Authority|Signature)" || true
