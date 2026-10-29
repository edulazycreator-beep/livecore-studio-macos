// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LiveCoreStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "LiveCoreStudio",
            targets: ["LiveCoreStudio"]
        )
    ],
    targets: [
        .executableTarget(
            name: "LiveCoreStudio",
            path: "LiveCoreStudio/Sources",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreImage"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("Network")
            ]
        ),
        .testTarget(
            name: "LiveCoreStudioTests",
            dependencies: ["LiveCoreStudio"],
            path: "LiveCoreStudioTests"
        )
    ]
)
