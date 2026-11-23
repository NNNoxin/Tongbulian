// swift-tools-version:5.9
import PackageDescription

// The menu-bar app imports SwiftUI and is added only when this package is
// resolved on macOS. Linux builds the diagnostic core, the dry-run CLI, and tests.
var products: [Product] = [
    .library(name: "TongDuanCore", targets: ["TongDuanCore"]),
    .executable(name: "tongbulian", targets: ["tongbulian"]),
]

var targets: [Target] = [
    .target(name: "TongDuanCore"),
    .executableTarget(
        name: "tongbulian",
        dependencies: ["TongDuanCore"],
        path: "Sources/TongbulianCLI"
    ),
    .testTarget(
        name: "TongDuanCoreTests",
        dependencies: ["TongDuanCore"]
    ),
]

#if os(macOS)
products.append(.executable(name: "TongbulianApp", targets: ["TongbulianApp"]))
targets.append(
    .executableTarget(
        name: "TongbulianApp",
        dependencies: ["TongDuanCore"],
        path: "Sources/TongbulianApp",
        linkerSettings: [
            .linkedFramework("CoreWLAN"),
            .linkedFramework("CoreLocation"),
            .linkedFramework("AppKit"),
        ]
    )
)
#endif

let package = Package(
    name: "Tongbulian",
    platforms: [
        .macOS(.v13),
    ],
    products: products,
    targets: targets
)
