#!/usr/bin/env bash
# Собирает и ставит clipstack в /Applications, перезапуская работающий экземпляр.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="clipstack"
TARGET_DIR="${CLIPSTACK_INSTALL_DIR:-/Applications}"
TARGET="$TARGET_DIR/$APP_NAME.app"

"$ROOT/Scripts/build-app.sh" release

if [ ! -w "$TARGET_DIR" ]; then
	echo "!! Нет прав на запись в $TARGET_DIR."
	echo "   Поставь в домашнюю папку:  CLIPSTACK_INSTALL_DIR=\"\$HOME/Applications\" $0"
	exit 1
fi

echo "==> останавливаю запущенный экземпляр"
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
sleep 1

echo "==> ставлю в $TARGET"
rm -rf "$TARGET"
cp -R "$ROOT/build/$APP_NAME.app" "$TARGET"

echo "==> запускаю"
open "$TARGET"

cat <<EOF

Готово: $TARGET

Если приложение переехало из другой папки, macOS может попросить заново выдать
Универсальный доступ — история при этом не теряется, она лежит отдельно:
~/Library/Application Support/clipstack/
EOF
