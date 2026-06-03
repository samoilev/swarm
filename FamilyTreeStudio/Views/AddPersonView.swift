import SwiftUI
import AppKit

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
    @State private var birthPlace = ""
    @State private var birthCoords = ""
    @State private var deathDate = ""
    @State private var deathPlace = ""
    @State private var deathCoords = ""
    @State private var isLiving = true
    @State private var burialPlace = ""
    @State private var burialCoords = ""
    @State private var occupation = ""
    @State private var education = ""
    @State private var notes = ""
    
    // Any number of relatives can be linked at once. Each row names a role (read
    // from the new person's perspective) and an existing person who fills it.
    @State private var pendingRels: [PendingRelation] = []

    struct PendingRelation: Identifiable {
        let id = UUID()
        var kind: RelationKind = .parent
        var personId: UUID? = nil
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
                    Text("Добавить родственника")
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
                        SectionHeader(title: "Личность")
                        HStack(spacing: 12) {
                            SepiaTextField(label: "ФАМИЛИЯ", text: $surname, placeholder: "напр. Иванов")
                            SepiaTextField(label: "ИМЯ", text: $givenNames, placeholder: "напр. Иван")
                            SepiaTextField(label: "ОТЧЕСТВО", text: $patronymic, placeholder: "напр. Петрович")
                        }.padding(.bottom, 12)
                        
                        HStack(spacing: 12) {
                            SepiaTextField(label: "ДЕВИЧЬЯ ФАМИЛИЯ", text: $maidenName, placeholder: "—")
                            VStack(alignment: .leading, spacing: 6) {
                                Text("ПОЛ").font(SepiaTheme.ui(size: 9.5)).tracking(1.5).foregroundColor(SepiaTheme.inkSoft)
                                HStack(spacing: 6) {
                                    ForEach(Person.Sex.allCases, id: \.rawValue) { s in
                                        Button(s.displayName) { sex = s }.buttonStyle(SepiaButtonStyle(isActive: sex == s))
                                    }
                                }
                            }
                        }.padding(.bottom, 12)
                        
                        SectionHeader(title: "Рождение")
                        SepiaDateField(label: "ДАТА", text: $birthDate).padding(.bottom, 8)
                        PlacePickerField(label: "МЕСТО", text: $birthPlace, placeholder: "Город, область, страна") { prefillCoords(for: $0, into: $birthCoords) }.padding(.bottom, 8).zIndex(1)
                        SepiaTextField(label: "КООРДИНАТЫ", text: $birthCoords, placeholder: "напр. 55.7558, 37.6173").padding(.bottom, 12)
                        
                        SectionHeader(title: "Смерть и погребение")
                        Toggle(isOn: $isLiving) {
                            Text("Жив(а)").font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.ink)
                        }.toggleStyle(.checkbox).padding(.bottom, 8)
                        
                        if !isLiving {
                            SepiaDateField(label: "ДАТА", text: $deathDate).padding(.bottom, 8)
                            PlacePickerField(label: "МЕСТО СМЕРТИ", text: $deathPlace, placeholder: "—") { prefillCoords(for: $0, into: $deathCoords) }.padding(.bottom, 8).zIndex(1)
                            SepiaTextField(label: "КООРДИНАТЫ", text: $deathCoords, placeholder: "напр. 55.7558, 37.6173").padding(.bottom, 8)
                            SepiaTextField(label: "МЕСТО ЗАХОРОНЕНИЯ", text: $burialPlace, placeholder: "—").padding(.bottom, 8)
                            SepiaTextField(label: "КООРДИНАТЫ МОГИЛЫ", text: $burialCoords, placeholder: "напр. 55.7558, 37.6173").padding(.bottom, 12)
                        }
                        
                        SectionHeader(title: "Жизнь")
                        SepiaTextField(label: "ПРОФЕССИЯ", text: $occupation, placeholder: "—").padding(.bottom, 8)
                        SepiaTextField(label: "ОБРАЗОВАНИЕ", text: $education, placeholder: "—").padding(.bottom, 8)
                        SepiaNotesField(label: "ЗАМЕТКИ", text: $notes, placeholder: "Свободный текст…").padding(.bottom, 12)

                        SectionHeader(title: "Родственные связи")
                        if tree.people.isEmpty {
                            Text("Добавьте людей в дерево, чтобы создавать связи")
                                .font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.inkSoft)
                        } else {
                            ForEach($pendingRels) { $rel in
                                HStack(spacing: 8) {
                                    Picker("", selection: $rel.kind) {
                                        ForEach(RelationKind.allCases) { k in Text(k.displayName).tag(k) }
                                    }.labelsHidden().pickerStyle(.menu).frame(width: 130)
                                    Picker("", selection: $rel.personId) {
                                        Text("Выбрать…").tag(nil as UUID?)
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
                                Label("Добавить связь", systemImage: "plus")
                            }.buttonStyle(SepiaButtonStyle()).padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 20)
                }
                
                Divider().overlay(SepiaTheme.toolbarLine)
                
                HStack {
                    Button("Отмена") { dismiss() }.buttonStyle(SepiaButtonStyle())
                    Spacer()
                    Button("Добавить") { addPerson() }
                        .buttonStyle(SepiaButtonStyle(isActive: true))
                        .disabled(givenNames.isEmpty && surname.isEmpty)
                }
                .padding(16)
            }
        }
        .frame(width: 540, height: 680)
    }
    
    private func addPerson() {
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

        if let c = parseGraveCoords(birthCoords) {
            person.birthLat = c.lat
            person.birthLon = c.lon
        }
        if !isLiving, let c = parseGraveCoords(deathCoords) {
            person.deathLat = c.lat
            person.deathLon = c.lon
        }
        if !isLiving, let c = parseGraveCoords(burialCoords) {
            person.burialLat = c.lat
            person.burialLon = c.lon
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
        store.save()
        onAdded(person)
        dismiss()
    }

    /// Resolve a picked place to coordinates and fill the bound field. Only fires when
    /// a suggestion is chosen from the list, so manual entries keep their manual coords.
    private func prefillCoords(for place: String, into coords: Binding<String>) {
        GeocodingService.shared.coordinate(for: place) { coord in
            DispatchQueue.main.async {
                if let c = coord { coords.wrappedValue = String(format: "%.5f, %.5f", c.latitude, c.longitude) }
            }
        }
    }

    /// Parses "lat, lon" (decimal degrees) into a coordinate pair, or nil if invalid.
    private func parseGraveCoords(_ s: String) -> (lat: Double, lon: Double)? {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return (lat, lon)
    }
}
