import AppKit
import SwarmCore
import SwiftUI

struct InspectorPanel: View {
    @Binding var person: Person?
    let tree: FamilyTree
    var store: TreeStore
    @Binding var width: CGFloat
    var onEdit: ((Person) -> Void)?
    var onDelete: ((Person) -> Void)?
    var onMakeHome: ((Person) -> Void)?

    private let minWidth: CGFloat = 260
    private let maxWidth: CGFloat = 500

    /// Trail of people visited via relative links, so deep navigation can step back.
    @State private var history: [Person] = []
    /// Set when we change `person` ourselves (relative link / back) so the external-
    /// selection observer doesn't wipe the trail on our own navigation.
    @State private var internalNav = false

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
            .onChange(of: person.id) { _, _ in
                // A change we didn't make (a new canvas selection) starts a fresh
                // context, so drop the relative-navigation trail.
                if internalNav { internalNav = false } else { history = [] }
            }
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
                if !history.isEmpty {
                    Button {
                        guard let prev = history.popLast() else { return }
                        internalNav = true
                        // Re-resolve against the live tree: an undo since this entry
                        // was pushed may have replaced that Person instance.
                        self.person = tree.person(byId: prev.id) ?? prev
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                            Text(L10n.tr("Назад")).font(SepiaTheme.ui(size: 11))
                        }
                        .foregroundColor(SepiaTheme.accent2)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("Вернуться к предыдущей персоне"))
                    .accessibilityLabel(L10n.tr("Назад к предыдущей персоне"))
                    .padding(.bottom, 2)
                }
                Text(person.displayName(language: .current))
                    .font(SepiaTheme.display(size: 19))
                    .fontWeight(.semibold)
                    .foregroundColor(SepiaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let maiden = person.maidenName, !maiden.isEmpty, maiden != person.surname {
                    Text(L10n.tr("урожд. \(maiden)"))
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
            if tree.homePersonId != person.id, let onMakeHome {
                actionBtn("house", fg: fg, bg: bg, stroke: stroke) { onMakeHome(person) }
                    .help(L10n.tr("Сделать домашней персоной"))
                    .accessibilityLabel(L10n.tr("Сделать домашней персоной"))
            }
            if let onDelete {
                actionBtn("trash", fg: tinted ? .red.opacity(0.85) : .red.opacity(0.7), bg: bg, stroke: stroke) { onDelete(person) }
                    .help(L10n.tr("Удалить"))
                    .accessibilityLabel(L10n.tr("Удалить персону"))
            }
            if let onEdit {
                actionBtn("pencil", fg: fg, bg: bg, stroke: stroke) { onEdit(person) }
                    .help(L10n.tr("Редактировать"))
                    .accessibilityLabel(L10n.tr("Редактировать"))
            }
            actionBtn("xmark", fg: fg, bg: bg, stroke: stroke) { self.person = nil }
                .help(L10n.tr("Закрыть"))
                .accessibilityLabel(L10n.tr("Закрыть карточку"))
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
        .buttonStyle(InspectorActionButtonStyle())
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
        fieldSection(L10n.tr("Личность"), [
            (L10n.tr("ИМЕНА"), p.givenNames),
            (L10n.tr("ОТЧЕСТВО"), p.patronymic ?? ""),
            (L10n.tr("ФАМИЛИЯ"), p.surname),
            (L10n.tr("ДЕВИЧЬЯ"), p.maidenName ?? ""),
            (L10n.tr("ПОЛ"), p.sex == .unknown ? "" : p.sex.displayName),
        ])
    }

    private func birthSection(_ p: Person) -> some View {
        var rows: [(String, String)] = [
            (L10n.tr("ДАТА"), p.birthDate ?? ""),
            (L10n.tr("МЕСТО"), p.birthPlace ?? ""),
        ]
        if let lat = p.birthLat, let lon = p.birthLon {
            rows.append((L10n.tr("КООРДИНАТЫ"), String(format: "%.5f, %.5f", lat, lon)))
        }
        return fieldSection(L10n.tr("Рождение"), rows)
    }

    private func deathSection(_ p: Person) -> some View {
        fieldSection(L10n.tr("Смерть и погребение"), deathRows(p))
    }

    private func deathRows(_ p: Person) -> [(String, String)] {
        var rows: [(String, String)] = []
        if !p.isLiving {
            rows.append((L10n.tr("ДАТА"), p.deathDate ?? ""))
            rows.append((L10n.tr("МЕСТО СМЕРТИ"), p.deathPlace ?? ""))
            if let lat = p.deathLat, let lon = p.deathLon {
                rows.append((L10n.tr("КООРДИНАТЫ"), String(format: "%.5f, %.5f", lat, lon)))
            }
        }
        rows.append((L10n.tr("ЗАХОРОНЕНИЕ"), p.burialPlace ?? ""))
        if let lat = p.burialLat, let lon = p.burialLon {
            rows.append((L10n.tr("КООРДИНАТЫ МОГИЛЫ"), String(format: "%.5f, %.5f", lat, lon)))
        }
        return rows
    }

    private func lifeSection(_ p: Person) -> some View {
        fieldSection(L10n.tr("Жизнь"), [
            (L10n.tr("ПРОФЕССИЯ"), p.occupation ?? ""),
            (L10n.tr("ОБРАЗОВАНИЕ"), p.education ?? ""),
            (L10n.tr("ЗАМЕТКИ"), p.notes ?? ""),
        ])
    }

    @ViewBuilder
    private func mapSection(_ p: Person) -> some View {
        let hasPlace = (p.birthPlace?.isEmpty == false) || (p.deathPlace?.isEmpty == false)
            || (p.birthLat != nil && p.birthLon != nil) || (p.deathLat != nil && p.deathLon != nil)
        if hasPlace {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L10n.tr("Карта"))
                PersonMiniMap(person: p).padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func attachmentsSection(_ p: Person) -> some View {
        if !p.attachments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L10n.tr("Файлы"))
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
                                Text(att.format.isEmpty ? L10n.tr("Файл") : att.format)
                                    .font(SepiaTheme.ui(size: 9.5)).tracking(1).foregroundColor(SepiaTheme.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("Открыть «\(att.originalName)»"))
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
                SectionHeader(title: L10n.tr("Родственные"))
                if let f = parents.father { relRow(L10n.tr("Отец"), f) }
                if let m = parents.mother { relRow(L10n.tr("Мать"), m) }
                ForEach(spouses, id: \.id) { s in relRow(L10n.tr("Супруг"), s) }
                ForEach(children, id: \.id) { c in relRow(L10n.tr("Ребёнок"), c) }
                ForEach(siblings, id: \.id) { s in
                    relRow(s.sex == .male ? L10n.tr("Брат") : s.sex == .female ? L10n.tr("Сестра") : L10n.tr("Брат/сестра"), s)
                }
            }
        }
    }

    /// Label above value, matching `FieldRow` — a fixed label column here made these
    /// rows the only ones in the panel whose text started further right.
    private func relRow(_ tag: String, _ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tag.uppercased())
                .font(SepiaTheme.ui(size: 11)).tracking(1.0).foregroundColor(SepiaTheme.inkSoft)
            Button(p.displayName(language: .current)) {
                if let current = self.person { history.append(current) }
                internalNav = true
                self.person = p
            }
            .buttonStyle(RelativeLinkButtonStyle())
            .font(SepiaTheme.body(size: 14))
            .multilineTextAlignment(.leading)
            .underline(color: SepiaTheme.accent2.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

/// The inspector's small square actions (home, delete, edit, close) were `.plain`, which on
/// macOS means no hover and no press state at all — four unlit targets in the busiest corner
/// of the panel. This gives them the same hover-lifts / press-dips language as the toolbar.
private struct InspectorActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InspectorActionSurface(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct InspectorActionSurface<Label: View>: View {
        let label: Label
        let isPressed: Bool
        @State private var isHovering = false

        var body: some View {
            label
                .brightness(isHovering && !isPressed ? 0.04 : 0)
                .opacity(isPressed ? 0.7 : 1)
                .scaleEffect(isPressed ? 0.92 : (isHovering ? 1.06 : 1.0))
                .sepiaMotion(SepiaMotion.press, value: isPressed)
                .sepiaMotion(SepiaMotion.hover, value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

/// A relative's name in the panel is a navigation link but rendered as bare text; without a
/// hover cue there is nothing to say it can be clicked.
private struct RelativeLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RelativeLinkSurface(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct RelativeLinkSurface<Label: View>: View {
        let label: Label
        let isPressed: Bool
        @State private var isHovering = false

        var body: some View {
            label
                .foregroundColor(isHovering || isPressed ? SepiaTheme.accent : SepiaTheme.ink)
                .opacity(isPressed ? 0.7 : 1)
                .sepiaMotion(SepiaMotion.hover, value: isHovering)
                .sepiaMotion(SepiaMotion.press, value: isPressed)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(SepiaTheme.ui(size: 11)).tracking(1.2).foregroundColor(SepiaTheme.accent2).fontWeight(.semibold)
            .padding(.top, 16).padding(.bottom, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(SepiaTheme.fieldLine).frame(height: 1) }
            .padding(.bottom, 10)
    }
}

struct FieldRow: View {
    let label: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(SepiaTheme.ui(size: 11)).tracking(1.0).foregroundColor(SepiaTheme.inkSoft)
            Text(value.isEmpty ? "—" : value).font(SepiaTheme.body(size: 14)).foregroundColor(SepiaTheme.ink)
        }
        .padding(.bottom, 12)
    }
}
