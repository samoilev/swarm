import CoreGraphics
import SwarmCore

/// Zoom and pan that seat `content` whole and centred inside `viewSize`, with the same
/// margin and zoom limits every canvas uses. Returns nil when either box is degenerate.
/// The tree and the fan both fit to screen; only the state they write differs, so the
/// arithmetic lives here rather than once per canvas.
func canvasFitTransform(viewSize: CGSize, content: CGSize) -> (zoom: CGFloat, offset: CGSize)? {
    guard content.width > 0, content.height > 0, viewSize.width > 0, viewSize.height > 0 else { return nil }
    let margin: CGFloat = 20
    let scaleW = (viewSize.width - margin * 2) / content.width
    let scaleH = (viewSize.height - margin * 2) / content.height
    let zoom = max(0.2, min(min(scaleW, scaleH), 1.6))
    return (
        zoom,
        CGSize(
            width: (viewSize.width - content.width * zoom) / 2,
            height: (viewSize.height - content.height * zoom) / 2
        )
    )
}

extension Person {
    /// Spoken description for VoiceOver on canvas nodes (tree cards, fan wedges, map
    /// pins): name, then lifespan and sex when known. Keeps the three visual surfaces
    /// announcing the same thing.
    var accessibilityDescription: String {
        let name = displayName(language: .current)
        var parts = [name.isEmpty ? L10n.tr("Неизвестно") : name]
        if !lifespan.isEmpty { parts.append(lifespan) }
        if sex != .unknown { parts.append(sex.displayName) }
        return parts.joined(separator: ", ")
    }

    /// The place to print beside an event pin, resolved through the place dataset so the
    /// label matches the current language. Falls back to the person's own free-text field
    /// when the event carries no place reference.
    func presentationPlace(kind: GenealogyEvent.Kind, fallback: String?) -> String {
        guard let reference = event(ofKind: kind)?.place else { return fallback ?? "" }
        return PlacesDatabase.shared.presentationName(for: reference, language: .current)
    }
}
