// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Releases",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "ReleasesCore", targets: ["ReleasesCore"]),
    .executable(name: "releases", targets: ["ReleasesCLI"]),
    .executable(name: "ReleasesApp", targets: ["ReleasesApp"])
  ],
  targets: [
    .target(name: "ReleasesCore"),
    .executableTarget(
      name: "ReleasesCLI",
      dependencies: ["ReleasesCore"]
    ),
    .executableTarget(
      name: "ReleasesApp",
      dependencies: ["ReleasesCore"]
    ),
    .testTarget(
      name: "ReleasesCoreTests",
      dependencies: ["ReleasesCore"]
    )
  ]
)
