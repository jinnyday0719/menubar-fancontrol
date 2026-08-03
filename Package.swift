// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MenuBarFanControl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FanCtlCore", targets: ["FanCtlCore"]),
        .executable(name: "menubar-fancontrol", targets: ["FanCtlMenuBar"]),
        .executable(name: "menubar-fancontrol-helper", targets: ["FanCtlHelper"]),
        .executable(
            name: "menubar-fancontrol-legacy-cleanup",
            targets: ["FanCtlLegacyCleanup"]
        )
    ],
    targets: [
        .target(
            name: "FanCtlCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "FanCtlHelperXPC"
        ),
        .executableTarget(
            name: "FanCtlMenuBar",
            dependencies: ["FanCtlCore", "FanCtlHelperXPC"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "FanCtlHelper",
            dependencies: ["FanCtlCore", "FanCtlHelperXPC"],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "FanCtlLegacyCleanup",
            dependencies: ["FanCtlCore", "FanCtlHelperXPC"],
            linkerSettings: [
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "MenuBarFanControlCoreTests",
            dependencies: ["FanCtlCore"],
            path: "Tests/MenuBarFanControlCoreTests"
        ),
        .testTarget(
            name: "FanCtlHelperXPCTests",
            dependencies: ["FanCtlHelperXPC"]
        ),
        .testTarget(
            name: "FanCtlMenuBarTests",
            dependencies: ["FanCtlMenuBar"]
        )
    ]
)
