import FamilyTreeCore
import SwiftUI

struct PeopleWorkspaceView: View {
    let tree: FamilyTree
    let index: TreeWorkspaceIndexes
    @Binding var selectedPerson: Person?
    let onMakeHome: (Person) -> Void

    @State private var query = ""
    @State private var missingOnly = false
    @State private var selectedPlace = ""
    @State private var sort: Sort = .name

    enum Sort: String, CaseIterable, Identifiable {
        case name = "По имени"
        case birth = "По рождению"
        case death = "По смерти"
        var id: String { rawValue }
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
        workspaceSurface(title: "Люди", count: entries.count) {
            HStack(spacing: 10) {
                TextField("Имя, дата или место", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Picker("Сортировка", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 160)
                Picker("Место", selection: $selectedPlace) {
                    Text("Все места").tag("")
                    ForEach(Array(Set(index.searchEntries.flatMap(\.places))).sorted(), id: \.self) { Text($0).tag($0) }
                }.frame(width: 200)
                Toggle("Только неполные", isOn: $missingOnly)
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
                                if entry.hasMissingData { Label("Есть пропуски", systemImage: "exclamationmark.circle").font(SepiaTheme.ui(size: 10)).foregroundStyle(SepiaTheme.accent) }
                                Menu {
                                    Button("Сделать домашней персоной") { onMakeHome(person) }
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
            (query.isEmpty || entry.personName.localizedStandardContains(query) || entry.place?.displayName.localizedStandardContains(query) == true) &&
                (kind == nil || entry.kind == kind) &&
                (Int(fromYear).map { (entry.sortYear ?? Int.min) >= $0 } ?? true) &&
                (Int(toYear).map { (entry.sortYear ?? Int.max) <= $0 } ?? true)
        }
    }

    var body: some View {
        workspaceSurface(title: "Хронология", count: entries.count) {
            HStack(spacing: 10) {
                TextField("Персона или место", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                Picker("Событие", selection: $kind) {
                    Text("Все события").tag(nil as GenealogyEvent.Kind?)
                    ForEach(GenealogyEvent.Kind.allCases, id: \.self) { Text(eventName($0)).tag($0 as GenealogyEvent.Kind?) }
                }.frame(width: 180)
                TextField("С года", text: $fromYear).textFieldStyle(.roundedBorder).frame(width: 80)
                TextField("По год", text: $toYear).textFieldStyle(.roundedBorder).frame(width: 80)
            }
        } content: {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    Button { selectedPerson = entry.personID.flatMap { tree.person(byId: $0) } } label: {
                        HStack(spacing: 14) {
                            Text(entry.date?.displayValue ?? "—").font(SepiaTheme.ui(size: 12)).foregroundStyle(SepiaTheme.accent2).frame(width: 130, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.personName).font(SepiaTheme.body(size: 15)).foregroundStyle(SepiaTheme.ink)
                                Text([eventName(entry.kind), entry.place?.displayName].compactMap { $0 }.joined(separator: " · "))
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
}

struct PlacesWorkspaceView: View {
    let tree: FamilyTree
    let index: TreeWorkspaceIndexes
    @Binding var selectedPerson: Person?
    @State private var query = ""
    @State private var unpinnedOnly = false

    private var entries: [PlaceWorkspaceEntry] {
        index.placeEntries.filter {
            (query.isEmpty || $0.place.displayName.localizedStandardContains(query)) &&
                (!unpinnedOnly || !$0.place.hasValidCoordinates)
        }
    }

    var body: some View {
        workspaceSurface(title: "Места", count: entries.count) {
            HStack(spacing: 12) {
                TextField("Найти место", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Toggle("Только без координат", isOn: $unpinnedOnly)
            }
        } content: {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    HStack(spacing: 14) {
                        Image(systemName: entry.place.hasValidCoordinates ? "mappin.circle.fill" : "mappin.slash")
                            .foregroundStyle(entry.place.hasValidCoordinates ? SepiaTheme.pinBirth : SepiaTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.place.displayName).font(SepiaTheme.body(size: 15)).foregroundStyle(SepiaTheme.ink)
                            Text("\(entry.eventCount) событ. · \(entry.personIDs.count) чел.\(entry.place.isCustom ? " · пользовательское" : "")")
                                .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                        }
                        Spacer()
                        ForEach(entry.personIDs.prefix(3), id: \.self) { id in
                            if let person = tree.person(byId: id) {
                                Button(person.surname.isEmpty ? person.givenNames : person.surname) { selectedPerson = person }
                                    .buttonStyle(.borderless).font(SepiaTheme.ui(size: 11))
                            }
                        }
                    }.padding(.horizontal, 18).frame(height: 58)
                    Divider().overlay(SepiaTheme.cardLine)
                }
            }
        }
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
            let personName = values.first?.personID.flatMap { tree.person(byId: $0)?.listName } ?? "Общие"
            let severity = values.first?.severity == .error ? "Ошибки" : "Предупреждения"
            return ReviewIssueGroup(id: key, title: "\(severity) · \(personName)", issues: values)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        workspaceSurface(title: "Проверка", count: issues.count + index.duplicateSuggestions.count) {
            HStack {
                Toggle("Только ошибки", isOn: $errorsOnly)
                Spacer()
                Text("Ошибки блокируют только новые или ухудшенные изменения.")
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
                    HStack { Text(issue.title).font(SepiaTheme.body(size: 15)); if issue.isBlocking { Text("БЛОКИРУЕТ").font(SepiaTheme.ui(size: 9)).foregroundStyle(.red) } }
                    Text(issue.message).font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                    if let field = issue.field {
                        Text("Открыть поле: \(field)").font(SepiaTheme.ui(size: 10)).foregroundStyle(SepiaTheme.accent2)
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
                Text("Возможный дубликат").font(SepiaTheme.body(size: 15)).foregroundStyle(SepiaTheme.ink)
                Text("\(first?.listName ?? "?") · \(second?.listName ?? "?")")
                    .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                Text(suggestion.reasons.joined(separator: ", ")).font(SepiaTheme.ui(size: 10)).foregroundStyle(SepiaTheme.inkSoft)
            }
            Spacer()
            if let first { Button("Открыть") { selectedPerson = first }.buttonStyle(.borderless) }
            if let second {
                Button("Удалить дубликат…", role: .destructive) { onDeleteDuplicate(second) }
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
    case .birth: "Рождение"
    case .death: "Смерть"
    case .burial: "Погребение"
    case .occupation: "Занятие"
    case .education: "Образование"
    case .marriage: "Брак"
    case .partnership: "Партнёрство"
    case .separation: "Раздельное проживание"
    case .divorce: "Развод"
    case .residence: "Проживание"
    case .immigration: "Иммиграция"
    case .military: "Военная служба"
    case .custom: "Событие"
    }
}
