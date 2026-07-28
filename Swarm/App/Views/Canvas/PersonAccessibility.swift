import SwarmCore

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
}
