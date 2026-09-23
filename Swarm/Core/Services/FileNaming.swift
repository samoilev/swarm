import Foundation

/// Names for files and folders Swarm writes beside other people's files.
enum FileNaming {
    /// Strip filesystem-illegal characters so a tree name can be used as a file/folder name.
    static func sanitizedFileName(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = raw.components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? L10n.tr("Дерево") : cleaned
    }

    /// Append " 2", " 3", … to `url`'s name until it points at a non-existent path.
    /// For directories pass `isDirectory: true` so a dot in the name (e.g. "Family v1.2")
    /// isn't mistaken for a file extension.
    static func uniqueURL(_ url: URL, isDirectory: Bool = false) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let base = isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let ext = isDirectory ? "" : url.pathExtension
        var i = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            let candidate = dir.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    /// A `.gdz` and its `.swarm-manifest` sidecar named as one pair: the first
    /// `name`, `name 2`, … for which *neither* exists. Uniquifying the archive alone
    /// let a stale sidecar with a free archive name become part of a new export.
    static func uniqueGEDZIPPair(in directory: URL, name: String) -> (archive: URL, sidecar: URL) {
        let fm = FileManager.default
        var stem = name
        var i = 2
        while true {
            let archive = directory.appendingPathComponent("\(stem).gdz")
            let sidecar = directory.appendingPathComponent("\(stem).swarm-manifest", isDirectory: true)
            if !fm.fileExists(atPath: archive.path), !fm.fileExists(atPath: sidecar.path) {
                return (archive, sidecar)
            }
            stem = "\(name) \(i)"
            i += 1
        }
    }
}
