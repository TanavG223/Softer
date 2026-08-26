// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PaceBack",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "PaceBack", targets: ["PaceBackApp"])
    ],
    targets: [
        .target(
            name: "PaceBackCore",
            linkerSettings: [
                .linkedFramework("CryptoKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security"),
                .linkedFramework("Vision")
            ]
        ),
        .executableTarget(
            name: "PaceBackApp",
            dependencies: ["PaceBackCore"]
        ),
        .testTarget(
            name: "PaceBackCoreTests",
            dependencies: ["PaceBackCore"]
        )
    ]
)
