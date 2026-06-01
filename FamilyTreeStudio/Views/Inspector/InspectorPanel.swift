import SwiftUI

struct InspectorPanel: View {
    @Binding var person: Person?
    let tree: FamilyTree
    @Binding var width: CGFloat
    var onEdit: ((Person) -> Void)? = nil
    var onDelete: ((Person) -> Void)? = nil
    
    private let minWidth: CGFloat = 260
    private let maxWidth: CGFloat = 500
    
    var body: some View {
        if let person = person {
            HStack(spacing: 0) {
                // Drag handle
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let newWidth = width - value.translation.width
                                width = min(maxWidth, max(minWidth, newWidth))
                            }
                    )
                    .overlay(Rectangle().fill(SepiaTheme.toolbarLine).frame(width: 1))
                
                VStack(spacing: 0) {
                    inspectorHeader(person)
                    Divider().overlay(SepiaTheme.toolbarLine)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            identitySection(person)
                            birthSection(person)
                            deathSection(person)
                            lifeSection(person)
                            sourcesSection(person)
                            relationshipsSection(person)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }
                }
            }
            .frame(width: width)
            .background(SepiaTheme.panelBg)
        }
    }
    
    private func inspectorHeader(_ person: Person) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let data = person.photoData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [SepiaTheme.photoA, SepiaTheme.photoB], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Path { path in
                        for i in stride(from: 0, to: 80, by: 6) {
                            path.move(to: CGPoint(x: CGFloat(i), y: 0))
                            path.addLine(to: CGPoint(x: 0, y: CGFloat(i)))
                        }
                    }
                    .stroke(SepiaTheme.photoB.opacity(0.5), lineWidth: 0.5)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(width: 56, height: 56)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(person.listName)
                    .font(SepiaTheme.display(size: 19))
                    .fontWeight(.semibold)
                    .foregroundColor(SepiaTheme.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let maiden = person.maidenName, !maiden.isEmpty, maiden != person.surname {
                    Text("урожд. \(maiden)")
                        .font(SepiaTheme.body(size: 12.5))
                        .italic()
                        .foregroundColor(SepiaTheme.inkSoft)
                }
                Text(person.lifespan.isEmpty ? "—" : person.lifespan)
                    .font(SepiaTheme.body(size: 13))
                    .foregroundColor(SepiaTheme.inkSoft)
            }
            .frame(minWidth: 120, alignment: .leading)
            
            Spacer(minLength: 4)
            
            VStack(spacing: 4) {
                if let onDelete = onDelete {
                    Button { onDelete(person) } label: {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundColor(.red.opacity(0.7))
                            .frame(width: 30, height: 30)
                            .background(SepiaTheme.cardBg)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Удалить")
                }
                if let onEdit = onEdit {
                    Button { onEdit(person) } label: {
                        Image(systemName: "pencil").font(.system(size: 12)).foregroundColor(SepiaTheme.inkSoft)
                            .frame(width: 30, height: 30)
                            .background(SepiaTheme.cardBg)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Редактировать")
                }
                Button { self.person = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 12)).foregroundColor(SepiaTheme.inkSoft)
                        .frame(width: 30, height: 30)
                        .background(SepiaTheme.cardBg)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Закрыть")
            }
        }
        .padding(16)
    }
    
    private func identitySection(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Личность")
            FieldRow(label: "ИМЕНА", value: p.givenNames)
            FieldRow(label: "ОТЧЕСТВО", value: p.patronymic ?? "—")
            FieldRow(label: "ФАМИЛИЯ", value: p.surname)
            FieldRow(label: "ДЕВИЧЬЯ", value: p.maidenName ?? "—")
            FieldRow(label: "ПОЛ", value: p.sex.displayName)
        }
    }
    
    private func birthSection(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Рождение")
            FieldRow(label: "ДАТА", value: p.birthDate ?? "—")
            FieldRow(label: "МЕСТО", value: p.birthPlace ?? "—")
        }
    }
    
    private func deathSection(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Смерть и погребение")
            FieldRow(label: "ДАТА", value: p.isLiving ? "— (жив)" : (p.deathDate ?? "—"))
            FieldRow(label: "МЕСТО", value: p.deathPlace ?? "—")
            FieldRow(label: "ЗАХОРОНЕНИЕ", value: p.burialPlace ?? "—")
        }
    }
    
    private func lifeSection(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Жизнь")
            FieldRow(label: "ПРОФЕССИЯ", value: p.occupation ?? "—")
            FieldRow(label: "ОБРАЗОВАНИЕ", value: p.education ?? "—")
            if let notes = p.notes, !notes.isEmpty { FieldRow(label: "ЗАМЕТКИ", value: notes) }
        }
    }
    
    private func sourcesSection(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Источники")
            if p.sources.isEmpty {
                Text("Источники не указаны").font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.inkSoft).padding(.bottom, 8)
            } else {
                ForEach(p.sources, id: \.self) { s in
                    Text("• \(s)").font(SepiaTheme.body(size: 12.5)).foregroundColor(SepiaTheme.ink).padding(.bottom, 4)
                }
            }
        }
    }
    
    private func relationshipsSection(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Родственные")
            let idx = FamilyIndex(tree: tree)
            let parents = idx.parentsOf(p)
            let spouses = idx.spousesOf(p)
            let children = idx.childrenOf(p)
            let siblings = idx.siblingsOf(p)
            
            if let f = parents.father { relRow("Отец", f) }
            if let m = parents.mother { relRow("Мать", m) }
            ForEach(spouses, id: \.id) { s in relRow("Супруг", s) }
            ForEach(children, id: \.id) { c in relRow("Ребёнок", c) }
            ForEach(siblings, id: \.id) { s in
                relRow(s.sex == .male ? "Брат" : s.sex == .female ? "Сестра" : "Брат/сестра", s)
            }
            
            if parents.father == nil && parents.mother == nil && spouses.isEmpty && children.isEmpty && siblings.isEmpty {
                Text("Родственные не указаны").font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.inkSoft)
            }
        }
    }
    
    private func relRow(_ tag: String, _ p: Person) -> some View {
        HStack(spacing: 8) {
            Text(tag.uppercased())
                .font(SepiaTheme.ui(size: 9.5)).tracking(1.2).foregroundColor(SepiaTheme.inkSoft)
                .frame(width: 60, alignment: .leading)
            Button(p.listName) { self.person = p }
                .buttonStyle(.plain)
                .font(SepiaTheme.body(size: 13.5))
                .foregroundColor(SepiaTheme.ink)
                .underline(color: SepiaTheme.accent2.opacity(0.5))
        }
        .padding(.bottom, 6)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(SepiaTheme.ui(size: 10)).tracking(2).foregroundColor(SepiaTheme.accent2).fontWeight(.semibold)
            .padding(.top, 16).padding(.bottom, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(SepiaTheme.fieldLine).frame(height: 1) }
            .padding(.bottom, 10)
    }
}

struct FieldRow: View {
    let label: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(SepiaTheme.ui(size: 9.5)).tracking(1.5).foregroundColor(SepiaTheme.inkSoft)
            Text(value.isEmpty ? "—" : value).font(SepiaTheme.body(size: 14)).foregroundColor(SepiaTheme.ink)
        }
        .padding(.bottom, 12)
    }
}
