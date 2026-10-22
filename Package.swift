// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundControl",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SoundControl", targets: ["SoundControl"])
    ],
    targets: [
        // Pure value-type logic: models, synth, resolution rules. Swift 6 strict concurrency, fully unit tested.
        .target(name: "SoundControlCore"),
        // The menu-bar app: system monitors (IOKit/CoreAudio C callbacks), audio engine, SwiftUI views.
        .executableTarget(
            name: "SoundControl",
            dependencies: ["SoundControlCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(name: "SoundControlCoreTests", dependencies: ["SoundControlCore"])
    ]
)
