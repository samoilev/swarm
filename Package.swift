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
            exclude: ["Resources/AppIcon_preview.png"],
            resources: [
                .copy("Resources/places.tsv"),
                .copy("Resources/geonames_ussr.tsv"),
            ]
        ),
        // The SwiftUI app shell. Depends on FamilyTreeCore for all domain types.
        .executableTarget(
            name: "FamilyTreeStudio",
            dependencies: ["FamilyTreeCore"],
            path: "FamilyTreeStudio/App",
            exclude: ["Assets.xcassets", "FamilyTreeStudio.entitlements"],
            resources: [.copy("Resources/AppIcon.icns")]
        ),
        .testTarget(
            name: "FamilyTreeCoreTests",
            dependencies: ["FamilyTreeCore"],
            path: "Tests/FamilyTreeCoreTests"
        ),
    ]
)
