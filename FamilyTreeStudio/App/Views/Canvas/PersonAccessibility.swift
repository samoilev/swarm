import FamilyTreeCore

extension Person {
    /// Spoken description for VoiceOver on canvas nodes (tree cards, fan wedges, map
    /// pins): name, then lifespan and sex when known. Keeps the three visual surfaces
    /// announcing the same thing.
    var accessibilityDescription: String {
        var parts = [listName.isEmpty ? "Неизвестно" : listName]
        if !lifespan.isEmpty { parts.append(lifespan) }
        if sex != .unknown { parts.append(sex.displayName) }
        return parts.joined(separator: ", ")
    }
}
