// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "YesChefMCP",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "yeschef-mcp", targets: ["YesChefMCP"]),
  ],
  dependencies: [
    .package(path: "../YesChefPackage"),
    .package(path: "../../../jon-platform/packages/MCPServerKit"),
    .package(path: "../../../jon-platform/packages/LLMHandoffKit"),
  ],
  targets: [
    .target(
      name: "YesChefMCPServer",
      dependencies: [
        .product(name: "YesChefCore", package: "YesChefPackage"),
        .product(name: "MCPServerKit", package: "MCPServerKit"),
        .product(name: "LLMHandoffKit", package: "LLMHandoffKit"),
      ]
    ),
    .executableTarget(name: "YesChefMCP", dependencies: ["YesChefMCPServer", .product(name: "MCPServerKit", package: "MCPServerKit")]),
    .testTarget(
      name: "YesChefMCPTests",
      dependencies: ["YesChefMCPServer", .product(name: "MCPServerKit", package: "MCPServerKit")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
