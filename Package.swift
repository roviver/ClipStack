// swift-tools-version: 6.0
import PackageDescription

// Собираем БЕЗ внешних зависимостей: SQLite берём системный (C API), глобальный хоткей —
// Carbon. Xcode на машине нет, поэтому каждая внешняя зависимость это лишняя точка отказа
// в сборочном скрипте, а обе задачи закрываются парой сотен строк своего кода.
let package = Package(
    name: "clipstack",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "clipstack",
            path: "Sources/clipstack",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
