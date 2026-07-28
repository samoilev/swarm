import AppKit
import os
import SwarmCore
import SwiftUI
import UniformTypeIdentifiers

private let log = Logger(subsystem: "com.samoilev.swarm", category: "EditPerson")

struct EditPersonView: View {
    @Environment(\.dismiss) private var dismiss
    let person: Person
    var tree: FamilyTree
    var store: TreeStore
    /// Called after a successful save so the host can confirm it (toast). Mirrors
    /// AddPersonView.onAdded — without it, edits saved and dismissed silently.
    var onSaved: ((Person) -> Void)?

    @State private var givenNames: String = ""
    @State private var patronymic: String = ""
    @State private var surname: String = ""
    @State private var maidenName: String = ""
    @State private var sex: Person.Sex = .unknown
    @State private var birthDate: String = ""
    @State private var birthDateEnd: String = ""
    @State private var birthQualifier: GenealogyDate.Qualifier = .exact
    @State private var originalBirthDate: GenealogyDate?
    @State private var birthPlace: String = ""
    @State private var birthCoords: String = ""
    @State private var selectedBirthPlace: PlaceEntry?
    @State private var deathDate: String = ""
    @State private var deathDateEnd: String = ""
    @State private var deathQualifier: GenealogyDate.Qualifier = .exact
    @State private var originalDeathDate: GenealogyDate?
    @State private var deathPlace: String = ""
    @State private var deathCoords: String = ""
    @State private var selectedDeathPlace: PlaceEntry?
    @State private var isLiving: Bool = true
    @State private var burialPlace: String = ""
    @State private var burialCoords: String = ""
    @State private var selectedBurialPlace: PlaceEntry?
    @State private var occupation: String = ""
    @State private var education: String = ""
    @State private var notes: String = ""
    @State private var photoData: Data?
    @State private var showPhotoImporter = false
    @State private var cropSource: NSImage?
    @State private var showAttachmentImporter = false
    @State private var addRelType: AddRelType = .none
    @State private var addRelPersonId: UUID?
    @State private var editSession: EditSession?
    @State private var preparedAttachmentIDs: Set<UUID> = []
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var didCommit = false
    @State private var sourceTitle = ""
    @State private var sourceAuthor = ""
    @State private var selectedSourceID: UUID?
    @State private var citationPage = ""
    @State private var citationDetail = ""
    @State private var citationTranscription = ""
    @State private var citationConfidence = ""
    @State private var citationNotes = ""
    @State private var evidenceTarget: EvidenceTarget = .person
    @State private var evidenceObjectID: UUID?

    enum EvidenceTarget: CaseIterable, Identifiable {
        case person, primaryName, birth, death, relationship, union, attachment
        var id: Self { self }
        var displayName: String {
            switch self {
            case .person: L10n.tr("Персона")
            case .primaryName: L10n.tr("Основное имя")
            case .birth: L10n.tr("Рождение")
            case .death: L10n.tr("Смерть")
            case .relationship: L10n.tr("Родительская связь")
            case .union: L10n.tr("Союз")
            case .attachment: L10n.tr("Вложение")
            }
        }
    }

    private var editingTree: FamilyTree { editSession?.draftTree ?? tree }
    private var editingPerson: Person { editingTree.person(byId: person.id) ?? person }

    enum AddRelType: CaseIterable {
        case none, parent, spouse, child, sibling
        var displayName: String {
            switch self {
            case .none: "—"
            case .parent: L10n.tr("Добавить родителя")
            case .spouse: L10n.tr("Добавить супруга")
            case .child: L10n.tr("Добавить ребёнка")
            case .sibling: L10n.tr("Добавить брата/сестру")
            }
        }
    }

    var body: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) } // tap empty space → close dropdowns

            VStack(spacing: 0) {
                HStack {
                    Text(L10n.tr("Редактировать"))
                        .font(SepiaTheme.display(size: 22))
                        .foregroundColor(SepiaTheme.ink)
                    Spacer()
                    Button { cancelEditing() } label: {
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

                        evidenceEditor

                        attachmentsEditor

                        unionsEditor

                        relationshipsEditor
                    }
                    .padding(.horizontal, 24).padding(.bottom, 20)
                }

                Divider().overlay(SepiaTheme.toolbarLine)

                HStack {
                    Button(L10n.tr("Отмена")) { cancelEditing() }.buttonStyle(SepiaButtonStyle())
                    Spacer()
                    Button(L10n.tr("Сохранить")) { savePerson() }
                        .buttonStyle(SepiaButtonStyle(isActive: true))
                        .disabled(isSaving)
                        .disabled(givenNames.isEmpty && surname.isEmpty)
                }
                .padding(16)
            }
        }
        .frame(width: 540, height: 720)
        .onAppear { loadPerson() }
        .onDisappear {
            if !didCommit { discardPreparedAttachments() }
        }
        .alert(L10n.tr("Не удалось сохранить"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .sheet(isPresented: Binding(get: { cropSource != nil }, set: { if !$0 { cropSource = nil } })) {
            if let img = cropSource {
                PhotoCropView(image: img,
                              onCancel: { cropSource = nil },
                              onConfirm: { cropped in storePhoto(cropped); cropSource = nil })
            }
        }
    }

    // MARK: - Relationships Editor

    private var evidenceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L10n.tr("Источники и доказательства"))

            HStack(spacing: 8) {
                SepiaTextField(label: L10n.tr("НОВЫЙ ИСТОЧНИК"), text: $sourceTitle, placeholder: L10n.tr("Название"))
                SepiaTextField(label: L10n.tr("АВТОР"), text: $sourceAuthor, placeholder: "—")
            }
            Button(L10n.tr("Добавить в библиотеку")) { addSource() }
                .buttonStyle(SepiaButtonStyle())
                .disabled(sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if editingTree.sourceRecords.isEmpty {
                Text(L10n.tr("Сначала добавьте источник.")).font(SepiaTheme.body(size: 12)).foregroundStyle(SepiaTheme.inkSoft)
            } else {
                Picker(L10n.tr("Источник"), selection: $selectedSourceID) {
                    Text(L10n.tr("Выбрать…")).tag(nil as UUID?)
                    ForEach(editingTree.sourceRecords) { Text($0.title).tag($0.id as UUID?) }
                }.pickerStyle(.menu)

                if let sourceID = selectedSourceID,
                   let sourceIndex = editingTree.sourceRecords.firstIndex(where: { $0.id == sourceID }) {
                    sourceRecordFields(index: sourceIndex)
                }

                HStack {
                    Picker(L10n.tr("Для факта"), selection: $evidenceTarget) {
                        ForEach(EvidenceTarget.allCases) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.menu)
                    if !evidenceObjects.isEmpty {
                        Picker(L10n.tr("Запись"), selection: $evidenceObjectID) {
                            Text(L10n.tr("Выбрать…")).tag(nil as UUID?)
                            ForEach(evidenceObjects, id: \.id) { Text($0.label).tag($0.id as UUID?) }
                        }.pickerStyle(.menu)
                    }
                }
                HStack(spacing: 8) {
                    SepiaTextField(label: L10n.tr("СТРАНИЦА"), text: $citationPage, placeholder: "—")
                    SepiaTextField(label: L10n.tr("ДЕТАЛЬ"), text: $citationDetail, placeholder: "—")
                    SepiaTextField(label: L10n.tr("НАДЁЖНОСТЬ"), text: $citationConfidence, placeholder: L10n.tr("0–3 / текст"))
                }
                SepiaNotesField(label: L10n.tr("РАСШИФРОВКА"), text: $citationTranscription, placeholder: L10n.tr("Точная запись из источника…"))
                SepiaNotesField(label: L10n.tr("ЗАМЕТКА К ССЫЛКЕ"), text: $citationNotes, placeholder: "—")
                Button(L10n.tr("Привязать ссылку")) { addCitation() }
                    .buttonStyle(SepiaButtonStyle(isActive: true))
                    .disabled(selectedSourceID == nil || (requiresEvidenceObject && evidenceObjectID == nil))
            }
        }.padding(.bottom, 12)
    }

    private func sourceRecordFields(index: Int) -> some View {
        VStack(spacing: 8) {
            SepiaTextField(label: L10n.tr("НАЗВАНИЕ"), text: Binding(
                get: { editingTree.sourceRecords[index].title },
                set: { editingTree.sourceRecords[index].title = $0 }
            ), placeholder: "—")
            HStack(spacing: 8) {
                SepiaTextField(label: L10n.tr("АВТОР"), text: optionalSourceBinding(index, \.author), placeholder: "—")
                SepiaTextField(label: L10n.tr("ПУБЛИКАЦИЯ"), text: optionalSourceBinding(index, \.publication), placeholder: "—")
            }
            HStack(spacing: 8) {
                SepiaTextField(label: L10n.tr("ХРАНИЛИЩЕ"), text: optionalSourceBinding(index, \.repository), placeholder: "—")
                SepiaTextField(label: L10n.tr("ШИФР"), text: optionalSourceBinding(index, \.callNumber), placeholder: "—")
            }
            SepiaNotesField(label: L10n.tr("ЗАМЕТКИ"), text: optionalSourceBinding(index, \.notes), placeholder: "—")
        }
    }

    private func optionalSourceBinding(_ index: Int, _ keyPath: WritableKeyPath<SourceRecord, String?>) -> Binding<String> {
        Binding(
            get: { editingTree.sourceRecords[index][keyPath: keyPath] ?? "" },
            set: { editingTree.sourceRecords[index][keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var evidenceObjects: [(id: UUID, label: String)] {
        switch evidenceTarget {
        case .relationship:
            editingTree.parentLinks.filter { $0.parentID == editingPerson.id || $0.childID == editingPerson.id }.map { link in
                let otherID = link.parentID == editingPerson.id ? link.childID : link.parentID
                return (link.id, editingTree.person(byId: otherID)?.listName ?? L10n.tr("Связь"))
            }
        case .union:
            editingTree.unions.filter { $0.partnerIds.contains(editingPerson.id) || $0.childrenIds.contains(editingPerson.id) }
                .map { ($0.id, unionLabel($0)) }
        case .attachment:
            editingPerson.attachments.map { ($0.id, $0.originalName) }
        default: []
        }
    }

    private var requiresEvidenceObject: Bool { [.relationship, .union, .attachment].contains(evidenceTarget) }

    private func addSource() {
        let title = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let source = SourceRecord(title: title, author: sourceAuthor.isEmpty ? nil : sourceAuthor)
        editingTree.sourceRecords.append(source)
        selectedSourceID = source.id
        sourceTitle = ""; sourceAuthor = ""
    }

    private func addCitation() {
        guard let sourceID = selectedSourceID else { return }
        let citation = Citation(
            sourceID: sourceID,
            page: citationPage.nilIfEmpty,
            detail: citationDetail.nilIfEmpty,
            transcription: citationTranscription.nilIfEmpty,
            confidence: citationConfidence.nilIfEmpty,
            notes: citationNotes.nilIfEmpty
        )
        switch evidenceTarget {
        case .person:
            editingPerson.citations.append(citation)
        case .primaryName:
            if let index = editingPerson.names.firstIndex(where: \.isPrimary) ?? editingPerson.names.indices.first {
                editingPerson.names[index].citations.append(citation)
            }
        case .birth, .death:
            let kind: GenealogyEvent.Kind = evidenceTarget == .birth ? .birth : .death
            var event = editingPerson.event(ofKind: kind) ?? GenealogyEvent(kind: kind)
            event.citations.append(citation)
            editingPerson.replaceEvent(event)
        case .relationship:
            if let id = evidenceObjectID, let index = editingTree.parentLinks.firstIndex(where: { $0.id == id }) {
                editingTree.parentLinks[index].citations.append(citation)
            }
        case .union:
            if let id = evidenceObjectID, let union = editingTree.unions.first(where: { $0.id == id }) { union.citations.append(citation) }
        case .attachment:
            if let id = evidenceObjectID, let index = editingPerson.attachments.firstIndex(where: { $0.id == id }) {
                editingPerson.attachments[index].citations.append(citation)
            }
        }
        citationPage = ""; citationDetail = ""; citationTranscription = ""; citationConfidence = ""; citationNotes = ""
    }

    private var unionsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L10n.tr("Союзы и дети"))
            let unions = editingTree.unions.filter { $0.partnerIds.contains(editingPerson.id) }
            if unions.isEmpty {
                Text(L10n.tr("Союзы не заданы")).font(SepiaTheme.body(size: 13)).foregroundStyle(SepiaTheme.inkSoft)
            } else {
                ForEach(unions, id: \.id) { union in
                    UnionDraftEditor(union: union, tree: editingTree, subject: editingPerson)
                    Divider().overlay(SepiaTheme.fieldLine).padding(.vertical, 8)
                }
            }
        }.padding(.bottom, 12)
    }

    private func unionLabel(_ union: Union) -> String {
        let names = union.partnerIds.compactMap { editingTree.person(byId: $0)?.listName }
        return names.isEmpty ? L10n.tr("Семейная запись") : names.joined(separator: " + ")
    }

    private var relationshipsEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.tr("Родство"))

            let editPerson = editingPerson
            let idx = FamilyIndex(tree: editingTree)
            let parents = idx.parentsOf(editPerson)
            let spouses = idx.spousesOf(editPerson)
            let children = idx.childrenOf(editPerson)
            let siblings = idx.siblingsOf(editPerson)

            // Current relationships
            if let f = parents.father { relEditRow(L10n.tr("Отец"), f) { removeParent(f) } }
            if let m = parents.mother { relEditRow(L10n.tr("Мать"), m) { removeParent(m) } }
            ForEach(spouses, id: \.id) { s in relEditRow(L10n.tr("Супруг"), s) { removeSpouse(s) } }
            ForEach(children, id: \.id) { c in relEditRow(L10n.tr("Ребёнок"), c) { removeChild(c) } }
            ForEach(siblings, id: \.id) { s in
                relEditRow(s.sex == .male ? L10n.tr("Брат") : s.sex == .female ? L10n.tr("Сестра") : L10n.tr("Брат/сестра"), s) { removeSibling(s) }
            }

            if parents.father == nil && parents.mother == nil && spouses.isEmpty && children.isEmpty && siblings.isEmpty {
                Text(L10n.tr("Родственные связи не заданы"))
                    .font(SepiaTheme.body(size: 13))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .padding(.bottom, 8)
            }

            // Add new relationship
            Divider().overlay(SepiaTheme.fieldLine).padding(.vertical, 8)

            HStack(spacing: 8) {
                Picker("", selection: $addRelType) {
                    ForEach(AddRelType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .font(SepiaTheme.body(size: 13))

                if addRelType != .none {
                    Picker(L10n.tr("Кто:"), selection: $addRelPersonId) {
                        Text(L10n.tr("Выбрать…")).tag(nil as UUID?)
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
                Button(L10n.tr("Связать")) { addRelationship() }
                    .buttonStyle(SepiaButtonStyle(isActive: true))
                    .padding(.top, 4)
            }
        }
    }

    private var availablePeople: [Person] {
        editingTree.people
            .filter { $0.id != editingPerson.id }
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
        let editPerson = editingPerson
        for union in editingTree.unions {
            if union.childrenIds.contains(editPerson.id) && union.partnerIds.contains(parent.id) {
                if union.partnerIds.count <= 1 && union.childrenIds.count <= 1 {
                    editingTree.unions.removeAll { $0.id == union.id }
                } else if union.partnerIds.count > 1 {
                    if union.partner1Id == parent.id { union.partner1Id = nil }
                    else if union.partner2Id == parent.id { union.partner2Id = nil }
                } else {
                    union.childrenIds.removeAll { $0 == editPerson.id }
                }
                break
            }
        }
        editingTree.optimizeRoot()
        editingTree.reconcileParentLinks()
    }

    private func removeSpouse(_ spouse: Person) {
        let editPerson = editingPerson
        editingTree.unions.removeAll { union in
            union.partnerIds.contains(editPerson.id) && union.partnerIds.contains(spouse.id) && union.childrenIds.isEmpty
        }
        // If the union has children, remove only the partner link.
        for union in editingTree.unions {
            if union.partnerIds.contains(editPerson.id) && union.partnerIds.contains(spouse.id) {
                if union.partner1Id == spouse.id { union.partner1Id = nil }
                else if union.partner2Id == spouse.id { union.partner2Id = nil }
                break
            }
        }
        editingTree.optimizeRoot()
        editingTree.reconcileParentLinks()
    }

    private func removeChild(_ child: Person) {
        let editPerson = editingPerson
        for union in editingTree.unions {
            if union.partnerIds.contains(editPerson.id) && union.childrenIds.contains(child.id) {
                union.childrenIds.removeAll { $0 == child.id }
                if union.childrenIds.isEmpty && union.partnerIds.count <= 1 {
                    editingTree.unions.removeAll { $0.id == union.id }
                }
                break
            }
        }
        editingTree.optimizeRoot()
        editingTree.reconcileParentLinks()
    }

    private func removeSibling(_ sibling: Person) {
        let editPerson = editingPerson
        for union in editingTree.unions {
            if union.childrenIds.contains(editPerson.id) && union.childrenIds.contains(sibling.id) {
                union.childrenIds.removeAll { $0 == sibling.id }
                break
            }
        }
        editingTree.optimizeRoot()
        editingTree.reconcileParentLinks()
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
        editingTree.addRelation(kind, person: editingPerson, target: targetId)

        addRelType = .none
        addRelPersonId = nil
        editingTree.optimizeRoot()
    }

    // MARK: - Attachments Editor

    private var attachmentsEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.tr("Файлы"))

            if editingPerson.attachments.isEmpty {
                Text(L10n.tr("Файлы не прикреплены"))
                    .font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.inkSoft)
                    .padding(.bottom, 8)
            } else {
                ForEach(editingPerson.attachments) { att in
                    attachmentEditRow(att)
                }
            }

            Button { showAttachmentImporter = true } label: {
                Label(L10n.tr("Прикрепить файл"), systemImage: "paperclip")
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
        let url = store.previewURL(for: att, in: tree)
        return HStack(spacing: 10) {
            Button { NSWorkspace.shared.open(url) } label: {
                HStack(spacing: 10) {
                    AttachmentThumbnail(url: url, isImage: att.isImage, format: att.format, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(att.originalName)
                            .font(SepiaTheme.body(size: 13.5)).foregroundColor(SepiaTheme.ink)
                            .lineLimit(1).truncationMode(.middle)
                        Text(att.format.isEmpty ? L10n.tr("Файл") : att.format)
                            .font(SepiaTheme.ui(size: 9.5)).tracking(1).foregroundColor(SepiaTheme.inkSoft)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("Открыть «\(att.originalName)»"))

            Spacer(minLength: 0)

            Button { removeDraftAttachment(att) } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14)).foregroundColor(.red.opacity(0.7))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("Удалить файл"))
        }
        .padding(.bottom, 8)
    }

    private func attachFiles(_ urls: [URL]) {
        for url in urls {
            do {
                let attachment = try store.prepareAttachment(in: tree, sourceURL: url)
                editingPerson.attachments.append(attachment)
                preparedAttachmentIDs.insert(attachment.id)
            } catch {
                log.error("Failed to attach \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func removeDraftAttachment(_ attachment: Attachment) {
        editingPerson.attachments.removeAll { $0.id == attachment.id }
        if preparedAttachmentIDs.remove(attachment.id) != nil {
            store.discardPreparedAttachment(attachment, in: tree)
        }
    }

    private var photoEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("ФОТО"))
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
                        Label(L10n.tr("Выбрать фото"), systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(SepiaButtonStyle())
                    .fileImporter(isPresented: $showPhotoImporter, allowedContentTypes: [.image]) { result in
                        if case .success(let url) = result { beginPhotoSelection(from: url) }
                    }

                    if photoData != nil {
                        Button(role: .destructive) {
                            photoData = nil
                        } label: {
                            Label(L10n.tr("Удалить"), systemImage: "trash")
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
        if editSession == nil { editSession = try? EditSession(tree: tree) }
        let source = editingPerson
        givenNames = source.givenNames
        patronymic = source.patronymic ?? ""
        surname = source.surname
        maidenName = source.maidenName ?? ""
        sex = source.sex
        let loadedBirth = displayDate(source.event(ofKind: .birth)?.date)
        originalBirthDate = source.event(ofKind: .birth)?.date
        birthDate = loadedBirth.text
        birthDateEnd = loadedBirth.end
        birthQualifier = loadedBirth.qualifier
        birthPlace = source.birthPlace ?? ""
        birthCoords = formatCoords(source.birthLat, source.birthLon)
        let loadedDeath = displayDate(source.event(ofKind: .death)?.date)
        originalDeathDate = source.event(ofKind: .death)?.date
        deathDate = loadedDeath.text
        deathDateEnd = loadedDeath.end
        deathQualifier = loadedDeath.qualifier
        deathPlace = source.deathPlace ?? ""
        deathCoords = formatCoords(source.deathLat, source.deathLon)
        isLiving = source.isLiving
        burialPlace = source.burialPlace ?? ""
        if let lat = source.burialLat, let lon = source.burialLon {
            burialCoords = "\(lat), \(lon)"
        } else {
            burialCoords = ""
        }
        occupation = source.occupation ?? ""
        education = source.education ?? ""
        notes = source.notes ?? ""
        photoData = source.photoData
    }

    private func savePerson() {
        guard validCoordinateText(birthCoords), validCoordinateText(deathCoords), validCoordinateText(burialCoords) else {
            saveError = L10n.tr("Координаты должны иметь формат «широта, долгота» и находиться в допустимом диапазоне.")
            return
        }
        let parsedBirthDate = parsedDate(text: birthDate, end: birthDateEnd, qualifier: birthQualifier, original: originalBirthDate)
        let parsedDeathDate = isLiving ? nil : parsedDate(
            text: deathDate,
            end: deathDateEnd,
            qualifier: deathQualifier,
            original: originalDeathDate
        )
        if (!birthDate.isEmpty && parsedBirthDate == nil) || (!isLiving && !deathDate.isEmpty && parsedDeathDate == nil) {
            saveError = L10n.tr("Исправьте некорректные даты перед сохранением.")
            return
        }
        let before = try? JSONEncoder().encode(tree)
        let draft = editingTree
        let draftPerson = editingPerson
        tree.unions = draft.unions
        tree.parentLinks = draft.parentLinks
        tree.sourceRecords = draft.sourceRecords
        person.attachments = draftPerson.attachments
        person.citations = draftPerson.citations
        person.names = draftPerson.names
        person.events = draftPerson.events
        person.givenNames = givenNames
        person.patronymic = patronymic.isEmpty ? nil : patronymic
        person.surname = surname
        person.maidenName = maidenName.isEmpty ? nil : maidenName
        person.sex = sex
        person.birthDate = birthDate.isEmpty ? nil : FamilyDate.normalize(birthDate)
        person.setStructuredDate(parsedBirthDate, for: .birth)
        person.birthPlace = birthPlace.isEmpty ? nil : birthPlace
        let birthCoord = parseGraveCoords(birthCoords)
        person.birthLat = birthCoord?.lat
        person.birthLon = birthCoord?.lon
        if let selectedBirthPlace, selectedBirthPlace.displayName == birthPlace {
            person.setStructuredPlace(selectedBirthPlace.placeReference, for: .birth)
        }
        person.deathDate = isLiving ? nil : (deathDate.isEmpty ? nil : FamilyDate.normalize(deathDate))
        person.setStructuredDate(parsedDeathDate, for: .death)
        person.deathPlace = isLiving ? nil : (deathPlace.isEmpty ? nil : deathPlace)
        let deathCoord = isLiving ? nil : parseGraveCoords(deathCoords)
        person.deathLat = deathCoord?.lat
        person.deathLon = deathCoord?.lon
        if let selectedDeathPlace, selectedDeathPlace.displayName == deathPlace, !isLiving {
            person.setStructuredPlace(selectedDeathPlace.placeReference, for: .death)
        }
        person.isLiving = isLiving
        person.burialPlace = burialPlace.isEmpty ? nil : burialPlace
        let graveCoords = isLiving ? nil : parseGraveCoords(burialCoords)
        person.burialLat = graveCoords?.lat
        person.burialLon = graveCoords?.lon
        if let selectedBurialPlace, selectedBurialPlace.displayName == burialPlace, !isLiving {
            person.setStructuredPlace(selectedBurialPlace.placeReference, for: .burial)
        }
        person.occupation = occupation.isEmpty ? nil : occupation
        person.education = education.isEmpty ? nil : education
        person.notes = notes.isEmpty ? nil : notes
        if photoData != person.photoData { person.photoData = photoData }
        person.updatedAt = Date()
        tree.optimizeRoot()
        tree.updatedAt = Date()
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                _ = try await store.saveTree(tree)
                didCommit = true
                preparedAttachmentIDs.removeAll()
                onSaved?(person)
                dismiss()
            } catch {
                if let before, let snapshot = try? JSONDecoder().decode(FamilyTree.self, from: before) {
                    apply(snapshot: snapshot)
                }
                saveError = error.localizedDescription
            }
        }
    }

    private func validCoordinateText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let coordinates = parseGraveCoords(trimmed) else { return false }
        return (-90 ... 90).contains(coordinates.lat) && (-180 ... 180).contains(coordinates.lon)
    }

    private func parsedDate(
        text: String,
        end: String,
        qualifier: GenealogyDate.Qualifier,
        original: GenealogyDate?
    ) -> GenealogyDate? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let original, original.start == nil, text == original.rawValue, qualifier == original.qualifier {
            return original
        }
        let range = qualifier == .between || qualifier == .fromTo
        let value = GenealogyDate(userInput: text, qualifier: qualifier, endValue: range ? end : nil)
        return value.isValid ? value : nil
    }

    private func displayDate(_ date: GenealogyDate?) -> (text: String, end: String, qualifier: GenealogyDate.Qualifier) {
        guard let date else { return ("", "", .exact) }
        return (date.start?.displayValue ?? date.rawValue, date.end?.displayValue ?? "", date.qualifier)
    }

    private func cancelEditing() {
        discardPreparedAttachments()
        dismiss()
    }

    private func discardPreparedAttachments() {
        for attachment in editingPerson.attachments where preparedAttachmentIDs.contains(attachment.id) {
            store.discardPreparedAttachment(attachment, in: tree)
        }
        preparedAttachmentIDs.removeAll()
    }

    private func apply(snapshot: FamilyTree) {
        tree.name = snapshot.name
        tree.subtitle = snapshot.subtitle
        tree.homePersonId = snapshot.homePersonId
        tree.rootUnionId = snapshot.rootUnionId
        if let source = snapshot.person(byId: person.id) {
            person.givenNames = source.givenNames
            person.patronymic = source.patronymic
            person.surname = source.surname
            person.maidenName = source.maidenName
            person.sex = source.sex
            person.birthDate = source.birthDate
            person.birthPlace = source.birthPlace
            person.birthLat = source.birthLat
            person.birthLon = source.birthLon
            person.deathDate = source.deathDate
            person.deathPlace = source.deathPlace
            person.deathLat = source.deathLat
            person.deathLon = source.deathLon
            person.isLiving = source.isLiving
            person.burialPlace = source.burialPlace
            person.burialLat = source.burialLat
            person.burialLon = source.burialLon
            person.occupation = source.occupation
            person.education = source.education
            person.notes = source.notes
            person.names = source.names
            person.events = source.events
            person.citations = source.citations
            person.attachments = source.attachments
            person.photoFilename = source.photoFilename
            person.gedcomXref = source.gedcomXref
            person.unknownBranches = source.unknownBranches
            person.eventExtras = source.eventExtras
        }
        tree.unions = snapshot.unions
        tree.sourceRecords = snapshot.sourceRecords
        tree.parentLinks = snapshot.parentLinks
        tree.headUnknownBranches = snapshot.headUnknownBranches
        tree.unknownRecords = snapshot.unknownRecords
        tree.gedcomDocument = snapshot.gedcomDocument
        tree.importReport = snapshot.importReport
        tree.acceptedBaselineIssueIDs = snapshot.acceptedBaselineIssueIDs
        tree.layoutVersion += 1
        store.refreshMediaFolders(for: tree)
    }
}

private struct UnionDraftEditor: View {
    let union: Union
    let tree: FamilyTree
    let subject: Person
    @State private var childToAdd: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(partnerNames).font(SepiaTheme.body(size: 15)).foregroundStyle(SepiaTheme.ink)
                    Text(L10n.tr("\(union.childrenIds.count) детей · \(union.citations.count) ссылок"))
                        .font(SepiaTheme.ui(size: 10)).foregroundStyle(SepiaTheme.inkSoft)
                }
                Spacer()
            }

            Picker(L10n.tr("Партнёр"), selection: partnerBinding) {
                Text(L10n.tr("Не указан")).tag(nil as UUID?)
                ForEach(availablePartners, id: \.id) { Text($0.listName).tag($0.id as UUID?) }
            }
            .pickerStyle(.menu)

            UnionEventDraftEditor(kind: .partnership, union: union, attachments: subject.attachments)
            UnionEventDraftEditor(kind: .marriage, union: union, attachments: subject.attachments)
            UnionEventDraftEditor(kind: .separation, union: union, attachments: subject.attachments)
            UnionEventDraftEditor(kind: .divorce, union: union, attachments: subject.attachments)

            SepiaFieldLabel(L10n.tr("ДЕТИ И ТИП РОДИТЕЛЬСТВА"), isDecorative: false)
            ForEach(union.childrenIds, id: \.self) { childID in
                HStack {
                    Text(tree.person(byId: childID)?.listName ?? L10n.tr("Неизвестная персона"))
                        .font(SepiaTheme.body(size: 13)).foregroundStyle(SepiaTheme.ink)
                    Spacer()
                    Picker(L10n.tr("Тип"), selection: parentageBinding(childID: childID)) {
                        ForEach(ParentageKind.allCases, id: \.rawValue) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.menu).frame(width: 150)
                    Button(role: .destructive) {
                        union.childrenIds.removeAll { $0 == childID }
                        tree.parentLinks.removeAll { $0.unionID == union.id && $0.childID == childID }
                    } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                }
            }
            HStack {
                Picker(L10n.tr("Добавить ребёнка"), selection: $childToAdd) {
                    Text(L10n.tr("Выбрать…")).tag(nil as UUID?)
                    ForEach(availableChildren, id: \.id) { Text($0.listName).tag($0.id as UUID?) }
                }.pickerStyle(.menu)
                Button(L10n.tr("Добавить")) { addChild() }.buttonStyle(SepiaButtonStyle()).disabled(childToAdd == nil)
            }
        }
        .padding(12)
        .background(SepiaTheme.cardBg.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SepiaTheme.cardLine, lineWidth: 1))
    }

    private var partnerNames: String {
        union.partnerIds.compactMap { tree.person(byId: $0)?.listName }.joined(separator: " + ")
    }

    private var availableChildren: [Person] {
        tree.people.filter { !union.partnerIds.contains($0.id) && !union.childrenIds.contains($0.id) }
            .sorted { $0.listName.localizedStandardCompare($1.listName) == .orderedAscending }
    }

    private var availablePartners: [Person] {
        tree.people.filter { $0.id != subject.id && !union.childrenIds.contains($0.id) }
            .sorted { $0.listName.localizedStandardCompare($1.listName) == .orderedAscending }
    }

    private var partnerBinding: Binding<UUID?> {
        Binding(
            get: { union.partnerIds.first { $0 != subject.id } },
            set: { partnerID in
                if union.partner1Id == subject.id { union.partner2Id = partnerID }
                else if union.partner2Id == subject.id { union.partner1Id = partnerID }
                else {
                    union.partner1Id = subject.id
                    union.partner2Id = partnerID
                }
            }
        )
    }

    private func parentageBinding(childID: UUID) -> Binding<ParentageKind> {
        Binding(
            get: {
                tree.parentLinks.first(where: { $0.unionID == union.id && $0.parentID == subject.id && $0.childID == childID })?.kind ?? .biological
            },
            set: { kind in
                if let index = tree.parentLinks.firstIndex(where: { $0.unionID == union.id && $0.parentID == subject.id && $0.childID == childID }) {
                    tree.parentLinks[index].kind = kind
                } else {
                    tree.parentLinks.append(ParentLink(parentID: subject.id, childID: childID, unionID: union.id, kind: kind))
                }
            }
        )
    }

    private func addChild() {
        guard let childToAdd else { return }
        union.childrenIds.append(childToAdd)
        for parentID in union.partnerIds {
            tree.parentLinks.append(ParentLink(parentID: parentID, childID: childToAdd, unionID: union.id))
        }
        self.childToAdd = nil
    }
}

private struct UnionEventDraftEditor: View {
    let kind: GenealogyEvent.Kind
    let union: Union
    let attachments: [Attachment]
    @State private var enabled: Bool
    @State private var dateText: String
    @State private var endText: String
    @State private var qualifier: GenealogyDate.Qualifier
    @State private var placeText: String
    @State private var selectedPlace: PlaceEntry?
    @State private var notes: String
    @State private var mediaIDs: Set<String>

    init(kind: GenealogyEvent.Kind, union: Union, attachments: [Attachment]) {
        self.kind = kind
        self.union = union
        self.attachments = attachments
        let event = union.event(ofKind: kind)
        _enabled = State(initialValue: event != nil)
        _dateText = State(initialValue: event?.date?.start?.displayValue ?? event?.date?.rawValue ?? "")
        _endText = State(initialValue: event?.date?.end?.displayValue ?? "")
        _qualifier = State(initialValue: event?.date?.qualifier ?? .exact)
        _placeText = State(initialValue: event?.place?.displayName ?? "")
        _notes = State(initialValue: event?.notes ?? "")
        _mediaIDs = State(initialValue: Set(event?.mediaIDs ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(eventTitle, isOn: $enabled).toggleStyle(.checkbox)
                .font(SepiaTheme.body(size: 13)).foregroundStyle(SepiaTheme.ink)
            if enabled {
                SepiaDateField(label: L10n.tr("ДАТА"), text: $dateText, qualifier: $qualifier, endText: $endText)
                PlacePickerField(label: L10n.tr("МЕСТО"), text: $placeText, placeholder: "—") { selectedPlace = $0; commit() }
                SepiaNotesField(label: L10n.tr("ЗАМЕТКИ"), text: $notes, placeholder: "—")
                if !attachments.isEmpty {
                    Menu(L10n.tr("Медиа (\(mediaIDs.count))")) {
                        ForEach(attachments) { attachment in
                            Toggle(attachment.originalName, isOn: Binding(
                                get: { mediaIDs.contains(attachment.id.uuidString) },
                                set: { selected in
                                    if selected { mediaIDs.insert(attachment.id.uuidString) }
                                    else { mediaIDs.remove(attachment.id.uuidString) }
                                    commit()
                                }
                            ))
                        }
                    }.menuStyle(.borderlessButton)
                }
            }
        }
        .onChange(of: enabled) { _, _ in commit() }
        .onChange(of: dateText) { _, _ in commit() }
        .onChange(of: endText) { _, _ in commit() }
        .onChange(of: qualifier) { _, _ in commit() }
        .onChange(of: placeText) { _, _ in commit() }
        .onChange(of: notes) { _, _ in commit() }
    }

    private var eventTitle: String {
        switch kind {
        case .partnership: L10n.tr("Партнёрство")
        case .marriage: L10n.tr("Брак")
        case .separation: L10n.tr("Раздельное проживание")
        case .divorce: L10n.tr("Развод")
        default: kind.rawValue
        }
    }

    private func commit() {
        guard enabled else {
            union.events.removeAll { $0.kind == kind }
            if kind == .marriage { union.marriageDate = nil; union.marriagePlace = nil }
            if [.divorce, .separation].contains(kind), union.status == kind.rawValue { union.status = nil }
            return
        }
        let range = qualifier == .between || qualifier == .fromTo
        let date = dateText.nilIfEmpty.map { GenealogyDate(userInput: $0, qualifier: qualifier, endValue: range ? endText : nil) }
        let place: PlaceReference? = if let selectedPlace, selectedPlace.displayName == placeText {
            selectedPlace.placeReference
        } else {
            placeText.nilIfEmpty.map { PlaceReference(displayName: $0, isCustom: true) }
        }
        let old = union.event(ofKind: kind)
        let event = GenealogyEvent(
            id: old?.id ?? UUID(),
            kind: kind,
            value: old?.value,
            date: date,
            place: place,
            notes: notes.nilIfEmpty,
            citations: old?.citations ?? [],
            mediaIDs: Array(mediaIDs).sorted(),
            rawGEDCOMBranches: old?.rawGEDCOMBranches ?? []
        )
        union.replaceEvent(event)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
