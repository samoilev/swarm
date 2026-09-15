import Foundation

/// Locates the SwiftPM resource bundles.
///
/// SwiftPM's generated `Bundle.module` looks in exactly two places: next to
/// `Bundle.main.bundleURL`, and the absolute `.build` directory of the machine that
/// compiled the binary. Neither exists in a packaged `.app`, where resources belong in
/// `Contents/Resources` — so `Bundle.module` traps at launch on any machine other than
/// the one that built it, and only that machine's leftover `.build` directory hides it.
///
/// Resolving through `Bundle.main` first fixes the packaged case. `Bundle.module` is
/// touched only when the app bundle has no copy, which is the `swift run` and test path.
/// The order matters: reading `Bundle.module` when it cannot resolve is fatal, so it must
/// stay the fallback rather than the probe.
enum ResourceBundle {
    /// Resources belonging to `SwarmCore` — place data, map vectors, translations.
    static let core: Bundle = packaged(named: "Swarm_SwarmCore") ?? .module

    /// A resource URL that a retry can actually recover.
    ///
    /// `Bundle`'s own lookup memoises its answer for the life of the process, a miss
    /// included, so a file restored while the app runs stays invisible to it and Try Again
    /// keeps reporting the original failure. Falling back to the bundle's resource folder
    /// asks the file system instead.
    ///
    /// ponytail: a flat-resource fallback, not a general replacement for bundle lookup —
    /// it does not walk localised subdirectories. Every caller here wants a flat resource.
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = core.url(forResource: name, withExtension: ext) { return url }
        guard let direct = core.resourceURL?.appendingPathComponent("\(name).\(ext)"),
              FileManager.default.fileExists(atPath: direct.path) else { return nil }
        return direct
    }

    private static func packaged(named name: String) -> Bundle? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "bundle") else { return nil }
        return Bundle(url: url)
    }
}
