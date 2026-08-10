#!/usr/bin/env bash
# Рисует иконку приложения и собирает .icns. Отдельным скриптом, а не на каждой сборке:
# иконка меняется раз в жизни проекта, а iconutil заметно медленнее самой сборки.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/draw.swift" <<'SWIFT'
import AppKit

// Рисуем в 1024 и даём iconutil самому сделать остальные размеры.
let side = 1024.0
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

// Подложка со скруглением macOS-стиля.
let inset = side * 0.09
let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let plate = NSBezierPath(roundedRect: rect, xRadius: side * 0.19, yRadius: side * 0.19)
NSGradient(
    colors: [NSColor(srgbRed: 0.30, green: 0.55, blue: 0.98, alpha: 1),
             NSColor(srgbRed: 0.17, green: 0.33, blue: 0.85, alpha: 1)]
)?.draw(in: plate, angle: -90)

// Стопка «карточек» — намёк на историю копий, из которой берут нужную.
let cardWidth = side * 0.44
let cardHeight = side * 0.30
let centerX = side / 2
for (index, offset) in [side * 0.10, 0.0, -side * 0.10].enumerated() {
    let alpha = [0.45, 0.70, 1.0][index]
    let shrink = [side * 0.06, side * 0.03, 0.0][index]
    let card = NSRect(
        x: centerX - (cardWidth - shrink) / 2,
        y: side * 0.36 + offset,
        width: cardWidth - shrink,
        height: cardHeight
    )
    NSColor(white: 1, alpha: alpha).setFill()
    NSBezierPath(roundedRect: card, xRadius: side * 0.035, yRadius: side * 0.035).fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

echo "==> рисую иконку"
swiftc -O -o "$WORK/draw" "$WORK/draw.swift"
"$WORK/draw" "$WORK/icon.png"

echo "==> собираю .icns"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
	sips -z $size $size "$WORK/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
	sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"

echo "готово: $ROOT/Resources/AppIcon.icns"
