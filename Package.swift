// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mFanCtl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FanCtlCore", targets: ["FanCtlCore"]),
        .executable(name: "mfanctl-menubar", targets: ["FanCtlMenuBar"]),
        .executable(name: "mfanctl-helper", targets: ["FanCtlHelper"])
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
        .testTarget(
            name: "mFanCtlCoreTests",
            dependencies: ["FanCtlCore"]
        )
    ]
)
