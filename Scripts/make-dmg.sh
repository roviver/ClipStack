#!/usr/bin/env bash
# Собирает clipstack.dmg — образ с приложением и ярлыком /Applications рядом,
# чтобы установка была обычным перетаскиванием.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="clipstack"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Resources/Info.plist")"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"

"$ROOT/Scripts/build-app.sh" release

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "==> готовлю содержимое образа"
cp -R "$ROOT/build/$APP_NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Короткая памятка внутри образа: приложение подписано самоподписанным сертификатом,
# поэтому у чужого пользователя Gatekeeper поднимет тревогу.
cat >"$STAGING/ПРОЧТИ МЕНЯ.txt" <<'EOF'
clipstack — менеджер буфера обмена для macOS

Установка: перетащи clipstack.app в папку Applications.

Первый запуск: macOS скажет, что разработчик не проверен — приложение подписано
самоподписанным сертификатом, без платного Apple Developer Program. Открой его
правым кликом → «Открыть», и подтверди один раз.

Чтобы работала вставка в активное окно, выдай доступ:
Системные настройки → Конфиденциальность и безопасность → Универсальный доступ.

Показать историю: ⇧⌘V
EOF

echo "==> собираю образ"
rm -f "$DMG"
hdiutil create \
	-volname "$APP_NAME $VERSION" \
	-srcfolder "$STAGING" \
	-ov -format UDZO \
	"$DMG" >/dev/null

echo "готово: $DMG"
ls -lh "$DMG" | awk '{print "  размер:", $5}'
shasum -a 256 "$DMG" | awk '{print "  sha256:", $1}'
