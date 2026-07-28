import AppKit
import SwarmCore
import SwiftUI

struct AddPersonView: View {
    @Environment(\.dismiss) private var dismiss
    var tree: FamilyTree
    var store: TreeStore
    let onAdded: (Person) -> Void

    @State private var givenNames = ""
    @State private var patronymic = ""
    @State private var surname = ""
    @State private var maidenName = ""
    @State private var sex: Person.Sex = .unknown
    @State private var birthDate = ""
    @State private var birthDateEnd = ""
    @State private var birthQualifier: GenealogyDate.Qualifier = .exact
    @State private var birthPlace = ""
    @State private var birthCoords = ""
    @State private var selectedBirthPlace: PlaceEntry?
    @State private var deathDate = ""
    @State private var deathDateEnd = ""
    @State private var deathQualifier: GenealogyDate.Qualifier = .exact
    @State private var deathPlace = ""
    @State private var deathCoords = ""
    @State private var selectedDeathPlace: PlaceEntry?
    @State private var isLiving = true
    @State private var burialPlace = ""
    @State private var burialCoords = ""
    @State private var selectedBurialPlace: PlaceEntry?
    @State private var occupation = ""
    @State private var education = ""
    @State private var notes = ""
    @State private var saveError: String?
    @State private var isSaving = false

    /// Any number of relatives can be linked at once. Each row names a role (read
    /// from the new person's perspective) and an existing person who fills it.
    @State private var pendingRels: [PendingRelation] = []

    struct PendingRelation: Identifiable {
        let id = UUID()
        var kind: RelationKind = .parent
        var personId: UUID?
    }

    private var sortedPeople: [Person] {
        tree.people.sorted { $0.listName.localizedCaseInsensitiveCompare($1.listName) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) } // tap empty space → close dropdowns

            VStack(spacing: 0) {
                HStack {
                    Text(L10n.tr("Добавить родственника"))
                        .font(SepiaTheme.display(size: 22))
                        .foregroundColor(SepiaTheme.ink)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundColor(SepiaTheme.inkSoft)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)

                Divider().overlay(SepiaTheme.toolbarLine)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: L10n.tr("Личность"))
                        HStack(spacing: 12) {
                            SepiaTextField(label: L10n.tr("ФАМИЛИЯ"), text: $surname, placeholder: L10n.tr("напр. Иванов"))
                            SepiaTextField(label: L10n.tr("ИМЯ"), text: $givenNames, placeholder: L10n.tr("напр. Иван"))
                            SepiaTextField(label: L10n.tr("ОТЧЕСТВО"), text: $patronymic, placeholder: L10n.tr("напр. Петрович"))
                        }.padding(.bottom, 12)

                        HStack(spacing: 12) {
                            SepiaTextField(label: L10n.tr("ДЕВИЧЬЯ ФАМИЛИЯ"), text: $maidenName, placeholder: "—")
                            VStack(alignment: .leading, spacing: 6) {
                                SepiaFieldLabel(L10n.tr("ПОЛ"), isDecorative: false)
                                // Two toggles, not three choices: an unanswered field
                                // used to render "Не указан" in the same filled style as
                                // a deliberate answer, so nobody could tell the two apart.
                                HStack(spacing: 6) {
                                    ForEach([Person.Sex.male, .female], id: \.rawValue) { option in
                                        Button(option.displayName) { sex = (sex == option) ? .unknown : option }
                                            .buttonStyle(SepiaButtonStyle(isActive: sex == option))
                                            .accessibilityAddTraits(sex == option ? [.isSelected] : [])
                                    }
                                    if sex == .unknown {
                                        Text(Person.Sex.unknown.displayName)
                                            .font(SepiaTheme.ui(size: 11.5))
                                            .foregroundColor(SepiaTheme.inkSoft)
                                            .padding(.leading, 2)
                                    }
                                }
                            }
                        }.padding(.bottom, 12)

                        SectionHeader(title: L10n.tr("Рождение"))
                        SepiaDateField(
                            label: L10n.tr("ДАТА"),
                            text: $birthDate,
                            qualifier: $birthQualifier,
                            endText: $birthDateEnd
                        ).padding(.bottom, 8)
                        PlacePickerField(label: L10n.tr("МЕСТО"), text: $birthPlace, placeholder: L10n.tr("Город, область, страна")) {
                            selectedBirthPlace = $0
                            prefillCoords(for: $0, into: $birthCoords)
                        }.padding(.bottom, 8).zIndex(1)
                        SepiaTextField(label: L10n.tr("КООРДИНАТЫ"), text: $birthCoords, placeholder: L10n.tr("напр. 55.7558, 37.6173")).padding(.bottom, 12)

                        SectionHeader(title: L10n.tr("Смерть и погребение"))
                        Toggle(isOn: $isLiving) {
                            Text(L10n.tr("Жив(а)")).font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.ink)
                        }.toggleStyle(.checkbox).padding(.bottom, 8)

                        if !isLiving {
                            SepiaDateField(
                                label: L10n.tr("ДАТА"),
                                text: $deathDate,
                                qualifier: $deathQualifier,
                                endText: $deathDateEnd
                            ).padding(.bottom, 8)
                            PlacePickerField(label: L10n.tr("МЕСТО СМЕРТИ"), text: $deathPlace, placeholder: "—") {
                                selectedDeathPlace = $0
                                prefillCoords(for: $0, into: $deathCoords)
                            }.padding(.bottom, 8).zIndex(1)
                            SepiaTextField(label: L10n.tr("КООРДИНАТЫ"), text: $deathCoords, placeholder: L10n.tr("напр. 55.7558, 37.6173")).padding(.bottom, 8)
                            PlacePickerField(label: L10n.tr("МЕСТО ЗАХОРОНЕНИЯ"), text: $burialPlace, placeholder: "—") {
                                selectedBurialPlace = $0
                                prefillCoords(for: $0, into: $burialCoords)
                            }.padding(.bottom, 8).zIndex(1)
                            SepiaTextField(label: L10n.tr("КООРДИНАТЫ МОГИЛЫ"), text: $burialCoords, placeholder: L10n.tr("напр. 55.7558, 37.6173")).padding(.bottom, 12)
                        }

                        SectionHeader(title: L10n.tr("Жизнь"))
                        SepiaTextField(label: L10n.tr("ПРОФЕССИЯ"), text: $occupation, placeholder: "—").padding(.bottom, 8)
                        SepiaTextField(label: L10n.tr("ОБРАЗОВАНИЕ"), text: $education, placeholder: "—").padding(.bottom, 8)
                        SepiaNotesField(label: L10n.tr("ЗАМЕТКИ"), text: $notes, placeholder: L10n.tr("Свободный текст…")).padding(.bottom, 12)

                        SectionHeader(title: L10n.tr("Родственные связи"))
                        if tree.people.isEmpty {
                            Text(L10n.tr("Добавьте людей в дерево, чтобы создавать связи"))
                                .font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.inkSoft)
                        } else {
                            ForEach($pendingRels) { $rel in
                                HStack(spacing: 8) {
                                    Picker("", selection: $rel.kind) {
                                        ForEach(RelationKind.allCases) { k in Text(k.displayName).tag(k) }
                                    }.labelsHidden().pickerStyle(.menu).frame(width: 130)
                                    Picker("", selection: $rel.personId) {
                                        Text(L10n.tr("Выбрать…")).tag(nil as UUID?)
                                        ForEach(sortedPeople, id: \.id) { p in Text(p.listName).tag(p.id as UUID?) }
                                    }.labelsHidden().pickerStyle(.menu)
                                    Button { pendingRels.removeAll { $0.id == rel.id } } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 14)).foregroundColor(.red.opacity(0.7))
                                            .frame(width: 24, height: 24).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                                .font(SepiaTheme.body(size: 13))
                                .padding(.bottom, 6)
                            }
                            Button { pendingRels.append(PendingRelation()) } label: {
                                Label(L10n.tr("Добавить связь"), systemImage: "plus")
                            }.buttonStyle(SepiaButtonStyle()).padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 20)
                }

                Divider().overlay(SepiaTheme.toolbarLine)

                HStack {
                    Button(L10n.tr("Отмена")) { dismiss() }.buttonStyle(SepiaButtonStyle())
                    Spacer()
                    Button(L10n.tr("Добавить")) { addPerson() }
                        .buttonStyle(SepiaButtonStyle(isActive: true))
                        .disabled(isSaving)
                        .disabled(givenNames.isEmpty && surname.isEmpty)
                }
                .padding(16)
            }
        }
        .frame(width: 540, height: 680)
        .alert(L10n.tr("Не удалось добавить персону"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func addPerson() {
        let parsedBirth = parsedDate(text: birthDate, end: birthDateEnd, qualifier: birthQualifier)
        let parsedDeath = isLiving ? nil : parsedDate(text: deathDate, end: deathDateEnd, qualifier: deathQualifier)
        guard birthDate.isEmpty || parsedBirth != nil,
              isLiving || deathDate.isEmpty || parsedDeath != nil else {
            saveError = L10n.tr("Исправьте некорректные даты перед сохранением.")
            return
        }
        guard validCoordinateText(birthCoords), validCoordinateText(deathCoords), validCoordinateText(burialCoords) else {
            saveError = L10n.tr("Координаты должны иметь формат «широта, долгота» и находиться в допустимом диапазоне.")
            return
        }
        let before = try? JSONEncoder().encode(tree)
        let person = Person(
            givenNames: givenNames,
            patronymic: patronymic.isEmpty ? nil : patronymic,
            surname: surname,
            maidenName: maidenName.isEmpty ? nil : maidenName, sex: sex,
            birthDate: birthDate.isEmpty ? nil : FamilyDate.normalize(birthDate),
            birthPlace: birthPlace.isEmpty ? nil : birthPlace,
            deathDate: isLiving ? nil : (deathDate.isEmpty ? nil : FamilyDate.normalize(deathDate)),
            deathPlace: isLiving ? nil : (deathPlace.isEmpty ? nil : deathPlace),
            isLiving: isLiving,
            burialPlace: burialPlace.isEmpty ? nil : burialPlace,
            occupation: occupation.isEmpty ? nil : occupation,
            education: education.isEmpty ? nil : education,
            notes: notes.isEmpty ? nil : notes
        )
        person.setStructuredDate(parsedBirth, for: .birth)
        person.setStructuredDate(parsedDeath, for: .death)

        if let c = parseGraveCoords(birthCoords) {
            person.birthLat = c.lat
            person.birthLon = c.lon
        }
        if let selectedBirthPlace, selectedBirthPlace.displayName == birthPlace {
            person.setStructuredPlace(selectedBirthPlace.placeReference, for: .birth)
        }
        if !isLiving, let c = parseGraveCoords(deathCoords) {
            person.deathLat = c.lat
            person.deathLon = c.lon
        }
        if !isLiving, let selectedDeathPlace, selectedDeathPlace.displayName == deathPlace {
            person.setStructuredPlace(selectedDeathPlace.placeReference, for: .death)
        }
        if !isLiving, let c = parseGraveCoords(burialCoords) {
            person.burialLat = c.lat
            person.burialLon = c.lon
        }
        if !isLiving, let selectedBurialPlace, selectedBurialPlace.displayName == burialPlace {
            person.setStructuredPlace(selectedBurialPlace.placeReference, for: .burial)
        }

        tree.people.append(person)

        // Apply all chosen relationships (parents before siblings, spouses before
        // children) so multiple relatives merge into shared unions correctly.
        for rel in pendingRels.sorted(by: { $0.kind.applyOrder < $1.kind.applyOrder }) {
            guard let targetId = rel.personId else { continue }
            tree.addRelation(rel.kind, person: person, target: targetId)
        }

        tree.optimizeRoot()
        tree.updatedAt = Date()
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                _ = try await store.saveTree(tree)
                onAdded(person)
                dismiss()
            } catch {
                if let before, let snapshot = try? JSONDecoder().decode(FamilyTree.self, from: before) {
                    tree.people = snapshot.people
                    tree.unions = snapshot.unions
                    tree.sourceRecords = snapshot.sourceRecords
                    tree.parentLinks = snapshot.parentLinks
                    tree.homePersonId = snapshot.homePersonId
                    tree.rootUnionId = snapshot.rootUnionId
                    tree.layoutVersion += 1
                    store.refreshMediaFolders(for: tree)
                }
                saveError = error.localizedDescription
            }
        }
    }

    /// Resolve a picked place to coordinates and fill the bound field. Only fires when
    /// a suggestion is chosen from the list, so manual entries keep their manual coords.
    private func prefillCoords(for place: PlaceEntry, into coords: Binding<String>) {
        if let c = GeocodingService.shared.coordinate(for: place) {
            coords.wrappedValue = String(format: "%.5f, %.5f", c.latitude, c.longitude)
        }
    }

    /// Parses "lat, lon" (decimal degrees) into a coordinate pair, or nil if invalid.
    private func parseGraveCoords(_ s: String) -> (lat: Double, lon: Double)? {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return (lat, lon)
    }

    private func parsedDate(
        text: String,
        end: String,
        qualifier: GenealogyDate.Qualifier
    ) -> GenealogyDate? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let range = qualifier == .between || qualifier == .fromTo
        let value = GenealogyDate(userInput: text, qualifier: qualifier, endValue: range ? end : nil)
        return value.isValid ? value : nil
    }

    private func validCoordinateText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let coordinates = parseGraveCoords(trimmed) else { return false }
        return (-90 ... 90).contains(coordinates.lat) && (-180 ... 180).contains(coordinates.lon)
    }
}
