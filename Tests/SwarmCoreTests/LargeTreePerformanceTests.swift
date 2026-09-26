import Foundation
@testable import SwarmCore
import Testing

/// Timings for a synthetic large tree: parse, serialize, import, save and relaunch.
/// Opt-in, because it measures rather than asserts and takes a while:
///
///     SWARM_PERF=1 ./Scripts/run-tests.sh --filter LargeTreePerformanceTests
///
/// `SWARM_PERF_PEOPLE` and `SWARM_PERF_MEDIA_MB` size the tree (defaults 20,000 people,
/// 200 MB of portraits). Compare the printed numbers before and after a change.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWARM_PERF"] != nil))
@MainActor
struct LargeTreePerformanceTests {
    private static let environment = ProcessInfo.processInfo.environment
    private static let people = Int(environment["SWARM_PERF_PEOPLE"] ?? "") ?? 20000
    private static let mediaMB = Int(environment["SWARM_PERF_MEDIA_MB"] ?? "") ?? 200

    /// Person `p` partners in family `(p + 1) / 2`; family `k` has children
    /// `4k + 1 … 4k + 4`. Every child gets two parent links, so links ≈ 2 × people.
    private static func gedcom(people: Int, portraits: Int) -> String {
        var lines = ["0 HEAD", "1 GEDC", "2 VERS 5.5.1", "1 CHAR UTF-8"]
        for p in 1 ... people {
            lines.append("0 @I\(p)@ INDI")
            lines.append("1 NAME Человек\(p) /Фамилия\(p % 500)/")
            lines.append("1 SEX \(p.isMultiple(of: 2) ? "F" : "M")")
            lines.append("1 BIRT")
            lines.append("2 DATE \(1500 + p % 400)")
            if p <= portraits {
                lines.append("1 OBJE")
                lines.append("2 FILE portrait-\(p).jpg")
            }
            lines.append("1 FAMS @F\((p + 1) / 2)@")
            if p > 4 { lines.append("1 FAMC @F\((p - 1) / 4)@") }
        }
        for k in 1 ... people / 2 {
            lines.append("0 @F\(k)@ FAM")
            lines.append("1 HUSB @I\(2 * k - 1)@")
            lines.append("1 WIFE @I\(2 * k)@")
            for child in (4 * k + 1) ... (4 * k + 4) where child <= people {
                lines.append("1 CHIL @I\(child)@")
            }
        }
        lines.append("0 TRLR")
        return lines.joined(separator: "\n")
    }

    private func time<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        let result = try body()
        print("⏱ \(label): \(start.duration(to: .now))")
        return result
    }

    private func time<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        let result = try await body()
        print("⏱ \(label): \(start.duration(to: .now))")
        return result
    }

    @Test func largeTreeTimings() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("swarm-perf-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let media = source.appendingPathComponent("Media", isDirectory: true)
        try fm.createDirectory(at: media, withIntermediateDirectories: true)

        let portraitBytes = 2 * 1024 * 1024
        let portraits = min(Self.people, Self.mediaMB / 2)
        let bytes = Data((0 ..< portraitBytes).map { UInt8(truncatingIfNeeded: $0) })
        for p in stride(from: 1, through: portraits, by: 1) {
            try bytes.write(to: media.appendingPathComponent("portrait-\(p).jpg"))
        }
        let text = Self.gedcom(people: Self.people, portraits: portraits)
        let ged = source.appendingPathComponent("Большое дерево.ged")
        try text.write(to: ged, atomically: true, encoding: .utf8)
        print("⏱ tree: \(Self.people) people, \(portraits) portraits of 2 MB")

        let parsed = try time("parse") { try GEDCOMCodec.parse(ged) }
        _ = try time("serialize") {
            try GEDCOMCodec.serialize(tree: parsed.tree, document: parsed.document)
        }

        let library = root.appendingPathComponent("Library", isDirectory: true)
        let store = TreeStore(storageFolder: library)
        let staged = try time("stage import") { try store.stageImport(from: ged) }
        let tree = try await time("import") { try await store.importGEDCOM(from: staged).tree }
        store.discardImportPreview(at: staged)

        // One undo entry is a full JSON snapshot; the imported syntax tree rides along.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let snapshot = try encoder.encode(tree)
        let withoutDocument = try tree.deepCopy()
        withoutDocument.gedcomDocument = nil
        let slimmed = try encoder.encode(withoutDocument)
        let packed = time("pack undo snapshot") { TreeUndoController.pack(snapshot) }
        print("⏱ undo snapshot: \(snapshot.count / 1024) KB, \(packed.count / 1024) KB stored, \(slimmed.count / 1024) KB without the imported document")

        tree.people[0].givenNames = "Изменённое имя"
        _ = try await time("save after one edit") { try await store.saveTree(tree) }
        _ = time("relaunch (load library)") { TreeStore(storageFolder: library) }
        #expect(tree.people.count == Self.people)
    }
}
