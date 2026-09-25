// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SchreibtischUnterlage",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "SchreibtischUnterlage",
            targets: ["SchreibtischUnterlage"]
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
            name: "SchreibtischUnterlageCore",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .target(
            name: "SchreibtischUnterlagePlatform",
            dependencies: [
                "CGVirtualDisplayBridge",
                "SchreibtischUnterlageCore",
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
            name: "SchreibtischUnterlage",
            dependencies: [
                "SchreibtischUnterlageCore",
                "SchreibtischUnterlagePlatform",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "SchreibtischUnterlageCoreTests",
            dependencies: ["SchreibtischUnterlageCore"],
            path: "Tests/SchreibtischUnterlageCoreTests"
        ),
    ]
)
