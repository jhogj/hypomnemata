// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HypomnemataNative",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "HypomnemataMacApp", targets: ["HypomnemataMacApp"]),
        .executable(name: "HypomnemataNativeChecks", targets: ["HypomnemataNativeChecks"]),
        .library(name: "HypomnemataCore", targets: ["HypomnemataCore"]),
        .library(name: "HypomnemataData", targets: ["HypomnemataData"]),
        .library(name: "HypomnemataMedia", targets: ["HypomnemataMedia"]),
        .library(name: "HypomnemataIngestion", targets: ["HypomnemataIngestion"]),
        .library(name: "HypomnemataAI", targets: ["HypomnemataAI"]),
        .library(name: "HypomnemataBackup", targets: ["HypomnemataBackup"]),
    ],
    dependencies: [
        .package(path: "Vendor/GRDBSQLCipher"),
    ],
    targets: [
        .target(name: "HypomnemataCore"),
        .target(
            name: "HypomnemataData",
            dependencies: [
                "HypomnemataCore",
                .product(name: "GRDB", package: "GRDBSQLCipher"),
            ]
        ),
        .target(
            name: "HypomnemataMedia",
            dependencies: ["HypomnemataCore"]
        ),
        .target(
            name: "HypomnemataIngestion",
            dependencies: ["HypomnemataCore"]
        ),
        .target(
            name: "HypomnemataAI",
            dependencies: ["HypomnemataCore"]
        ),
        .target(
            name: "HypomnemataBackup",
            dependencies: ["HypomnemataCore", "HypomnemataData"]
        ),
        .executableTarget(
            name: "HypomnemataMacApp",
            dependencies: [
                "HypomnemataCore",
                "HypomnemataData",
                "HypomnemataMedia",
                "HypomnemataIngestion",
                "HypomnemataAI",
                "HypomnemataBackup",
            ]
        ),
        .executableTarget(
            name: "HypomnemataNativeChecks",
            dependencies: [
                "HypomnemataCore",
                "HypomnemataData",
                "HypomnemataIngestion",
                "HypomnemataMedia",
                .product(name: "GRDB", package: "GRDBSQLCipher"),
            ]
        ),
    ]
)
