import AppKit
import FamilyTreeCore
import SwiftUI

struct InspectorPanel: View {
    @Binding var person: Person?
    let tree: FamilyTree
    var store: TreeStore
    @Binding var width: CGFloat
    var onEdit: ((Person) -> Void)?
    var onDelete: ((Person) -> Void)?

    private let minWidth: CGFloat = 260
    private let maxWidth: CGFloat = 500

    var body: some View {
        if let person {
            HStack(spacing: 0) {
                // Drag handle
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        // .set() (not push/pop): the panel is conditionally removed
                        // with a transition, so a hover-exit can be missed — push/pop
                        // would then leak the resize cursor onto the stack.
                        if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
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
                            mapSection(person)
                            lifeSection(person)
                            attachmentsSection(person)
                            relationshipsSection(person)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .textSelection(.enabled)
                    }
                }
            }
            .frame(width: width)
            .background(SepiaTheme.panelBg)
        }
    }

    private func inspectorHeader(_ person: Person) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Portrait photo — same 3:4 ratio as the tree node, flush to the top-left
            // edges (no placeholder when absent).
            if let data = person.photoData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 160)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(person.listName)
                    .font(SepiaTheme.display(size: 19))
                    .fontWeight(.semibold)
                    .foregroundColor(SepiaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let maiden = person.maidenName, !maiden.isEmpty, maiden != person.surname {
                    Text("урожд. \(maiden)")
                        .font(SepiaTheme.body(size: 12.5))
                        .italic()
                        .foregroundColor(SepiaTheme.inkSoft)
                }
                if !person.lifespan.isEmpty {
                    Text(person.lifespan)
                        .font(SepiaTheme.body(size: 13))
                        .foregroundColor(SepiaTheme.inkSoft)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .padding(.top, 14)

            actionButtons(person: person, tinted: false)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .padding(.trailing, 14)
        }
    }

    @ViewBuilder
    private func actionButtons(person: Person, tinted: Bool) -> some View {
        let bg = tinted ? Color.black.opacity(0.35) : SepiaTheme.cardBg
        let fg = tinted ? Color.white : SepiaTheme.inkSoft
        let stroke = tinted ? Color.white.opacity(0.25) : SepiaTheme.cardLine

        VStack(spacing: 4) {
            if let onDelete {
                actionBtn("trash", fg: tinted ? .red.opacity(0.85) : .red.opacity(0.7), bg: bg, stroke: stroke) { onDelete(person) }
                    .help("Удалить")
            }
            if let onEdit {
                actionBtn("pencil", fg: fg, bg: bg, stroke: stroke) { onEdit(person) }
                    .help("Редактировать")
            }
            actionBtn("xmark", fg: fg, bg: bg, stroke: stroke) { self.person = nil }
                .help("Закрыть")
        }
    }

    private func actionBtn(_ image: String, fg: Color, bg: Color, stroke: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image).font(.system(size: 12)).foregroundColor(fg)
                .frame(width: 30, height: 30)
                .background(bg)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(stroke, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Each section renders only when it has at least one filled field, and within
    // a section only non-empty fields appear.

    @ViewBuilder
    private func fieldSection(_ title: String, _ rows: [(String, String)]) -> some View {
        let filled = rows.filter { !$0.1.isEmpty }
        if !filled.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: title)
                ForEach(filled, id: \.0) { FieldRow(label: $0.0, value: $0.1) }
            }
        }
    }

    private func identitySection(_ p: Person) -> some View {
        fieldSection("Личность", [
            ("ИМЕНА", p.givenNames),
            ("ОТЧЕСТВО", p.patronymic ?? ""),
            ("ФАМИЛИЯ", p.surname),
            ("ДЕВИЧЬЯ", p.maidenName ?? ""),
            ("ПОЛ", p.sex == .unknown ? "" : p.sex.displayName),
        ])
    }

    private func birthSection(_ p: Person) -> some View {
        var rows: [(String, String)] = [
            ("ДАТА", p.birthDate ?? ""),
            ("МЕСТО", p.birthPlace ?? ""),
        ]
        if let lat = p.birthLat, let lon = p.birthLon {
            rows.append(("КООРДИНАТЫ", String(format: "%.5f, %.5f", lat, lon)))
        }
        return fieldSection("Рождение", rows)
    }

    private func deathSection(_ p: Person) -> some View {
        fieldSection("Смерть и погребение", deathRows(p))
    }

    private func deathRows(_ p: Person) -> [(String, String)] {
        var rows: [(String, String)] = []
        if !p.isLiving {
            rows.append(("ДАТА", p.deathDate ?? ""))
            rows.append(("МЕСТО СМЕРТИ", p.deathPlace ?? ""))
            if let lat = p.deathLat, let lon = p.deathLon {
                rows.append(("КООРДИНАТЫ", String(format: "%.5f, %.5f", lat, lon)))
            }
        }
        rows.append(("ЗАХОРОНЕНИЕ", p.burialPlace ?? ""))
        if let lat = p.burialLat, let lon = p.burialLon {
            rows.append(("КООРДИНАТЫ МОГИЛЫ", String(format: "%.5f, %.5f", lat, lon)))
        }
        return rows
    }

    private func lifeSection(_ p: Person) -> some View {
        fieldSection("Жизнь", [
            ("ПРОФЕССИЯ", p.occupation ?? ""),
            ("ОБРАЗОВАНИЕ", p.education ?? ""),
            ("ЗАМЕТКИ", p.notes ?? ""),
        ])
    }

    @ViewBuilder
    private func mapSection(_ p: Person) -> some View {
        let hasPlace = (p.birthPlace?.isEmpty == false) || (p.deathPlace?.isEmpty == false)
            || (p.birthLat != nil && p.birthLon != nil) || (p.deathLat != nil && p.deathLon != nil)
        if hasPlace {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Карта")
                PersonMiniMap(person: p).padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func attachmentsSection(_ p: Person) -> some View {
        if !p.attachments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Файлы")
                ForEach(p.attachments) { att in
                    let url = store.attachmentURL(att, in: tree)
                    Button { NSWorkspace.shared.open(url) } label: {
                        HStack(spacing: 10) {
                            AttachmentThumbnail(url: url, isImage: att.isImage, format: att.format, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(att.originalName)
                                    .font(SepiaTheme.body(size: 13))
                                    .foregroundColor(SepiaTheme.ink)
                                    .lineLimit(1).truncationMode(.middle)
                                Text(att.format.isEmpty ? "Файл" : att.format)
                                    .font(SepiaTheme.ui(size: 9.5)).tracking(1).foregroundColor(SepiaTheme.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Открыть «\(att.originalName)»")
                    .padding(.bottom, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func relationshipsSection(_ p: Person) -> some View {
        let idx = FamilyIndex(tree: tree)
        let parents = idx.parentsOf(p)
        let spouses = idx.spousesOf(p)
        let children = idx.childrenOf(p)
        let siblings = idx.siblingsOf(p)
        let hasAny = parents.father != nil || parents.mother != nil
            || !spouses.isEmpty || !children.isEmpty || !siblings.isEmpty
        if hasAny {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Родственные")
                if let f = parents.father { relRow("Отец", f) }
                if let m = parents.mother { relRow("Мать", m) }
                ForEach(spouses, id: \.id) { s in relRow("Супруг", s) }
                ForEach(children, id: \.id) { c in relRow("Ребёнок", c) }
                ForEach(siblings, id: \.id) { s in
                    relRow(s.sex == .male ? "Брат" : s.sex == .female ? "Сестра" : "Брат/сестра", s)
                }
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
