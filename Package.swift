// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusLens",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FocusLens", targets: ["FocusLens"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.8.0")
    ],
    targets: [
        .executableTarget(
            name: "FocusLens",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "FocusLens",
            exclude: [
                "Resources/Info.plist"
            ]
        )
    ]
)
