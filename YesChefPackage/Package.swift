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
    // GRDB is declared even though nothing here writes `import GRDB`: `import
    // SQLiteData` re-exports `Database`, `DatabaseWriter`, `Configuration` and
    // `DatabaseMigrator`, and `bootstrapDatabase` / every repository call uses
    // them. `@_exported` is a *compile-time* re-export, not a
    // `-reexport_framework`, so the symbols are visible to the type checker and
    // absent from the linker's search path the moment Xcode builds these
    // products as dynamic frameworks — which it does for all of them as soon as
    // a test bundle enters the build graph. `swift build`/`swift test` link
    // everything statically and never notice. Floor matches sqlite-data's own;
    // SwiftPM unifies the graph to one resolution. See CloudSyncKit's manifest
    // for the same note — that package had the same latent defect.
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
    .package(path: "../../../jon-platform/packages/LLMClientKit"),
    .package(path: "../../../jon-platform/packages/CloudSyncKit"),
  ],
  targets: [
    .target(
      name: "YesChefCore",
      dependencies: [
        .product(name: "CloudSyncKit", package: "CloudSyncKit"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "GRDB", package: "GRDB.swift"),
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
