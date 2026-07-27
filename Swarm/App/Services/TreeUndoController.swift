import Foundation
import SwarmCore

/// Snapshot-based undo/redo for a single tree.
///
/// `FamilyTree`, `Person`, and `Union` are all reference types kept in memory, so
/// undo works by serializing the whole tree (Codable → JSON, lossless including
/// photos and coordinates) before a mutation and restoring it on demand. One undo
/// entry covers one edit *session*: opening the add or edit sheet, or a single
/// delete. A session that changes nothing (a cancelled sheet) records no entry.
final class TreeUndoController {
    private var undoStack: [Data] = []
    private var redoStack: [Data] = []
    /// Tree state captured at the start of the current session, pending commit.
    private var sessionBase: Data?

    /// True while a mutation session (an open add/edit sheet) is in flight. Undo/redo
    /// must be refused then — applying a snapshot would rewrite the tree under the
    /// open editor and lose its edits.
    var isSessionActive: Bool {
        sessionBase != nil
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Capture the tree state at the start of a mutation session.
    func begin(_ tree: FamilyTree) {
        sessionBase = try? Self.encoder.encode(tree)
    }

    /// Close a session: record an undo entry only if the tree actually changed.
    func commit(_ tree: FamilyTree) {
        guard let base = sessionBase else { return }
        sessionBase = nil
        guard let now = try? Self.encoder.encode(tree), now != base else { return }
        undoStack.append(base)
        redoStack.removeAll()
    }

    /// Abort an in-flight mutation and restore the exact session snapshot. Used when
    /// transactional persistence fails after the in-memory mutation was prepared.
    func cancel(_ tree: FamilyTree) {
        guard let base = sessionBase else { return }
        sessionBase = nil
        apply(base, to: tree)
    }

    /// Restore the previous state into the live tree. Returns false when nothing is
    /// on the undo stack so the caller can skip the save/toast.
    @discardableResult
    func undo(_ tree: FamilyTree) -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        if let current = try? Self.encoder.encode(tree) { redoStack.append(current) }
        apply(previous, to: tree)
        return true
    }

    @discardableResult
    func redo(_ tree: FamilyTree) -> Bool {
        guard let next = redoStack.popLast() else { return false }
        if let current = try? Self.encoder.encode(tree) { undoStack.append(current) }
        apply(next, to: tree)
        return true
    }

    /// Copy a decoded snapshot back into the live tree instance (shared across many
    /// views), then bump `layoutVersion` so the canvases recompute their layout.
    private func apply(_ data: Data, to tree: FamilyTree) {
        guard let snapshot = try? Self.decoder.decode(FamilyTree.self, from: data) else { return }
        tree.applyContent(of: snapshot)
    }
}
