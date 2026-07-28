// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Swarm",
    defaultLocalization: "ru",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure domain logic (Models + Services): no SwiftUI dependency, so it can be
        // unit-tested independently of the app's views.
        .target(
            name: "SwarmCore",
            path: "Swarm/Core",
            exclude: ["Resources/PLACE_DATA.md", "Resources/MAP_DATA.md"],
            resources: [
                .process("Resources/Localization"),
                .copy("Resources/place_index_v2.tsv"),
                .copy("Resources/ne_110m_land.geojson"),
                .copy("Resources/ne_110m_admin_0_boundary_lines_land.geojson"),
            ]
        ),
        // The SwiftUI app shell. Depends on SwarmCore for all domain types.
        .executableTarget(
            name: "Swarm",
            dependencies: ["SwarmCore"],
            path: "Swarm/App",
            exclude: ["Assets.xcassets"],
            resources: [.copy("Resources/AppIcon.icns")]
        ),
        .testTarget(
            name: "SwarmCoreTests",
            dependencies: ["SwarmCore"],
            path: "Tests/SwarmCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
