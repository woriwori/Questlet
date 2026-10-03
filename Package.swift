// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Questlet",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Questlet", targets: ["Questlet"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "QuestletCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Questlet", dependencies: ["QuestletCore"], resources: [.process("Resources")]),
        .testTarget(name: "QuestletCoreTests", dependencies: ["QuestletCore"])
    ],
    swiftLanguageModes: [.v5]
)
