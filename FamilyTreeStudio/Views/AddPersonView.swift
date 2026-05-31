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
    @State private var occupation = ""
    @State private var education = ""
    @State private var notes = ""
    
    @State private var relType: RelType = .none
    @State private var relatedPersonId: UUID?
    
    enum RelType: String, CaseIterable {
        case none = "Нет (отдельно)"
        case child = "Ребёнок…"
        case parent = "Родитель…"
        case spouse = "Супруг/а…"
        case sibling = "Брат/сестра…"
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
                            SepiaTextField(label: "ИМЕНА", text: $givenNames, placeholder: "напр. Иван")
                            SepiaTextField(label: "ОТЧЕСТВО", text: $patronymic, placeholder: "напр. Петрович")
                            SepiaTextField(label: "ФАМИЛИЯ", text: $surname, placeholder: "напр. Иванов")
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
                        SepiaTextField(label: "ДАТА", text: $birthDate, placeholder: "ДД.ММ.ГГГГ").padding(.bottom, 8)
                        PlacePickerField(label: "МЕСТО", text: $birthPlace, placeholder: "Город, область, страна").padding(.bottom, 12)
                        
                        SectionHeader(title: "Смерть и погребение")
                        Toggle(isOn: $isLiving) {
                            Text("Жив(а)").font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.ink)
                        }.toggleStyle(.checkbox).padding(.bottom, 8)
                        
                        if !isLiving {
                            SepiaTextField(label: "ДАТА", text: $deathDate, placeholder: "ДД.ММ.ГГГГ").padding(.bottom, 8)
                            PlacePickerField(label: "МЕСТО", text: $deathPlace, placeholder: "—").padding(.bottom, 8)
                            PlacePickerField(label: "МЕСТО ЗАХОРОНЕНИЯ", text: $burialPlace, placeholder: "—").padding(.bottom, 12)
                        }
                        
                        SectionHeader(title: "Жизнь")
                        SepiaTextField(label: "ПРОФЕССИЯ", text: $occupation, placeholder: "—").padding(.bottom, 8)
                        SepiaTextField(label: "ОБРАЗОВАНИЕ", text: $education, placeholder: "—").padding(.bottom, 12)
                        
                        SectionHeader(title: "Родство")
                        Picker("Связать как:", selection: $relType) {
                            ForEach(RelType.allCases, id: \.rawValue) { t in Text(t.rawValue).tag(t) }
                        }.pickerStyle(.menu).font(SepiaTheme.body(size: 13)).padding(.bottom, 8)
                        
                        if relType != .none && !tree.people.isEmpty {
                            Picker("Кто:", selection: $relatedPersonId) {
                                Text("Выбрать…").tag(nil as UUID?)
                                ForEach(tree.people, id: \.id) { p in Text(p.fullName).tag(p.id as UUID?) }
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
        
        tree.people.append(person)
        
        if let rpid = relatedPersonId, relType != .none {
            switch relType {
            case .spouse:
                // Check: already spouses
                if !tree.unions.contains(where: { $0.partnerIds.contains(rpid) && $0.partnerIds.contains(person.id) }) {
                    // If rpid has a union with children but no second partner, add as partner
                    if let existing = tree.unions.first(where: { $0.partnerIds.contains(rpid) && $0.partnerIds.count == 1 }) {
                        if existing.partner1Id == nil { existing.partner1Id = person.id }
                        else if existing.partner2Id == nil { existing.partner2Id = person.id }
                    } else {
                        let u = Union(partner1Id: rpid, partner2Id: person.id)
                        tree.unions.append(u)
                    }
                }
            case .child:
                if let existing = tree.unions.first(where: { $0.partnerIds.contains(rpid) }) {
                    existing.childrenIds.append(person.id)
                } else {
                    let u = Union(partner1Id: rpid, childrenIds: [person.id])
                    tree.unions.append(u)
                }
            case .parent:
                if let existing = tree.unions.first(where: { $0.childrenIds.contains(rpid) }) {
                    if existing.partner1Id == nil { existing.partner1Id = person.id }
                    else if existing.partner2Id == nil { existing.partner2Id = person.id }
                } else {
                    let u = Union(partner1Id: person.id, childrenIds: [rpid])
                    tree.unions.append(u)
                }
            case .sibling:
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
}
