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
    /// Opening the portrait is the workspace's job, not the panel's: a sheet is its own
    /// window, so a click on the dimmed canvas behind it never reaches us. The full-size
    /// portrait is presented as an overlay over the whole window instead.
    var onOpenPortrait: ((Person) -> Void)?

    private let minWidth: CGFloat = 260
    private let maxWidth: CGFloat = 500

    /// Trail of people visited via relative links, so deep navigation can step back.
    @State private var history: [Person] = []
    /// Set when we change `person` ourselves (relative link / back) so the external-
    /// selection observer doesn't wipe the trail on our own navigation.
    @State private var internalNav = false
    /// Hover over the resize gutter, which is otherwise invisible: the grabber only
    /// appears once the pointer is close enough to use it.
    @State private var resizeHovering = false

    /// The panel floats rather than butting against the window edge, so its corner
    /// radius is a real one. Everything inside it stays concentric at a smaller radius.
    private let panelShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        if let person {
            HStack(spacing: 0) {
                resizeGutter
                panel(person)
            }
            .frame(width: width)
            .onChange(of: person.id) { _, _ in
                // A change we didn't make (a new canvas selection) starts a fresh
                // context, so drop the relative-navigation trail.
                if internalNav { internalNav = false } else { history = [] }
            }
        }
    }

    /// The resize target. A hairline rule between two panes is chrome from the old
    /// design; a floating panel is separated by the gap itself, so the only mark here
    /// is a grabber that appears when the pointer can act on it.
    private var resizeGutter: some View {
        Capsule()
            .fill(SepiaTheme.ink.opacity(resizeHovering ? 0.32 : 0))
            .frame(width: 4, height: 46)
            .frame(maxHeight: .infinity)
            .frame(width: 11)
            .contentShape(Rectangle())
            .sepiaMotion(SepiaMotion.hover, value: resizeHovering)
            .onHover { hovering in
                resizeHovering = hovering
                // .set() (not push/pop): the panel is conditionally removed with a
                // transition, so a hover-exit can be missed — push/pop would then leak
                // the resize cursor onto the stack.
                if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newWidth = width - value.translation.width
                        width = min(maxWidth, max(minWidth, newWidth))
                    }
            )
            .accessibilityHidden(true)
    }

    /// One solid card carrying the whole record, lifted off the workspace paper by its
    /// shadow rather than by translucency.
    private func panel(_ person: Person) -> some View {
        details(person)
            // Opaque paper, not glass: the record has to stay readable over whatever
            // part of the tree happens to sit behind it.
            .background(SepiaTheme.panelBg, in: panelShape)
            .overlay {
                // A white hairline, not a palette colour: it is the glass edge catching
                // light, the same highlight the material draws along its own top.
                panelShape.strokeBorder(.white.opacity(0.55), lineWidth: 1)
            }
            .clipShape(panelShape)
            .shadow(color: SepiaTheme.ink.opacity(0.26), radius: 18, y: 8)
            .padding(.vertical, 10)
            .padding(.trailing, 10)
    }

    /// The header scrolls away with the record rather than hovering over it: this is a
    /// card being read top to bottom, not a window with a title bar, and a pinned bar
    /// would spend most of a tall record repeating a name the reader has already left.
    private func details(_ person: Person) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                inspectorHeader(person)

                VStack(alignment: .leading, spacing: 0) {
                    identitySection(person)
                    birthSection(person)
                    deathSection(person)
                    mapSection(person)
                    lifeSection(person)
                    attachmentsSection(person)
                    linksSection(person)
                    relationshipsSection(person)
                }
                .textSelection(.enabled)

                deleteFooter(person)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .scrollContentBackground(.hidden)
        // The overlay scroller lands on the trailing edge, right over the close button,
        // and swallows the click until it fades. The fades below already say there is
        // more card; the bar only cost us a hit target.
        .scrollIndicators(.hidden)
        // Both ends of the record dissolve instead of being sheared off by the panel's
        // own corners. Fixed heights, not fractions: the fade must stay the same weight
        // whether the window is 600pt tall or 1400. `.scrollEdgeEffectStyle` would be
        // the system route, but it only draws for a system bar, and this card has none.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 12)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
            }
        }
    }

    // MARK: - Header

    /// Two bands: where you are and what you can do about this record, then who it is.
    /// The old header interleaved them — a Back button wedged above the name, actions
    /// stacked in the margin — so no row of it was a row of anything.
    private func inspectorHeader(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            navRow(person)
            identityRow(person)
        }
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    /// Everything that acts on the card rather than on the record inside it, gathered
    /// on one line: leave to the previous person, edit this one, close the card.
    private func navRow(_ person: Person) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if !history.isEmpty {
                    Button {
                        guard let prev = history.popLast() else { return }
                        internalNav = true
                        // Re-resolve against the live tree: an undo since this entry
                        // was pushed may have replaced that Person instance.
                        self.person = tree.person(byId: prev.id) ?? prev
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                            Text(L10n.tr("Назад")).font(SepiaTheme.ui(size: 11))
                        }
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .foregroundStyle(SepiaTheme.accent2)
                    .controlSize(.small)
                    .help(L10n.tr("Вернуться к предыдущей персоне"))
                    .accessibilityLabel(L10n.tr("Назад к предыдущей персоне"))
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    // The same tracked capitals the wordmark and the library use to say
                    // which room you are in. Holds the row's height when Back is absent,
                    // so the header doesn't grow and shrink as you walk the family.
                    SepiaTrackedLabel(L10n.tr("Персона"))
                        .frame(height: 20)
                }

                Spacer(minLength: 8)

                // A pair of matching circles. Only the accent separates them: one acts on
                // the record, one dismisses the card. The word is carried by the tooltip
                // and the accessibility label, where a pencil has never needed it.
                if let onEdit {
                    Button { onEdit(person) } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .tint(SepiaTheme.accent)
                    .help(L10n.tr("Редактировать"))
                    .accessibilityLabel(L10n.tr("Редактировать"))
                }

                Button { self.person = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(SepiaTheme.ink)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help(L10n.tr("Закрыть карточку"))
                .accessibilityLabel(L10n.tr("Закрыть карточку"))
            }
        }
        .sepiaMotion(SepiaMotion.state, value: history.isEmpty)
    }

    private func identityRow(_ person: Person) -> some View {
        HStack(alignment: .top, spacing: 13) {
            portrait(person)

            VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName(language: .current))
                    .font(SepiaTheme.display(size: 20))
                    .fontWeight(.semibold)
                    .foregroundColor(SepiaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
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
                        .padding(.top, 1)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 3:4 like every other portrait in the app, but rounded and inset rather than
    /// bled into the panel's corner — a square-cropped photo jammed against a rounded
    /// glass edge was the single loudest mismatch in the old header. Absent photos get
    /// the tree node's placeholder instead of collapsing the row. A real photo is a
    /// button onto the full-size copy; the placeholder stands for nothing to open.
    @ViewBuilder
    private func portrait(_ person: Person) -> some View {
        if person.photoData != nil {
            Button { onOpenPortrait?(person) } label: { portraitPlate(person) }
                .buttonStyle(.plain)
                .onHover { $0 ? NSCursor.pointingHand.set() : NSCursor.arrow.set() }
                .help(L10n.tr("Открыть фото"))
                .accessibilityLabel(L10n.tr("Открыть фото"))
        } else {
            portraitPlate(person).accessibilityHidden(true)
        }
    }

    private func portraitPlate(_ person: Person) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Group {
            if let data = person.photoData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [SepiaTheme.photoA, SepiaTheme.photoB],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Image(systemName: "person.fill")
                        .font(.system(size: 26))
                        .foregroundColor(SepiaTheme.inkSoft.opacity(0.42))
                }
            }
        }
        .frame(width: 84, height: 84 / SepiaTheme.portraitAspect)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.55), lineWidth: 1) }
        .shadow(color: SepiaTheme.ink.opacity(0.18), radius: 6, y: 3)
    }

    /// Deleting a person is the last thing on the card and never on the way to anything
    /// else: it sits past the whole record, labelled with what it destroys, so it can
    /// only be reached deliberately. It stays a quiet glass button — the accent belongs
    /// to Edit, and a red slab here would be the loudest thing in the panel.
    @ViewBuilder
    private func deleteFooter(_ person: Person) -> some View {
        if let onDelete {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(SepiaTheme.fieldLine)
                    .frame(height: 1)
                    .padding(.bottom, 16)

                Button(role: .destructive) { onDelete(person) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L10n.tr("Удалить персону"))
                            .font(SepiaTheme.ui(size: 12))
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(SepiaTheme.danger)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .help(L10n.tr("Удалить персону"))
                .accessibilityLabel(L10n.tr("Удалить персону"))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 20)
        }
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
        // The portrait is a file of this person like any other, so it is listed with
        // them. It stays in Media/ — this row is a view of it, not a second copy.
        let portraitImage = p.photoData.flatMap(NSImage.init(data:))
        if portraitImage != nil || !p.attachments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L10n.tr("Файлы"))
                if let portraitImage {
                    Button { onOpenPortrait?(p) } label: {
                        fileRow(title: L10n.tr("Портрет"), format: portraitFormat(p)) {
                            Image(nsImage: portraitImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("Открыть фото"))
                    .padding(.bottom, 8)
                }
                ForEach(p.attachments) { att in
                    let url = store.attachmentURL(att, in: tree)
                    Button { NSWorkspace.shared.open(url) } label: {
                        fileRow(title: att.originalName, format: att.format) {
                            AttachmentThumbnail(url: url, isImage: att.isImage, format: att.format, size: 40)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("Открыть «\(att.originalName)»"))
                    .padding(.bottom, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func linksSection(_ p: Person) -> some View {
        if !p.links.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L10n.tr("Ссылки"))
                ForEach(p.links) { link in
                    Button {
                        if let url = link.openableURL { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .font(.system(size: 13))
                                .foregroundColor(SepiaTheme.inkSoft)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 5).fill(SepiaTheme.photoA.opacity(0.3)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.displayTitle)
                                    .font(SepiaTheme.body(size: 13))
                                    .foregroundColor(SepiaTheme.ink)
                                    .lineLimit(1).truncationMode(.middle)
                                Text(link.displayHost)
                                    .font(SepiaTheme.ui(size: 9.5)).tracking(1)
                                    .foregroundColor(SepiaTheme.inkSoft)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(link.openableURL == nil)
                    .help(L10n.tr("Открыть «\(link.displayTitle)»"))
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func fileRow(title: String, format: String, @ViewBuilder thumbnail: () -> some View) -> some View {
        HStack(spacing: 10) {
            thumbnail()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SepiaTheme.body(size: 13))
                    .foregroundColor(SepiaTheme.ink)
                    .lineLimit(1).truncationMode(.middle)
                Text(format.isEmpty ? L10n.tr("Файл") : format)
                    .font(SepiaTheme.ui(size: 9.5)).tracking(1).foregroundColor(SepiaTheme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// Portraits are stored as JPEG unless they came in from an import that kept its
    /// own extension.
    private func portraitFormat(_ p: Person) -> String {
        let ext = (p.photoFilename as NSString?)?.pathExtension.uppercased() ?? ""
        return ext.isEmpty ? "JPEG" : ext
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
            Button {
                if let current = self.person { history.append(current) }
                internalNav = true
                self.person = p
            } label: {
                HStack(spacing: 8) {
                    Text(p.displayName(language: .current))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SepiaTheme.inkSoft)
                }
            }
            .buttonStyle(RelativeLinkButtonStyle())
            .font(SepiaTheme.body(size: 14))
            .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

/// The portrait at the size the file actually holds. The card can only ever show a
/// thumbnail of it, and the photo is usually the one thing on a record worth looking at
/// closely — a face, a uniform, a date written on the back.
///
/// An overlay over the workspace rather than a sheet: a sheet is a separate window, and
/// the dimmed canvas around it belongs to the window underneath, which modality has
/// already stopped answering the mouse. Owning the dimmer is what lets a click on it close.
struct PortraitPreview: View {
    let image: NSImage?
    let name: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // The dimmer, and the whole reason this is not a sheet. A Button rather than
            // an `onTapGesture`: the canvas underneath carries a DragGesture, and a bare
            // tap gesture on the scrim never resolves against it.
            Button(action: onClose) {
                SepiaTheme.ink.opacity(0.34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ignoresSafeArea()
            .accessibilityLabel(L10n.tr("Закрыть"))

            // Keeps a band of dimmer visible all round, so there is always something to
            // click even when the window is barely bigger than the card.
            card.padding(28)
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: SepiaTheme.ink.opacity(0.24), radius: 14, y: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(L10n.tr("Портрет не найден"))
                    .font(SepiaTheme.body(size: 14))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 10) {
                Text(name)
                    .font(SepiaTheme.body(size: 13))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                Button(L10n.tr("Закрыть")) { onClose() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        // A ceiling, not a fixed size: in a short window the card shrinks with it instead
        // of running off both ends.
        .frame(maxWidth: 560, maxHeight: 680)
        .background(SepiaTheme.panelBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: SepiaTheme.ink.opacity(0.34), radius: 30, y: 14)
        // Stops a click on the card itself from reaching the dimmer behind it.
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {}
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
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background {
                    // A wash, not the opaque field fill: on a glass panel a solid
                    // hover plate reads as a second surface pasted over the first.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SepiaTheme.ink.opacity(isHovering ? 0.07 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
