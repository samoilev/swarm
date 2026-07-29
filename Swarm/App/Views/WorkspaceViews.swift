import SwarmCore
import SwiftUI

struct PeopleWorkspaceView: View {
    let tree: FamilyTree
    let index: TreeWorkspaceIndexes
    @Binding var selectedPerson: Person?
    let onEdit: (Person) -> Void

    @State private var query = ""
    @State private var missingOnly = false
    @State private var selectedPlace = ""
    @State private var sort: Sort = .name

    enum Sort: CaseIterable, Identifiable {
        case name, birth, death
        var id: Self { self }
        var displayName: String {
            switch self {
            case .name: L10n.tr("По имени")
            case .birth: L10n.tr("По рождению")
            case .death: L10n.tr("По смерти")
            }
        }
    }

    private var entries: [PersonSearchEntry] {
        let normalized = TreeWorkspaceIndexes.normalize(query)
        var result = index.searchEntries.filter { entry in
            (normalized.isEmpty || entry.normalizedText.contains(normalized)) &&
                (!missingOnly || entry.hasMissingData) &&
                (selectedPlace.isEmpty || entry.places.contains(selectedPlace))
        }
        switch sort {
        case .name: break
        case .birth: result.sort { ($0.birthYear ?? Int.max, $0.displayName) < ($1.birthYear ?? Int.max, $1.displayName) }
        case .death: result.sort { ($0.deathYear ?? Int.max, $0.displayName) < ($1.deathYear ?? Int.max, $1.displayName) }
        }
        return result
    }

    var body: some View {
        workspaceSurface(title: L10n.tr("Люди"), count: entries.count) {
            HStack(spacing: 10) {
                TextField(L10n.tr("Имя, дата или место"), text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Picker(L10n.tr("Сортировка"), selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.displayName).tag($0) }
                }.frame(width: 160)
                Picker(L10n.tr("Место"), selection: $selectedPlace) {
                    Text(L10n.tr("Все места")).tag("")
                    ForEach(Array(Set(index.searchEntries.flatMap(\.places))).sorted(), id: \.self) { Text($0).tag($0) }
                }.frame(width: 200)
                Toggle(L10n.tr("Только неполные"), isOn: $missingOnly)
            }
        } content: {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    if let person = tree.person(byId: entry.personID) {
                        Button { selectedPerson = person } label: {
                            HStack(spacing: 14) {
                                Image(systemName: person.sex == .male ? "person.fill" : person.sex == .female ? "person.fill" : "person")
                                    .foregroundStyle(SepiaTheme.accent2).frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.displayName).font(SepiaTheme.body(size: 15)).foregroundStyle(SepiaTheme.ink)
                                    Text(lifeSummary(entry)).font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                                }
                                Spacer()
                                if entry.hasMissingData { Label(L10n.tr("Есть пропуски"), systemImage: "exclamationmark.circle").font(SepiaTheme.ui(size: 10)).foregroundStyle(SepiaTheme.accent) }
                                Menu {
                                    Button { onEdit(person) } label: {
                                        Label(L10n.tr("Редактировать"), systemImage: "pencil")
                                    }
                                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(SepiaTheme.inkSoft) }
                                    .menuStyle(.borderlessButton).fixedSize()
                            }
                            .padding(.horizontal, 18).frame(height: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(SepiaTheme.cardLine)
                    }
                }
            }
        }
    }

    private func lifeSummary(_ entry: PersonSearchEntry) -> String {
        let years = [entry.birthYear.map(String.init), entry.deathYear.map(String.init)].compactMap { $0 }.joined(separator: "–")
        return ([years] + entry.places.prefix(2)).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct TimelineWorkspaceView: View {
    let tree: FamilyTree
    let index: TreeWorkspaceIndexes
    @Binding var selectedPerson: Person?
    @State private var query = ""
    @State private var kind: GenealogyEvent.Kind?
    @State private var fromYear = ""
    @State private var toYear = ""

    private var entries: [TimelineEntry] {
        index.timelineEntries.filter { entry in
            (query.isEmpty
                || entry.personName.localizedStandardContains(query)
                || presentedPlace(entry.place)?.localizedStandardContains(query) == true) &&
                (kind == nil || entry.kind == kind) &&
                (Int(fromYear).map { (entry.sortYear ?? Int.min) >= $0 } ?? true) &&
                (Int(toYear).map { (entry.sortYear ?? Int.max) <= $0 } ?? true)
        }
    }

    var body: some View {
        workspaceSurface(title: L10n.tr("Хронология"), count: entries.count) {
            HStack(spacing: 10) {
                TextField(L10n.tr("Персона или место"), text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                Picker(L10n.tr("Событие"), selection: $kind) {
                    Text(L10n.tr("Все события")).tag(nil as GenealogyEvent.Kind?)
                    ForEach(GenealogyEvent.Kind.allCases, id: \.self) { Text(eventName($0)).tag($0 as GenealogyEvent.Kind?) }
                }.frame(width: 180)
                TextField(L10n.tr("С года"), text: $fromYear).textFieldStyle(.roundedBorder).frame(width: 80)
                TextField(L10n.tr("По год"), text: $toYear).textFieldStyle(.roundedBorder).frame(width: 80)
            }
        } content: {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    Button { selectedPerson = entry.personID.flatMap { tree.person(byId: $0) } } label: {
                        HStack(spacing: 14) {
                            Text(entry.date?.displayValue(language: .current) ?? "—")
                                .font(SepiaTheme.ui(size: 12))
                                .foregroundStyle(SepiaTheme.accent2)
                                .frame(width: 130, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.personName).font(SepiaTheme.body(size: 15)).foregroundStyle(SepiaTheme.ink)
                                Text([eventName(entry.kind), presentedPlace(entry.place)].compactMap { $0 }.joined(separator: " · "))
                                    .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                            }
                            Spacer()
                        }.padding(.horizontal, 18).frame(height: 56).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider().overlay(SepiaTheme.cardLine)
                }
            }
        }
    }

    private func presentedPlace(_ place: PlaceReference?) -> String? {
        guard let place else { return nil }
        return PlacesDatabase.shared.presentationName(for: place, language: .current)
    }
}

struct PlacesWorkspaceView: View {
    let tree: FamilyTree
    let index: TreeWorkspaceIndexes
    @Binding var selectedPerson: Person?
    @State private var query = ""
    @State private var unpinnedOnly = false

    private var entries: [PlaceWorkspaceEntry] {
        index.placeEntries.filter {
            (query.isEmpty || placeName($0.place).localizedCaseInsensitiveContains(query)) &&
                (!unpinnedOnly || !$0.place.hasValidCoordinates)
        }
    }

    var body: some View {
        workspaceSurface(title: L10n.tr("Места"), count: entries.count) {
            HStack(spacing: 12) {
                TextField(L10n.tr("Найти место"), text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Toggle(L10n.tr("Только без координат"), isOn: $unpinnedOnly)
            }
        } content: {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    HStack(spacing: 14) {
                        Image(systemName: entry.place.hasValidCoordinates ? "mappin.circle.fill" : "mappin.slash")
                            .foregroundStyle(entry.place.hasValidCoordinates ? SepiaTheme.pinBirth : SepiaTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(placeName(entry.place))
                                .font(SepiaTheme.body(size: 15))
                                .foregroundStyle(SepiaTheme.ink)
                            Text(
                                "\(L10n.count(entry.eventCount, .event)) · "
                                    + "\(L10n.count(entry.personIDs.count, .person))"
                                    + (entry.place.isCustom ? L10n.tr(" · пользовательское") : "")
                            )
                            .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                        }
                        Spacer()
                        ForEach(entry.personIDs.prefix(3), id: \.self) { id in
                            if let person = tree.person(byId: id) {
                                Button(person.displayName(language: .current)) { selectedPerson = person }
                                    .buttonStyle(.borderless).font(SepiaTheme.ui(size: 11))
                            }
                        }
                    }.padding(.horizontal, 18).frame(height: 58)
                    Divider().overlay(SepiaTheme.cardLine)
                }
            }
        }
    }

    private func placeName(_ place: PlaceReference) -> String {
        PlacesDatabase.shared.presentationName(for: place, language: .current)
    }
}

struct ReviewWorkspaceView: View {
    let tree: FamilyTree
    let index: TreeWorkspaceIndexes
    @Binding var selectedPerson: Person?
    let onEdit: (Person) -> Void
    let onDeleteDuplicate: (Person) -> Void
    @State private var errorsOnly = false

    private var issues: [TreeIssue] { index.issues.filter { !errorsOnly || $0.severity == .error } }
    private var issueGroups: [ReviewIssueGroup] {
        let grouped = Dictionary(grouping: issues) { issue in
            "\(issue.severity.rawValue):\(issue.personID?.uuidString ?? "general")"
        }
        return grouped.map { key, values in
            let personName = values.first?.personID.flatMap {
                tree.person(byId: $0)?.displayName(language: .current)
            } ?? L10n.tr("Общие")
            let severity = values.first?.severity == .error ? L10n.tr("Ошибки") : L10n.tr("Предупреждения")
            return ReviewIssueGroup(id: key, title: "\(severity) · \(personName)", issues: values)
        }.sorted {
            $0.title.compare(
                $1.title,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: AppLanguage.current.locale
            ) == .orderedAscending
        }
    }

    var body: some View {
        workspaceSurface(title: L10n.tr("Проверка"), count: issues.count + index.duplicateSuggestions.count) {
            HStack {
                Toggle(L10n.tr("Только ошибки"), isOn: $errorsOnly)
                Spacer()
                Text(L10n.tr("Ошибки блокируют только новые или ухудшенные изменения."))
                    .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
            }
        } content: {
            LazyVStack(spacing: 0) {
                ForEach(issueGroups) { group in
                    Text(group.title.uppercased())
                        .font(SepiaTheme.ui(size: 9.5)).tracking(1.1).foregroundStyle(SepiaTheme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 14)
                    ForEach(group.issues) { issue in
                        issueRow(issue)
                        Divider().overlay(SepiaTheme.cardLine)
                    }
                }
                ForEach(index.duplicateSuggestions) { suggestion in
                    duplicateRow(suggestion)
                    Divider().overlay(SepiaTheme.cardLine)
                }
            }
        }
    }

    private func issueRow(_ issue: TreeIssue) -> some View {
        Button {
            guard let id = issue.personID, let person = tree.person(byId: id) else { return }
            selectedPerson = person
            onEdit(person)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue.severity == .error ? Color.red.opacity(0.75) : SepiaTheme.accent2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(issue.title).font(SepiaTheme.body(size: 15)); if issue.isBlocking { Text(L10n.tr("БЛОКИРУЕТ")).font(SepiaTheme.ui(size: 9)).foregroundStyle(.red) } }
                    Text(issue.message).font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                    if let field = issue.field {
                        Text(L10n.tr("Открыть поле: \(field)")).font(SepiaTheme.ui(size: 10)).foregroundStyle(SepiaTheme.accent2)
                    }
                    Text(issue.code).font(.system(size: 9, design: .monospaced)).foregroundStyle(SepiaTheme.inkSoft)
                }.foregroundStyle(SepiaTheme.ink)
                Spacer()
            }.padding(16).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func duplicateRow(_ suggestion: DuplicateSuggestion) -> some View {
        let first = tree.person(byId: suggestion.firstPersonID)
        let second = tree.person(byId: suggestion.secondPersonID)
        return HStack(spacing: 12) {
            Image(systemName: "person.2.badge.questionmark").foregroundStyle(SepiaTheme.accent2)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("Возможный дубликат")).font(SepiaTheme.body(size: 15)).foregroundStyle(SepiaTheme.ink)
                Text(
                    "\(first?.displayName(language: .current) ?? "?") · "
                        + "\(second?.displayName(language: .current) ?? "?")"
                )
                .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                Text(suggestion.reasons.joined(separator: ", ")).font(SepiaTheme.ui(size: 10)).foregroundStyle(SepiaTheme.inkSoft)
            }
            Spacer()
            if let first { Button(L10n.tr("Открыть")) { selectedPerson = first }.buttonStyle(.borderless) }
            if let second {
                Button(L10n.tr("Удалить дубликат…"), role: .destructive) { onDeleteDuplicate(second) }
                    .buttonStyle(.borderless)
            }
        }.padding(16)
    }
}

private struct ReviewIssueGroup: Identifiable {
    let id: String
    let title: String
    let issues: [TreeIssue]
}

private func workspaceSurface(
    title: String,
    count: Int,
    @ViewBuilder filters: () -> some View,
    @ViewBuilder content: () -> some View
) -> some View {
    VStack(spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(SepiaTheme.display(size: 24)).foregroundStyle(SepiaTheme.ink)
            Text("\(count)").font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
            Spacer()
        }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
        filters().padding(.horizontal, 20).padding(.bottom, 14)
        Divider().overlay(SepiaTheme.cardLine)
        ScrollView { content() }
    }.background(SepiaTheme.paper)
}

private func eventName(_ kind: GenealogyEvent.Kind) -> String {
    switch kind {
    case .birth: L10n.tr("Рождение")
    case .death: L10n.tr("Смерть")
    case .burial: L10n.tr("Погребение")
    case .occupation: L10n.tr("Занятие")
    case .education: L10n.tr("Образование")
    case .marriage: L10n.tr("Брак")
    case .partnership: L10n.tr("Партнёрство")
    case .separation: L10n.tr("Раздельное проживание")
    case .divorce: L10n.tr("Развод")
    case .residence: L10n.tr("Проживание")
    case .immigration: L10n.tr("Иммиграция")
    case .military: L10n.tr("Военная служба")
    case .custom: L10n.tr("Событие")
    }
}
