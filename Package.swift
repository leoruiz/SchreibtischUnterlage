// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Schreibtischunterlage",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "Schreibtischunterlage",
            targets: ["Schreibtischunterlage"]
        ),
    ],
    targets: [
        .target(
            name: "CGVirtualDisplayBridge",
            path: "Sources/CGVirtualDisplayBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-fobjc-arc"]),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .target(
            name: "SchreibtischunterlageCore",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .target(
            name: "SchreibtischunterlagePlatform",
            dependencies: [
                "CGVirtualDisplayBridge",
                "SchreibtischunterlageCore",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .executableTarget(
            name: "Schreibtischunterlage",
            dependencies: [
                "SchreibtischunterlageCore",
                "SchreibtischunterlagePlatform",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "SchreibtischunterlageCoreTests",
            dependencies: ["SchreibtischunterlageCore"],
            path: "Tests/SchreibtischunterlageCoreTests"
        ),
    ]
)
