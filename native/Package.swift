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
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
    ],
    targets: [
        .target(name: "HypomnemataCore"),
        .target(
            name: "HypomnemataData",
            dependencies: [
                "HypomnemataCore",
                .product(name: "GRDB", package: "GRDB.swift"),
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
                "HypomnemataMedia",
            ]
        ),
    ]
)
