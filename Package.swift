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
            name: "SchreibtischunterlageCore"
        ),
        .executableTarget(
            name: "Schreibtischunterlage",
            dependencies: ["SchreibtischunterlageCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "SchreibtischunterlageCoreTests",
            dependencies: ["SchreibtischunterlageCore"],
            path: "Tests/SchreibtischunterlageCoreTests"
        ),
    ]
)
