import Foundation
import Observation

public struct PersonSearchEntry: Identifiable, Hashable, Sendable {
    public var id: UUID { personID }
    public let personID: UUID
    public var displayName: String
    public var normalizedText: String
    public var birthYear: Int?
    public var deathYear: Int?
    public var places: [String]
    public var hasMissingData: Bool
}

public struct TimelineEntry: Identifiable, Hashable, Sendable {
    public var id: String { "\(personID?.uuidString ?? unionID?.uuidString ?? "event"):\(eventID.uuidString)" }
    public let personID: UUID?
    public let unionID: UUID?
    public let relatedPersonIDs: [UUID]
    public let eventID: UUID
    public var personName: String
    public var kind: GenealogyEvent.Kind
    public var date: GenealogyDate?
    public var place: PlaceReference?
    public var sortYear: Int?
}

public struct PlaceWorkspaceEntry: Identifiable, Hashable, Sendable {
    public var id: String { place.datasetID ?? "custom:\(place.displayName)" }
    public var place: PlaceReference
    public var personIDs: [UUID]
    public var eventCount: Int
}

public struct DuplicateSuggestion: Identifiable, Hashable, Sendable {
    public var id: String {
        [firstPersonID.uuidString, secondPersonID.uuidString].sorted().joined(separator: ":")
    }

    public let firstPersonID: UUID
    public let secondPersonID: UUID
    public let reasons: [String]
}

/// Search, timeline, place and duplicate indexes contain metadata only. Portrait
/// bytes are deliberately excluded so 10,000-person trees remain cheap to browse.
@Observable
public final class TreeWorkspaceIndexes {
    public private(set) var searchEntries: [PersonSearchEntry] = []
    public private(set) var timelineEntries: [TimelineEntry] = []
    public private(set) var placeEntries: [PlaceWorkspaceEntry] = []
    public private(set) var duplicateSuggestions: [DuplicateSuggestion] = []
    public private(set) var issues: [TreeIssue] = []

    public init(tree: FamilyTree) {
        rebuild(tree: tree)
    }

    public func rebuild(tree: FamilyTree, validationContext: TreeValidationContext = .init()) {
        searchEntries = tree.people.map(Self.searchEntry)
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        timelineEntries = (tree.people.flatMap(Self.timelineEntries) + Self.unionTimelineEntries(tree))
            .sorted(by: Self.timelineSort)
        placeEntries = Self.buildPlaces(from: timelineEntries)
        duplicateSuggestions = TreeMergeEngine.duplicateSuggestions(in: tree)
        issues = TreeValidator.validate(tree, context: validationContext)
    }

    /// Incrementally replace one person's searchable/timeline/place metadata after a
    /// committed edit. Validation and duplicate candidates are recomputed because
    /// both depend on relationships outside the edited person.
    public func update(person: Person, in tree: FamilyTree, validationContext: TreeValidationContext = .init()) {
        searchEntries.removeAll { $0.personID == person.id }
        searchEntries.append(Self.searchEntry(person))
        searchEntries.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        timelineEntries.removeAll { $0.personID == person.id || $0.unionID != nil }
        timelineEntries.append(contentsOf: Self.timelineEntries(person))
        timelineEntries.append(contentsOf: Self.unionTimelineEntries(tree))
        timelineEntries.sort(by: Self.timelineSort)
        placeEntries = Self.buildPlaces(from: timelineEntries)
        duplicateSuggestions = TreeMergeEngine.duplicateSuggestions(in: tree)
        issues = TreeValidator.validate(tree, context: validationContext)
    }

    private static func searchEntry(_ person: Person) -> PersonSearchEntry {
        let places = person.events.compactMap(\.place?.displayName)
        let combined = ([person.fullName, person.listName] + places).joined(separator: " ")
        return PersonSearchEntry(
            personID: person.id,
            displayName: person.listName.isEmpty ? L10n.tr("Без имени") : person.listName,
            normalizedText: normalize(combined),
            birthYear: person.event(ofKind: .birth)?.date?.year,
            deathYear: person.event(ofKind: .death)?.date?.year,
            places: places,
            hasMissingData: person.givenNames.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                person.surname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                person.event(ofKind: .birth)?.date == nil
        )
    }

    private static func timelineEntries(_ person: Person) -> [TimelineEntry] {
        person.events.map { event in
            TimelineEntry(
                personID: person.id,
                unionID: nil,
                relatedPersonIDs: [person.id],
                eventID: event.id,
                personName: person.listName.isEmpty ? L10n.tr("Без имени") : person.listName,
                kind: event.kind,
                date: event.date,
                place: event.place,
                sortYear: event.date?.year
            )
        }
    }

    private static func unionTimelineEntries(_ tree: FamilyTree) -> [TimelineEntry] {
        tree.unions.flatMap { union in
            let relatedIDs = Array(Set(union.partnerIds + union.childrenIds))
            let names = union.partnerIds.compactMap { tree.person(byId: $0)?.listName }
            let title = names.isEmpty ? L10n.tr("Семейная запись") : names.joined(separator: " + ")
            return union.events.map { event in
                TimelineEntry(
                    personID: union.partnerIds.first ?? union.childrenIds.first,
                    unionID: union.id,
                    relatedPersonIDs: relatedIDs,
                    eventID: event.id,
                    personName: title,
                    kind: event.kind,
                    date: event.date,
                    place: event.place,
                    sortYear: event.date?.year
                )
            }
        }
    }

    private static func timelineSort(_ lhs: TimelineEntry, _ rhs: TimelineEntry) -> Bool {
        switch (lhs.sortYear, rhs.sortYear) {
        case let (a?, b?): a == b ? lhs.personName < rhs.personName : a < b
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.personName < rhs.personName
        }
    }

    private static func buildPlaces(from timeline: [TimelineEntry]) -> [PlaceWorkspaceEntry] {
        var grouped: [String: PlaceWorkspaceEntry] = [:]
        for entry in timeline {
            guard let place = entry.place, !place.displayName.isEmpty else { continue }
            let key = place.datasetID ?? "custom:\(normalize(place.displayName)):\(place.latitude ?? 999):\(place.longitude ?? 999)"
            var group = grouped[key] ?? PlaceWorkspaceEntry(place: place, personIDs: [], eventCount: 0)
            for personID in entry.relatedPersonIDs where !group.personIDs.contains(personID) {
                group.personIDs.append(personID)
            }
            group.eventCount += 1
            grouped[key] = group
        }
        return grouped.values.sorted { $0.place.displayName.localizedStandardCompare($1.place.displayName) == .orderedAscending }
    }

    public static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
