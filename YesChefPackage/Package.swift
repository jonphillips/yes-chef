// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "YesChefPackage",
  platforms: [
    .iOS(.v27),
    .macOS(.v26),
  ],
  products: [
    .library(name: "YesChefCore", targets: ["YesChefCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.7.0"),
    .package(path: "../../../jon-platform/packages/LLMClientKit"),
    .package(path: "../../../jon-platform/packages/CloudSyncKit"),
  ],
  targets: [
    .target(
      name: "YesChefCore",
      dependencies: [
        .product(name: "CloudSyncKit", package: "CloudSyncKit"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "LLMClientKit", package: "LLMClientKit"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "SwiftSoup", package: "SwiftSoup"),
      ]
    ),
    .testTarget(
      name: "YesChefCoreTests",
      dependencies: [
        "YesChefCore",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      exclude: ["Fixtures"]
    ),
  ]
)
