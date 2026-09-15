import SwiftUI

/// Tracks whether any screen is holding text the reader has typed and not yet saved.
///
/// It exists for one caller: the interface-size setting. Changing that size bumps
/// `.id(scaleRaw)` on the whole destination subtree in `ContentView`, which is the only
/// thing that re-runs bodies after `SepiaTheme.scale` changes — and which also destroys
/// every `@State` below it. Every draft in the app is `@State` inside that subtree, so a
/// scale change silently threw away a half-written person, source, merge or new tree.
///
/// The gate lets Settings ask before doing that, from the other window. It has to be one
/// instance shared by both scenes, so it is injected in `SwarmApp`.
///
/// ponytail: tracks *presented*, not *edited* — no field-by-field comparison. If the
/// prompt turns out to appear when nothing was actually typed, narrow the registration in
/// `EditPersonView` rather than teaching this type about content.
@Observable
final class DraftGate {
    /// One token per open draft: sheets stack, and the editor can open a source form over
    /// itself, so a plain `Bool` would clear the gate when the inner one closed.
    private var openDrafts: Set<UUID> = []

    var hasUnsavedDrafts: Bool { !openDrafts.isEmpty }

    func register(_ token: UUID) {
        openDrafts.insert(token)
    }

    func unregister(_ token: UUID) {
        openDrafts.remove(token)
    }
}

extension View {
    /// Marks this view as holding an unsaved draft for as long as it is on screen.
    func tracksUnsavedDraft() -> some View {
        modifier(UnsavedDraftTracker())
    }
}

private struct UnsavedDraftTracker: ViewModifier {
    @Environment(DraftGate.self) private var gate
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { gate.register(token) }
            .onDisappear { gate.unregister(token) }
    }
}
