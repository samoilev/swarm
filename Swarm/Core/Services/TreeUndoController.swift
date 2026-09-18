import Foundation
import Observation

/// Snapshot-based undo/redo for a single tree.
///
/// `FamilyTree`, `Person`, and `Union` are all reference types kept in memory, so
/// undo works by serializing the whole tree (Codable → JSON, lossless including
/// photos and coordinates) before a mutation and restoring it on demand. One undo
/// entry covers one edit *session*: opening the add or edit sheet, a merge, or a
/// single delete. A session that changes nothing (a cancelled sheet) records no entry.
@MainActor
@Observable
public final class TreeUndoController {
    private var undoStack: [Data] = []
    private var redoStack: [Data] = []
    /// Tree state captured at the start of the current session, pending commit.
    private var sessionBase: Data?

    /// Set when a snapshot failed to encode or decode. The operation it belongs to
    /// was skipped with the stacks left intact, so nothing was silently lost — but
    /// the user should hear that undo did not happen. Cleared by the view once shown.
    public var lastError: String?

    /// Every entry is a full-tree JSON snapshot, so the stacks are the memory cost
    /// driver; beyond this the oldest entry is dropped.
    private static let maxEntries = 50

    /// True while a mutation session (an open add/edit sheet) is in flight. Undo/redo
    /// must be refused then — applying a snapshot would rewrite the tree under the
    /// open editor and lose its edits.
    public var isSessionActive: Bool {
        sessionBase != nil
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Sorted keys make two encodes of identical state byte-equal. Without this,
    /// JSONEncoder's hash-seeded key order made `commit`'s "did anything change"
    /// comparison always true — every cancelled sheet recorded a phantom entry.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    public init() {}

    /// Capture the tree state at the start of a mutation session.
    public func begin(_ tree: FamilyTree) {
        do {
            sessionBase = try Self.encoder.encode(tree)
        } catch {
            sessionBase = nil
            lastError = L10n.tr("Это изменение нельзя отменить с помощью ⌘Z.")
        }
    }

    /// Close a session: record an undo entry only if the tree changed.
    public func commit(_ tree: FamilyTree) {
        guard let base = sessionBase else { return }
        sessionBase = nil
        // If the current state cannot be encoded for comparison, keep the entry
        // anyway: undoing back to the session base stays valid.
        if let now = try? Self.encoder.encode(tree), now == base { return }
        push(base, onto: &undoStack)
        redoStack.removeAll()
    }

    /// Abort an in-flight mutation and restore the exact session snapshot. Used when
    /// transactional persistence fails after the in-memory mutation was prepared.
    public func cancel(_ tree: FamilyTree) {
        guard let base = sessionBase else { return }
        sessionBase = nil
        if let snapshot = decodeOrReport(base) { tree.applyContent(of: snapshot) }
    }

    /// Restore the previous state into the live tree. Returns false when nothing is
    /// on the undo stack (or the snapshot is unreadable — stacks are left intact and
    /// `lastError` is set) so the caller can skip the save/toast.
    @discardableResult
    public func undo(_ tree: FamilyTree) -> Bool {
        guard let previous = undoStack.last else { return false }
        guard let snapshot = decodeOrReport(previous) else { return false }
        if let current = try? Self.encoder.encode(tree) { push(current, onto: &redoStack) }
        undoStack.removeLast()
        tree.applyContent(of: snapshot)
        return true
    }

    @discardableResult
    public func redo(_ tree: FamilyTree) -> Bool {
        guard let next = redoStack.last else { return false }
        guard let snapshot = decodeOrReport(next) else { return false }
        if let current = try? Self.encoder.encode(tree) { push(current, onto: &undoStack) }
        redoStack.removeLast()
        tree.applyContent(of: snapshot)
        return true
    }

    private func push(_ data: Data, onto stack: inout [Data]) {
        stack.append(data)
        if stack.count > Self.maxEntries { stack.removeFirst(stack.count - Self.maxEntries) }
    }

    /// Decode a snapshot; on failure set `lastError` instead of silently consuming
    /// the entry — `applyContent` bumps `layoutVersion` so canvases recompute.
    private func decodeOrReport(_ data: Data) -> FamilyTree? {
        do {
            return try Self.decoder.decode(FamilyTree.self, from: data)
        } catch {
            lastError = L10n.tr("Не удалось отменить изменение: данные для отмены повреждены.")
            return nil
        }
    }
}
