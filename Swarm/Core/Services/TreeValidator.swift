import Foundation

public struct TreeValidationContext: Sendable {
    /// Issue identities accepted from an imported baseline. They remain visible but
    /// do not block unrelated edits until the user changes the affected structure.
    public var acceptedBaselineIssueIDs: Set<String>
    public var treeFolderURL: URL?

    public init(acceptedBaselineIssueIDs: Set<String> = [], treeFolderURL: URL? = nil) {
        self.acceptedBaselineIssueIDs = acceptedBaselineIssueIDs
        self.treeFolderURL = treeFolderURL
    }
}

public struct TreeIssue: Identifiable, Codable, Hashable, Sendable {
    public enum Severity: String, Codable, CaseIterable, Sendable {
        case warning
        case error
    }

    public var id: String
    public var code: String
    public var severity: Severity
    public var title: String
    public var message: String
    public var personID: UUID?
    public var unionID: UUID?
    public var field: String?
    public var isBlocking: Bool

    public init(
        id: String,
        code: String,
        severity: Severity,
        title: String,
        message: String,
        personID: UUID? = nil,
        unionID: UUID? = nil,
        field: String? = nil,
        isBlocking: Bool
    ) {
        self.id = id
        self.code = code
        self.severity = severity
        self.title = title
        self.message = message
        self.personID = personID
        self.unionID = unionID
        self.field = field
        self.isBlocking = isBlocking
    }
}

public enum TreeValidator {
    public static func validate(
        _ tree: FamilyTree,
        context: TreeValidationContext = TreeValidationContext()
    ) -> [TreeIssue] {
        var issues: [TreeIssue] = []
        let personIDs = Set(tree.people.map(\.id))
        let unionIDs = Set(tree.unions.map(\.id))
        let sourceIDs = Set(tree.sourceRecords.map(\.id))

        addDuplicateIDs(tree.people.map(\.id), kind: "person", title: L10n.tr("Повтор идентификатора персоны"), to: &issues)
        addDuplicateIDs(tree.unions.map(\.id), kind: "union", title: L10n.tr("Повтор идентификатора семьи"), to: &issues)
        addDuplicateIDs(tree.sourceRecords.map(\.id), kind: "source", title: L10n.tr("Повтор идентификатора источника"), to: &issues)
        addSimilarSources(tree.sourceRecords, into: &issues)

        for union in tree.unions {
            for partner in union.partnerIds where !personIDs.contains(partner) {
                issues.append(error(
                    id: "union.\(union.id).dangling-partner.\(partner)",
                    code: "relationship.dangling-person",
                    title: L10n.tr("Не найдена персона"),
                    message: L10n.tr("Семейная связь ссылается на отсутствующую персону."),
                    unionID: union.id,
                    field: "partners"
                ))
            }
            for child in union.childrenIds where !personIDs.contains(child) {
                issues.append(error(
                    id: "union.\(union.id).dangling-child.\(child)",
                    code: "relationship.dangling-person",
                    title: L10n.tr("Не найден ребёнок"),
                    message: L10n.tr("Семейная запись ссылается на отсутствующего ребёнка."),
                    unionID: union.id,
                    field: "children"
                ))
            }
            if let p1 = union.partner1Id, p1 == union.partner2Id {
                issues.append(error(
                    id: "union.\(union.id).self-partner",
                    code: "relationship.self-link",
                    title: L10n.tr("Связь с самим собой"),
                    message: L10n.tr("Одна персона не может занимать обе позиции партнёров."),
                    unionID: union.id,
                    field: "partners"
                ))
            }
            for child in union.childrenIds where union.partnerIds.contains(child) {
                issues.append(error(
                    id: "union.\(union.id).self-parent.\(child)",
                    code: "relationship.self-link",
                    title: L10n.tr("Связь с самим собой"),
                    message: L10n.tr("Персона не может быть собственным родителем."),
                    personID: child,
                    unionID: union.id,
                    field: "children"
                ))
            }
        }

        for link in tree.parentLinks {
            if link.parentID == link.childID {
                issues.append(error(
                    id: "parent-link.\(link.id).self",
                    code: "relationship.self-link",
                    title: L10n.tr("Связь с самим собой"),
                    message: L10n.tr("Персона не может быть собственным родителем."),
                    personID: link.childID,
                    field: "parentage"
                ))
            }
            if !personIDs.contains(link.parentID) || !personIDs.contains(link.childID) ||
                (link.unionID != nil && !unionIDs.contains(link.unionID!)) {
                issues.append(error(
                    id: "parent-link.\(link.id).dangling",
                    code: "relationship.dangling-person",
                    title: L10n.tr("Неполная родительская связь"),
                    message: L10n.tr("Один из участников родительской связи отсутствует."),
                    personID: link.childID,
                    field: "parentage"
                ))
            }
        }

        for cycle in ancestryCycles(tree) {
            let signature = cycle.map(\.uuidString).sorted().joined(separator: ".")
            issues.append(error(
                id: "relationship.cycle.\(signature)",
                code: "relationship.ancestry-cycle",
                title: L10n.tr("Цикл предков"),
                message: L10n.tr("Цепочка родителей возвращается к исходной персоне."),
                personID: cycle.first,
                field: "parentage"
            ))
        }

        for person in tree.people {
            validateDates(person.events, owner: "person.\(person.id)", personID: person.id, unionID: nil, into: &issues)
            validateCoordinates(person.events, owner: "person.\(person.id)", personID: person.id, unionID: nil, into: &issues)
            validateChronology(person, into: &issues)

            for event in person.events where event.place?.displayName.isEmpty == false && event.place?.hasValidCoordinates != true {
                issues.append(warning(
                    id: "person.\(person.id).event.\(event.id).unpinned",
                    code: "place.unpinned",
                    title: L10n.tr("Место без координат"),
                    message: L10n.tr("«\(event.place?.displayName ?? "")» не будет показано на карте."),
                    personID: person.id,
                    field: event.kind.rawValue
                ))
            }
            let allPersonCitations = person.citations + person.events.flatMap(\.citations) +
                person.names.flatMap(\.citations) + person.attachments.flatMap(\.citations)
            for citation in allPersonCitations where !sourceIDs.contains(citation.sourceID) {
                issues.append(error(
                    id: "person.\(person.id).citation.\(citation.id).missing-source",
                    code: "citation.missing-source",
                    title: L10n.tr("Источник не найден"),
                    message: L10n.tr("Ссылка доказательства указывает на отсутствующий источник."),
                    personID: person.id,
                    field: "citations"
                ))
            }
            if let folder = context.treeFolderURL {
                if let photo = person.photoFilename {
                    let file = folder.appendingPathComponent("Media").appendingPathComponent(photo)
                    if !FileManager.default.fileExists(atPath: file.path) {
                        issues.append(warning(
                            id: "person.\(person.id).portrait.missing",
                            code: "file.missing",
                            title: L10n.tr("Портрет не найден"),
                            message: L10n.tr("Файл портрета «\(photo)» отсутствует на диске."),
                            personID: person.id,
                            field: "portrait"
                        ))
                    }
                }
                for attachment in person.attachments {
                    let file = folder.appendingPathComponent("Attachments").appendingPathComponent(attachment.storedName)
                    if !FileManager.default.fileExists(atPath: file.path) {
                        issues.append(warning(
                            id: "person.\(person.id).attachment.\(attachment.id).missing",
                            code: "file.missing",
                            title: L10n.tr("Файл не найден"),
                            message: L10n.tr("Вложение «\(attachment.originalName)» отсутствует на диске."),
                            personID: person.id,
                            field: "attachments"
                        ))
                    }
                }
            }
        }

        for union in tree.unions {
            validateDates(union.events, owner: "union.\(union.id)", personID: nil, unionID: union.id, into: &issues)
            validateCoordinates(union.events, owner: "union.\(union.id)", personID: nil, unionID: union.id, into: &issues)
            for event in union.events where event.place?.displayName.isEmpty == false && event.place?.hasValidCoordinates != true {
                issues.append(warning(
                    id: "union.\(union.id).event.\(event.id).unpinned",
                    code: "place.unpinned",
                    title: L10n.tr("Место без координат"),
                    message: L10n.tr("«\(event.place?.displayName ?? "")» не будет показано на карте."),
                    unionID: union.id,
                    field: event.kind.rawValue
                ))
            }
            for citation in union.citations + union.events.flatMap(\.citations) where !sourceIDs.contains(citation.sourceID) {
                issues.append(error(
                    id: "union.\(union.id).citation.\(citation.id).missing-source",
                    code: "citation.missing-source",
                    title: L10n.tr("Источник не найден"),
                    message: L10n.tr("Ссылка доказательства союза указывает на отсутствующий источник."),
                    unionID: union.id,
                    field: "citations"
                ))
            }
        }

        for link in tree.parentLinks {
            for citation in link.citations where !sourceIDs.contains(citation.sourceID) {
                issues.append(error(
                    id: "parent-link.\(link.id).citation.\(citation.id).missing-source",
                    code: "citation.missing-source",
                    title: L10n.tr("Источник не найден"),
                    message: L10n.tr("Ссылка доказательства родства указывает на отсутствующий источник."),
                    personID: link.childID,
                    field: "parentage"
                ))
            }
        }

        addDuplicatePeople(tree, into: &issues)
        if let report = tree.importReport {
            for pointer in report.unresolvedPointers {
                issues.append(warning(
                    id: "gedcom.pointer.\(pointer)",
                    code: "gedcom.unresolved-pointer",
                    title: L10n.tr("Неразрешённая ссылка GEDCOM"),
                    message: L10n.tr("Не найдена запись @\(pointer)@.")
                ))
            }
            for tag in report.preservedUnsupportedTags {
                issues.append(warning(
                    id: "gedcom.unsupported.\(tag)",
                    code: "gedcom.preserved-unsupported",
                    title: L10n.tr("Неподдерживаемая структура сохранена"),
                    message: L10n.tr("Тег \(tag) не редактируется, но будет сохранён при экспорте.")
                ))
            }
            for path in report.missingMedia {
                issues.append(warning(
                    id: "gedcom.media.missing.\(path)",
                    code: "file.missing",
                    title: L10n.tr("Медиа GEDCOM не найдено"),
                    message: L10n.tr("Импортированный файл ссылается на отсутствующий путь «\(path)».")
                ))
            }
        }

        return issues.map { issue in
            var result = issue
            result.isBlocking = issue.severity == .error && !context.acceptedBaselineIssueIDs.contains(issue.id)
            return result
        }.sorted {
            if $0.isBlocking != $1.isBlocking { return $0.isBlocking && !$1.isBlocking }
            if $0.severity != $1.severity { return $0.severity == .error }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private static func addDuplicateIDs(
        _ ids: [UUID],
        kind: String,
        title: String,
        to issues: inout [TreeIssue]
    ) {
        var counts: [UUID: Int] = [:]
        for id in ids {
            counts[id, default: 0] += 1
            guard counts[id, default: 0] > 1 else { continue }
            issues.append(error(
                id: "id.duplicate.\(kind).\(id).occurrence.\(counts[id, default: 0])",
                code: "identity.duplicate",
                title: title,
                message: L10n.tr("Идентификатор \(id.uuidString) используется более одного раза.")
            ))
        }
    }

    private static func addSimilarSources(_ sources: [SourceRecord], into issues: inout [TreeIssue]) {
        var groups: [String: [SourceRecord]] = [:]
        for source in sources {
            let key = source.title.lowercased()
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
                .replacingOccurrences(of: "ё", with: "е")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !key.isEmpty { groups[key, default: []].append(source) }
        }
        for (key, candidates) in groups where candidates.count > 1 && Set(candidates.map(\.title)).count > 1 {
            issues.append(warning(
                id: "source.possible-duplicate.\(key)",
                code: "source.possible-duplicate",
                title: L10n.tr("Похожие источники"),
                message: candidates.map(\.title).joined(separator: ", "),
                field: "sources"
            ))
        }
    }

    private static func validateDates(
        _ events: [GenealogyEvent],
        owner: String,
        personID: UUID?,
        unionID: UUID?,
        into issues: inout [TreeIssue]
    ) {
        for event in events {
            guard let date = event.date, !date.isValid else { continue }
            issues.append(error(
                id: "\(owner).event.\(event.id).invalid-date.\(date.rawValue)",
                code: "date.invalid",
                title: L10n.tr("Некорректная дата"),
                message: L10n.tr("Дата «\(date.rawValue)» не соответствует календарю или диапазону."),
                personID: personID,
                unionID: unionID,
                field: event.kind.rawValue
            ))
        }
    }

    private static func validateCoordinates(
        _ events: [GenealogyEvent],
        owner: String,
        personID: UUID?,
        unionID: UUID?,
        into issues: inout [TreeIssue]
    ) {
        for event in events {
            guard let place = event.place, place.latitude != nil || place.longitude != nil,
                  !place.hasValidCoordinates else { continue }
            let latitude = place.latitude.map { String($0) } ?? "nil"
            let longitude = place.longitude.map { String($0) } ?? "nil"
            issues.append(error(
                id: "\(owner).event.\(event.id).invalid-coordinate.\(latitude).\(longitude)",
                code: "place.invalid-coordinate",
                title: L10n.tr("Некорректные координаты"),
                message: L10n.tr("Широта должна быть от −90 до 90, долгота — от −180 до 180."),
                personID: personID,
                unionID: unionID,
                field: event.kind.rawValue
            ))
        }
    }

    private static func validateChronology(_ person: Person, into issues: inout [TreeIssue]) {
        guard let birth = person.event(ofKind: .birth)?.date?.year,
              let death = person.event(ofKind: .death)?.date?.year else { return }
        if death < birth {
            issues.append(warning(
                id: "person.\(person.id).chronology.death-before-birth",
                code: "chronology.death-before-birth",
                title: L10n.tr("Хронология требует проверки"),
                message: L10n.tr("Год смерти раньше года рождения."),
                personID: person.id,
                field: "death"
            ))
        } else if death - birth > 125 {
            issues.append(warning(
                id: "person.\(person.id).chronology.age-over-125",
                code: "chronology.unusual-lifespan",
                title: L10n.tr("Необычная продолжительность жизни"),
                message: L10n.tr("Разница между годами рождения и смерти превышает 125 лет."),
                personID: person.id,
                field: "death"
            ))
        }
    }

    private static func ancestryCycles(_ tree: FamilyTree) -> [[UUID]] {
        var parentsByChild: [UUID: [UUID]] = [:]
        let links = tree.parentLinks.isEmpty ? tree.unions.flatMap { union in
            union.childrenIds.flatMap { child in union.partnerIds.map { ($0, child) } }
        } : tree.parentLinks.map { ($0.parentID, $0.childID) }
        for (parent, child) in links { parentsByChild[child, default: []].append(parent) }

        var visiting = Set<UUID>()
        var visited = Set<UUID>()
        var stack: [UUID] = []
        var signatures = Set<String>()
        var cycles: [[UUID]] = []
        func visit(_ node: UUID) {
            if visiting.contains(node), let start = stack.firstIndex(of: node) {
                let cycle = Array(stack[start...])
                let signature = cycle.map(\.uuidString).sorted().joined(separator: ".")
                if signatures.insert(signature).inserted { cycles.append(cycle) }
                return
            }
            guard !visited.contains(node) else { return }
            visiting.insert(node); stack.append(node)
            for parent in parentsByChild[node] ?? [] { visit(parent) }
            _ = stack.popLast(); visiting.remove(node); visited.insert(node)
        }
        for person in tree.people { visit(person.id) }
        return cycles
    }

    private static func addDuplicatePeople(_ tree: FamilyTree, into issues: inout [TreeIssue]) {
        var groups: [String: [Person]] = [:]
        for person in tree.people {
            let name = person.fullName.lowercased()
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
                .replacingOccurrences(of: "ё", with: "е")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let year = person.event(ofKind: .birth)?.date?.year.map(String.init) ?? "?"
            groups["\(name)|\(year)", default: []].append(person)
        }
        for (key, people) in groups where people.count > 1 {
            issues.append(warning(
                id: "duplicate-person.\(key)",
                code: "person.possible-duplicate",
                title: L10n.tr("Возможные дубликаты"),
                message: people.map(\.listName).joined(separator: ", "),
                personID: people.first?.id,
                field: "identity"
            ))
        }
    }

    private static func error(
        id: String,
        code: String,
        title: String,
        message: String,
        personID: UUID? = nil,
        unionID: UUID? = nil,
        field: String? = nil
    ) -> TreeIssue {
        TreeIssue(
            id: id, code: code, severity: .error, title: title, message: message,
            personID: personID, unionID: unionID, field: field, isBlocking: true
        )
    }

    private static func warning(
        id: String,
        code: String,
        title: String,
        message: String,
        personID: UUID? = nil,
        unionID: UUID? = nil,
        field: String? = nil
    ) -> TreeIssue {
        TreeIssue(
            id: id, code: code, severity: .warning, title: title, message: message,
            personID: personID, unionID: unionID, field: field, isBlocking: false
        )
    }
}
