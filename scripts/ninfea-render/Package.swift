// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "NinfeaRender",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/cinemore/rife-metal.git",
             revision: "1fef4869a44fca32848102b9f6a774a20eb50db6")
  ],
  targets: [
    .executableTarget(name: "NinfeaRender",
      dependencies: [.product(name: "RifeMetal", package: "rife-metal")],
      resources: [.copy("Layers.metal")])
  ]
)
