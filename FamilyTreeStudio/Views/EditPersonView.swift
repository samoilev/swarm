import SwiftUI
import UniformTypeIdentifiers

struct EditPersonView: View {
    @Environment(\.dismiss) private var dismiss
    let person: Person
    var tree: FamilyTree
    var store: TreeStore
    
    @State private var givenNames: String = ""
    @State private var patronymic: String = ""
    @State private var surname: String = ""
    @State private var maidenName: String = ""
    @State private var sex: Person.Sex = .unknown
    @State private var birthDate: String = ""
    @State private var birthPlace: String = ""
    @State private var deathDate: String = ""
    @State private var deathPlace: String = ""
    @State private var isLiving: Bool = true
    @State private var burialPlace: String = ""
    @State private var occupation: String = ""
    @State private var education: String = ""
    @State private var notes: String = ""
    @State private var photoData: Data?
    @State private var addRelType: AddRelType = .none
    @State private var addRelPersonId: UUID?
    
    enum AddRelType: String, CaseIterable {
        case none = "—"
        case parent = "Добавить родителя"
        case spouse = "Добавить супруга"
        case child = "Добавить ребёнка"
        case sibling = "Добавить брата/сестру"
    }
    
    var body: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Text("Редактировать")
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
                        photoEditor
                        
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
                                        Button(s.russianName) { sex = s }.buttonStyle(SepiaButtonStyle(isActive: sex == s))
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
                            PlacePickerField(label: "МЕСТО ЗАХОРОНЕНИЯ", text: $burialPlace, placeholder: "—").padding(.bottom, 12)
                        }
                        
                        SectionHeader(title: "Жизнь")
                        SepiaTextField(label: "ПРОФЕССИЯ", text: $occupation, placeholder: "—").padding(.bottom, 8)
                        SepiaTextField(label: "ОБРАЗОВАНИЕ", text: $education, placeholder: "—").padding(.bottom, 8)
                        SepiaTextField(label: "ЗАМЕТКИ", text: $notes, placeholder: "—").padding(.bottom, 12)
                        
                        relationshipsEditor
                    }
                    .padding(.horizontal, 24).padding(.bottom, 20)
                }
                
                Divider().overlay(SepiaTheme.toolbarLine)
                
                HStack {
                    Button("Отмена") { dismiss() }.buttonStyle(SepiaButtonStyle())
                    Spacer()
                    Button("Сохранить") { savePerson() }
                        .buttonStyle(SepiaButtonStyle(isActive: true))
                        .disabled(givenNames.isEmpty && surname.isEmpty)
                }
                .padding(16)
            }
        }
        .frame(width: 540, height: 720)
        .onAppear { loadPerson() }
    }
    
    // MARK: - Relationships Editor
    
    private var relationshipsEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Родство")
            
            let idx = FamilyIndex(tree: tree)
            let parents = idx.parentsOf(person)
            let spouses = idx.spousesOf(person)
            let children = idx.childrenOf(person)
            let siblings = idx.siblingsOf(person)
            
            // Current relationships
            if let f = parents.father { relEditRow("Отец", f) { removeParent(f) } }
            if let m = parents.mother { relEditRow("Мать", m) { removeParent(m) } }
            ForEach(spouses, id: \.id) { s in relEditRow("Супруг", s) { removeSpouse(s) } }
            ForEach(children, id: \.id) { c in relEditRow("Ребёнок", c) { removeChild(c) } }
            ForEach(siblings, id: \.id) { s in
                relEditRow(s.sex == .male ? "Брат" : s.sex == .female ? "Сестра" : "Брат/сестра", s) { removeSibling(s) }
            }
            
            if parents.father == nil && parents.mother == nil && spouses.isEmpty && children.isEmpty && siblings.isEmpty {
                Text("Родственные связи не заданы")
                    .font(SepiaTheme.body(size: 13))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .padding(.bottom, 8)
            }
            
            // Add new relationship
            Divider().overlay(SepiaTheme.fieldLine).padding(.vertical, 8)
            
            HStack(spacing: 8) {
                Picker("", selection: $addRelType) {
                    ForEach(AddRelType.allCases, id: \.rawValue) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .font(SepiaTheme.body(size: 13))
                
                if addRelType != .none {
                    Picker("Кто:", selection: $addRelPersonId) {
                        Text("Выбрать…").tag(nil as UUID?)
                        ForEach(availablePeople, id: \.id) { p in
                            Text(p.listName).tag(p.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(SepiaTheme.body(size: 13))
                }
            }
            .padding(.bottom, 4)
            
            if addRelType != .none && addRelPersonId != nil {
                Button("Связать") { addRelationship() }
                    .buttonStyle(SepiaButtonStyle(isActive: true))
                    .padding(.top, 4)
            }
        }
    }
    
    private var availablePeople: [Person] {
        tree.people
            .filter { $0.id != person.id }
            .sorted { $0.listName.localizedCaseInsensitiveCompare($1.listName) == .orderedAscending }
    }
    
    private func relEditRow(_ tag: String, _ p: Person, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(tag.uppercased())
                .font(SepiaTheme.ui(size: 9.5)).tracking(1.2).foregroundColor(SepiaTheme.inkSoft)
                .frame(width: 80, alignment: .leading)
            Text(p.fullName)
                .font(SepiaTheme.body(size: 13.5))
                .foregroundColor(SepiaTheme.ink)
            Spacer()
            Button { onRemove() } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 6)
    }
    
    // MARK: - Relationship Actions
    
    private func removeParent(_ parent: Person) {
        for union in tree.unions {
            if union.childrenIds.contains(person.id) && union.partnerIds.contains(parent.id) {
                if union.partnerIds.count <= 1 && union.childrenIds.count <= 1 {
                    tree.unions.removeAll { $0.id == union.id }
                } else if union.partnerIds.count > 1 {
                    if union.partner1Id == parent.id { union.partner1Id = nil }
                    else if union.partner2Id == parent.id { union.partner2Id = nil }
                } else {
                    union.childrenIds.removeAll { $0 == person.id }
                }
                break
            }
        }
        tree.optimizeRoot()
        tree.updatedAt = Date()
        store.save()
    }
    
    private func removeSpouse(_ spouse: Person) {
        tree.unions.removeAll { union in
            union.partnerIds.contains(person.id) && union.partnerIds.contains(spouse.id) && union.childrenIds.isEmpty
        }
        // If union has children, just remove the partner link
        for union in tree.unions {
            if union.partnerIds.contains(person.id) && union.partnerIds.contains(spouse.id) {
                if union.partner1Id == spouse.id { union.partner1Id = nil }
                else if union.partner2Id == spouse.id { union.partner2Id = nil }
                break
            }
        }
        tree.optimizeRoot()
        tree.updatedAt = Date()
        store.save()
    }
    
    private func removeChild(_ child: Person) {
        for union in tree.unions {
            if union.partnerIds.contains(person.id) && union.childrenIds.contains(child.id) {
                union.childrenIds.removeAll { $0 == child.id }
                if union.childrenIds.isEmpty && union.partnerIds.count <= 1 {
                    tree.unions.removeAll { $0.id == union.id }
                }
                break
            }
        }
        tree.optimizeRoot()
        tree.updatedAt = Date()
        store.save()
    }
    
    private func removeSibling(_ sibling: Person) {
        for union in tree.unions {
            if union.childrenIds.contains(person.id) && union.childrenIds.contains(sibling.id) {
                union.childrenIds.removeAll { $0 == sibling.id }
                break
            }
        }
        tree.optimizeRoot()
        tree.updatedAt = Date()
        store.save()
    }
    
    private func addRelationship() {
        guard let targetId = addRelPersonId, addRelType != .none else { return }
        
        switch addRelType {
        case .parent:
            // Check: target is already a parent of this person
            if tree.unions.contains(where: { $0.childrenIds.contains(person.id) && $0.partnerIds.contains(targetId) }) {
                break
            }
            if let existing = tree.unions.first(where: { $0.childrenIds.contains(person.id) }) {
                if existing.partner1Id == nil { existing.partner1Id = targetId }
                else if existing.partner2Id == nil { existing.partner2Id = targetId }
            } else {
                let u = Union(partner1Id: targetId, childrenIds: [person.id])
                tree.unions.append(u)
            }
        case .spouse:
            // Check: already spouses
            if tree.unions.contains(where: { $0.partnerIds.contains(person.id) && $0.partnerIds.contains(targetId) }) {
                break
            }
            let u = Union(partner1Id: person.id, partner2Id: targetId)
            tree.unions.append(u)
        case .child:
            // Check: target is already a child of this person
            if tree.unions.contains(where: { $0.partnerIds.contains(person.id) && $0.childrenIds.contains(targetId) }) {
                break
            }
            if let existing = tree.unions.first(where: { $0.partnerIds.contains(person.id) }) {
                existing.childrenIds.append(targetId)
            } else {
                let u = Union(partner1Id: person.id, childrenIds: [targetId])
                tree.unions.append(u)
            }
        case .sibling:
            // Check: already siblings (share a parent union)
            if tree.unions.contains(where: { $0.childrenIds.contains(person.id) && $0.childrenIds.contains(targetId) }) {
                break
            }
            if let existing = tree.unions.first(where: { $0.childrenIds.contains(person.id) }) {
                existing.childrenIds.append(targetId)
            } else {
                let u = Union(childrenIds: [person.id, targetId])
                tree.unions.append(u)
            }
        case .none:
            break
        }
        
        addRelType = .none
        addRelPersonId = nil
        tree.optimizeRoot()
        tree.updatedAt = Date()
        store.save()
    }
    
    private var photoEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ФОТО")
                .font(SepiaTheme.ui(size: 10))
                .tracking(1.5)
                .foregroundColor(SepiaTheme.inkSoft)
            
            HStack(spacing: 12) {
                if let data = photoData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(SepiaTheme.toolbarLine, lineWidth: 1))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(SepiaTheme.photoA.opacity(0.3))
                            .frame(width: 80, height: 80)
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 28))
                            .foregroundColor(SepiaTheme.inkSoft.opacity(0.5))
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            if let img = NSImage(contentsOf: url) {
                                let resized = resizeImage(img, maxDimension: 400)
                                if let tiff = resized.tiffRepresentation,
                                   let rep = NSBitmapImageRep(data: tiff) {
                                    photoData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
                                }
                            }
                        }
                    } label: {
                        Label("Выбрать фото", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(SepiaButtonStyle())
                    
                    if photoData != nil {
                        Button(role: .destructive) {
                            photoData = nil
                        } label: {
                            Label("Удалить", systemImage: "trash")
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
    
    private func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    private func loadPerson() {
        givenNames = person.givenNames
        patronymic = person.patronymic ?? ""
        surname = person.surname
        maidenName = person.maidenName ?? ""
        sex = person.sex
        birthDate = person.birthDate ?? ""
        birthPlace = person.birthPlace ?? ""
        deathDate = person.deathDate ?? ""
        deathPlace = person.deathPlace ?? ""
        isLiving = person.isLiving
        burialPlace = person.burialPlace ?? ""
        occupation = person.occupation ?? ""
        education = person.education ?? ""
        notes = person.notes ?? ""
        photoData = person.photoData
    }
    
    private func savePerson() {
        person.givenNames = givenNames
        person.patronymic = patronymic.isEmpty ? nil : patronymic
        person.surname = surname
        person.maidenName = maidenName.isEmpty ? nil : maidenName
        person.sex = sex
        person.birthDate = birthDate.isEmpty ? nil : FamilyDate.normalize(birthDate)
        person.birthPlace = birthPlace.isEmpty ? nil : birthPlace
        person.deathDate = isLiving ? nil : (deathDate.isEmpty ? nil : FamilyDate.normalize(deathDate))
        person.deathPlace = isLiving ? nil : (deathPlace.isEmpty ? nil : deathPlace)
        person.isLiving = isLiving
        person.burialPlace = burialPlace.isEmpty ? nil : burialPlace
        person.occupation = occupation.isEmpty ? nil : occupation
        person.education = education.isEmpty ? nil : education
        person.notes = notes.isEmpty ? nil : notes
        person.photoData = photoData
        person.updatedAt = Date()
        tree.optimizeRoot()
        tree.updatedAt = Date()
        store.save()
        dismiss()
    }
}
