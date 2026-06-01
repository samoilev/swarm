// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FamilyTreeStudio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FamilyTreeStudio",
            path: "FamilyTreeStudio",
            exclude: ["Assets.xcassets", "FamilyTreeStudio.entitlements"],
            resources: [.copy("Resources/places.tsv"), .copy("Resources/geonames_ussr.tsv"), .copy("Resources/AppIcon.icns")]
        )
    ]
)
