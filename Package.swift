// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FamilyTreeStudio",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure domain logic (Models + Services): no SwiftUI dependency, so it can be
        // unit-tested independently of the app's views.
        .target(
            name: "FamilyTreeCore",
            path: "FamilyTreeStudio/Core",
            exclude: ["Resources/AppIcon_preview.png", "Resources/PLACE_DATA.md", "Resources/MAP_DATA.md"],
            resources: [
                .copy("Resources/places.tsv"),
                .copy("Resources/geonames_ussr.tsv"),
                .copy("Resources/place_index_v2.tsv"),
                .copy("Resources/ne_110m_land.geojson"),
                .copy("Resources/ne_110m_admin_0_boundary_lines_land.geojson"),
            ]
        ),
        // The SwiftUI app shell. Depends on FamilyTreeCore for all domain types.
        .executableTarget(
            name: "FamilyTreeStudio",
            dependencies: ["FamilyTreeCore"],
            path: "FamilyTreeStudio/App",
            exclude: ["Assets.xcassets"],
            resources: [.copy("Resources/AppIcon.icns")]
        ),
        .testTarget(
            name: "FamilyTreeCoreTests",
            dependencies: ["FamilyTreeCore"],
            path: "Tests/FamilyTreeCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
