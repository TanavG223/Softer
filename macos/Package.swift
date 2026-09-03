// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PaceBack",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "PaceBack", targets: ["PaceBackApp"]),
        .executable(name: "PaceBackVerification", targets: ["PaceBackVerification"])
    ],
    targets: [
        .target(
            name: "PaceBackCore",
            linkerSettings: [
                .linkedFramework("CryptoKit"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "PaceBackApp",
            dependencies: ["PaceBackCore"]
        ),
        .executableTarget(
            name: "PaceBackVerification",
            dependencies: ["PaceBackCore"]
        )
    ]
)
