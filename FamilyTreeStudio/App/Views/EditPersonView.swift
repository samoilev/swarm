import AppKit
import FamilyTreeCore
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
    @State private var birthCoords: String = ""
    @State private var deathDate: String = ""
    @State private var deathPlace: String = ""
    @State private var deathCoords: String = ""
    @State private var isLiving: Bool = true
    @State private var burialPlace: String = ""
    @State private var burialCoords: String = ""
    @State private var occupation: String = ""
    @State private var education: String = ""
    @State private var notes: String = ""
    @State private var photoData: Data?
    @State private var showPhotoImporter = false
    @State private var cropSource: NSImage?
    @State private var showAttachmentImporter = false
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
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) } // tap empty space → close dropdowns

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
                                        Button(s.russianName) { sex = s }.buttonStyle(SepiaButtonStyle(isActive: sex == s))
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

                        attachmentsEditor

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
        .sheet(isPresented: Binding(get: { cropSource != nil }, set: { if !$0 { cropSource = nil } })) {
            if let img = cropSource {
                PhotoCropView(image: img,
                              onCancel: { cropSource = nil },
                              onConfirm: { cropped in storePhoto(cropped); cropSource = nil })
            }
        }
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
            Text(p.listName)
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
        store.saveTree(tree)
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
        store.saveTree(tree)
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
        store.saveTree(tree)
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
        store.saveTree(tree)
    }

    private func addRelationship() {
        guard let targetId = addRelPersonId else { return }
        let kind: RelationKind
        switch addRelType {
        case .parent: kind = .parent
        case .spouse: kind = .spouse
        case .child: kind = .child
        case .sibling: kind = .sibling
        case .none: return
        }
        tree.addRelation(kind, person: person, target: targetId)

        addRelType = .none
        addRelPersonId = nil
        tree.optimizeRoot()
        tree.updatedAt = Date()
        store.saveTree(tree)
    }

    // MARK: - Attachments Editor

    private var attachmentsEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Файлы")

            if person.attachments.isEmpty {
                Text("Файлы не прикреплены")
                    .font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.inkSoft)
                    .padding(.bottom, 8)
            } else {
                ForEach(person.attachments) { att in
                    attachmentEditRow(att)
                }
            }

            Button { showAttachmentImporter = true } label: {
                Label("Прикрепить файл", systemImage: "paperclip")
            }
            .buttonStyle(SepiaButtonStyle())
            .padding(.top, 4)
            .padding(.bottom, 12)
            .fileImporter(isPresented: $showAttachmentImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { attachFiles(urls) }
            }
        }
    }

    private func attachmentEditRow(_ att: Attachment) -> some View {
        let url = store.attachmentURL(att, in: tree)
        return HStack(spacing: 10) {
            Button { NSWorkspace.shared.open(url) } label: {
                HStack(spacing: 10) {
                    AttachmentThumbnail(url: url, isImage: att.isImage, format: att.format, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(att.originalName)
                            .font(SepiaTheme.body(size: 13.5)).foregroundColor(SepiaTheme.ink)
                            .lineLimit(1).truncationMode(.middle)
                        Text(att.format.isEmpty ? "Файл" : att.format)
                            .font(SepiaTheme.ui(size: 9.5)).tracking(1).foregroundColor(SepiaTheme.inkSoft)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Открыть «\(att.originalName)»")

            Spacer(minLength: 0)

            Button { store.removeAttachment(att, from: person, in: tree) } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14)).foregroundColor(.red.opacity(0.7))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Удалить файл")
        }
        .padding(.bottom, 8)
    }

    private func attachFiles(_ urls: [URL]) {
        for url in urls {
            do {
                _ = try store.addAttachment(to: person, in: tree, sourceURL: url)
            } catch {
                print("Failed to attach \(url.lastPathComponent): \(error)")
            }
        }
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
                        .frame(width: 96, height: 128) // 3:4 portrait, matches tree node & inspector
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(SepiaTheme.toolbarLine, lineWidth: 1))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(SepiaTheme.photoA.opacity(0.3))
                            .frame(width: 96, height: 128)
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 28))
                            .foregroundColor(SepiaTheme.inkSoft.opacity(0.5))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        showPhotoImporter = true
                    } label: {
                        Label("Выбрать фото", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(SepiaButtonStyle())
                    .fileImporter(isPresented: $showPhotoImporter, allowedContentTypes: [.image]) { result in
                        if case .success(let url) = result { beginPhotoSelection(from: url) }
                    }

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

    /// Load the picked image at full resolution and present the crop selector.
    private func beginPhotoSelection(from url: URL) {
        // .fileImporter may hand back a security-scoped URL (sandbox-safe).
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let img = NSImage(contentsOf: url) else { return }
        cropSource = img
    }

    /// Store a (already cropped to 3:4) image as the card photo, downscaled to a thumbnail.
    private func storePhoto(_ image: NSImage) {
        let resized = resizeImage(image, maxDimension: 600)
        if let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            photoData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        }
    }

    private func formatCoords(_ lat: Double?, _ lon: Double?) -> String {
        guard let lat, let lon else { return "" }
        return String(format: "%.5f, %.5f", lat, lon)
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
        birthCoords = formatCoords(person.birthLat, person.birthLon)
        deathDate = person.deathDate ?? ""
        deathPlace = person.deathPlace ?? ""
        deathCoords = formatCoords(person.deathLat, person.deathLon)
        isLiving = person.isLiving
        burialPlace = person.burialPlace ?? ""
        if let lat = person.burialLat, let lon = person.burialLon {
            burialCoords = "\(lat), \(lon)"
        } else {
            burialCoords = ""
        }
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
        let birthCoord = parseGraveCoords(birthCoords)
        person.birthLat = birthCoord?.lat
        person.birthLon = birthCoord?.lon
        person.deathDate = isLiving ? nil : (deathDate.isEmpty ? nil : FamilyDate.normalize(deathDate))
        person.deathPlace = isLiving ? nil : (deathPlace.isEmpty ? nil : deathPlace)
        let deathCoord = isLiving ? nil : parseGraveCoords(deathCoords)
        person.deathLat = deathCoord?.lat
        person.deathLon = deathCoord?.lon
        person.isLiving = isLiving
        person.burialPlace = burialPlace.isEmpty ? nil : burialPlace
        let graveCoords = isLiving ? nil : parseGraveCoords(burialCoords)
        person.burialLat = graveCoords?.lat
        person.burialLon = graveCoords?.lon
        person.occupation = occupation.isEmpty ? nil : occupation
        person.education = education.isEmpty ? nil : education
        person.notes = notes.isEmpty ? nil : notes
        person.photoData = photoData
        person.updatedAt = Date()
        tree.optimizeRoot()
        tree.updatedAt = Date()
        store.saveTree(tree)
        dismiss()
    }
}
