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
    @State private var birthPlace = ""
    @State private var deathDate = ""
    @State private var deathPlace = ""
    @State private var isLiving = true
    @State private var burialPlace = ""
    @State private var burialCoords = ""
    @State private var occupation = ""
    @State private var education = ""
    @State private var notes = ""
    
    @State private var relType: RelType = .none
    @State private var relatedPersonId: UUID?
    
    // Action-based, from the perspective of the NEW person being added.
    // "Кто" selects the existing person who plays the named role.
    enum RelType: String, CaseIterable {
        case none = "Без связи"
        case parent = "Добавить родителя"
        case spouse = "Добавить супруга/у"
        case child = "Добавить ребёнка"
        case sibling = "Добавить брата/сестру"
    }
    
    var body: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()
            
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
                        PlacePickerField(label: "МЕСТО", text: $birthPlace, placeholder: "Город, область, страна").padding(.bottom, 12)
                        
                        SectionHeader(title: "Смерть и погребение")
                        Toggle(isOn: $isLiving) {
                            Text("Жив(а)").font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.ink)
                        }.toggleStyle(.checkbox).padding(.bottom, 8)
                        
                        if !isLiving {
                            SepiaDateField(label: "ДАТА", text: $deathDate).padding(.bottom, 8)
                            PlacePickerField(label: "МЕСТО", text: $deathPlace, placeholder: "—").padding(.bottom, 8)
                            PlacePickerField(label: "МЕСТО ЗАХОРОНЕНИЯ", text: $burialPlace, placeholder: "—").padding(.bottom, 8)
                            SepiaTextField(label: "КООРДИНАТЫ МОГИЛЫ", text: $burialCoords, placeholder: "напр. 55.7558, 37.6173").padding(.bottom, 12)
                        }
                        
                        SectionHeader(title: "Жизнь")
                        SepiaTextField(label: "ПРОФЕССИЯ", text: $occupation, placeholder: "—").padding(.bottom, 8)
                        SepiaTextField(label: "ОБРАЗОВАНИЕ", text: $education, placeholder: "—").padding(.bottom, 8)
                        SepiaNotesField(label: "ЗАМЕТКИ", text: $notes, placeholder: "Свободный текст…").padding(.bottom, 12)

                        SectionHeader(title: "Родство")
                        Picker("", selection: $relType) {
                            ForEach(RelType.allCases, id: \.rawValue) { t in Text(t.rawValue).tag(t) }
                        }.labelsHidden().pickerStyle(.menu).font(SepiaTheme.body(size: 13)).padding(.bottom, 8)

                        if relType != .none && !tree.people.isEmpty {
                            Picker("Кто:", selection: $relatedPersonId) {
                                Text("Выбрать…").tag(nil as UUID?)
                                ForEach(tree.people.sorted { $0.listName.localizedCaseInsensitiveCompare($1.listName) == .orderedAscending }, id: \.id) { p in Text(p.listName).tag(p.id as UUID?) }
                            }.pickerStyle(.menu).font(SepiaTheme.body(size: 13))
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

        if !isLiving, let c = parseGraveCoords(burialCoords) {
            person.burialLat = c.lat
            person.burialLon = c.lon
        }

        tree.people.append(person)
        
        // Links are interpreted from the new person's perspective:
        // the picked person (rpid) plays the named role relative to `person`.
        if let rpid = relatedPersonId, relType != .none {
            switch relType {
            case .spouse:
                // rpid becomes the new person's spouse
                if !tree.unions.contains(where: { $0.partnerIds.contains(rpid) && $0.partnerIds.contains(person.id) }) {
                    // If rpid has a one-partner union (e.g. with children), join it; else new union
                    if let existing = tree.unions.first(where: { $0.partnerIds.contains(rpid) && $0.partnerIds.count == 1 }) {
                        if existing.partner1Id == nil { existing.partner1Id = person.id }
                        else if existing.partner2Id == nil { existing.partner2Id = person.id }
                    } else {
                        let u = Union(partner1Id: rpid, partner2Id: person.id)
                        tree.unions.append(u)
                    }
                }
            case .child:
                // rpid becomes the new person's CHILD → new person is the parent.
                if let existing = tree.unions.first(where: { $0.childrenIds.contains(rpid) }) {
                    // rpid already has a parent union → add new person as the co-parent
                    if existing.partner1Id == nil { existing.partner1Id = person.id }
                    else if existing.partner2Id == nil { existing.partner2Id = person.id }
                    else { existing.childrenIds.append(rpid) } // fallback: shouldn't happen
                } else {
                    let u = Union(partner1Id: person.id, childrenIds: [rpid])
                    tree.unions.append(u)
                }
            case .parent:
                // rpid becomes the new person's PARENT → new person is the child.
                if let existing = tree.unions.first(where: { $0.partnerIds.contains(rpid) }) {
                    existing.childrenIds.append(person.id)
                } else {
                    let u = Union(partner1Id: rpid, childrenIds: [person.id])
                    tree.unions.append(u)
                }
            case .sibling:
                // new person and rpid share parents → add new person to rpid's parent union
                if let existing = tree.unions.first(where: { $0.childrenIds.contains(rpid) }) {
                    existing.childrenIds.append(person.id)
                } else {
                    let u = Union(childrenIds: [rpid, person.id])
                    tree.unions.append(u)
                }
            case .none: break
            }
        }
        
        tree.optimizeRoot()
        tree.updatedAt = Date()
        store.save()
        onAdded(person)
        dismiss()
    }

    /// Parses "lat, lon" (decimal degrees) into a coordinate pair, or nil if invalid.
    private func parseGraveCoords(_ s: String) -> (lat: Double, lon: Double)? {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return (lat, lon)
    }
}
