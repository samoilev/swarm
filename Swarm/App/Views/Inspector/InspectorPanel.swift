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
    /// Opening a photo is the workspace's job, not the panel's: a sheet is its own
    /// window, so a click on the dimmed canvas behind it never reaches us. The full-size
    /// photo is presented as an overlay over the whole window instead. The index is into
    /// `Person.photoRefs`, so the viewer opens on the picture that was clicked.
    var onOpenPhoto: ((Person, Int) -> Void)?
    /// Switching the workspace to the map is the workspace's job too — the panel only
    /// says which person the map should open on.
    var onOpenMap: ((Person) -> Void)?

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
    /// Bottom edge of the identity row in the scroller's own space, so the pinned
    /// controls can tell when the record has climbed up to them. Starts below
    /// everything: nothing has scrolled yet.
    @State private var identityBottom: CGFloat = .greatestFiniteMagnitude

    /// Name of the scroller's coordinate space, the frame `identityBottom` is read in.
    private static let scrollSpace = "inspectorScroll"

    /// Where the pinned row ends: its 13pt inset plus the taller of one 24pt circle and
    /// the two-line name beside it, which at 15pt over 13pt comes to 34.
    private let barBottom: CGFloat = 47

    /// Paper first, name second, 24pt of scroll apart: the rows are already dissolving
    /// into the backdrop before the small name arrives, and the big one is long gone by
    /// then, so the card never shows the same name twice.
    private var barCovered: Bool { identityBottom < barBottom + 24 }
    private var showBarName: Bool { identityBottom < barBottom }

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
    /// The exception is the two controls that act on the card rather than on the record
    /// — `pinnedActions` keeps them over the scroller, so a deep record never has to be
    /// scrolled back up to be closed.
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
                    sourcesSection(person)
                    externalIDsSection(person)
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
        .coordinateSpace(.named(Self.scrollSpace))
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
        // Outside the mask, so the top fade never dims the one pair of controls that is
        // always supposed to be reachable.
        .overlay(alignment: .top) { pinnedActions(person) }
    }

    // MARK: - Header

    /// Two bands: where you are and what you can do about this record, then who it is.
    /// The old header interleaved them — a Back button wedged above the name, actions
    /// stacked in the margin — so no row of it was a row of anything.
    private func inspectorHeader(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            navRow
            identityRow(person)
            // Only worth a row of its own once there is a second picture: with just the
            // portrait the header above is already showing it.
            if person.photoRefs.count > 1 {
                PersonPhotoStrip(person: person, tree: tree, store: store) { onOpenPhoto?(person, $0) }
            }
        }
        .padding(.top, 13)
        .padding(.bottom, 16)
        // The card turns its axis here — centred identity above, left-aligned record
        // below — and a rule is what says so. It rides the header's bottom edge rather
        // than sitting in the stack, so a photo strip can come and go above it without
        // any spacing being recomputed.
        .overlay(alignment: .bottom) { Rectangle().fill(SepiaTheme.cardRule).frame(height: 1) }
    }

    /// Where you are, and the way back out of a relative-link walk. Edit and close left
    /// this row for `pinnedActions`, which holds the same corner at every scroll
    /// position; all that is still here of them is the gap they need.
    private var navRow: some View {
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
                        Image(systemName: "chevron.left").font(SepiaTheme.icon(size: 10, weight: .semibold))
                        Text(L10n.tr("Назад")).font(SepiaType.label)
                    }
                }
                .sepiaGlassButton(.capsule)
                .buttonBorderShape(.capsule)
                .foregroundStyle(SepiaTheme.accent2)
                .controlSize(.small)
                .help(L10n.tr("Вернуться к предыдущей карточке"))
                .accessibilityLabel(L10n.tr("К предыдущей карточке"))
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Spacer(minLength: 8)
        }
        // Empty unless a relative link has been walked: a card that is already showing
        // the person's name and face does not also need a caption saying "Человек".
        // The row stays because the two circles float above it — the height is the
        // space they need, and without it the whole header rides up under them.
        .frame(minHeight: 24)
        // Two 24pt circles and the spacing between them float above this row, plus a gap
        // before them, so a long Back capsule stops short of running underneath.
        .padding(.trailing, 64)
        .sepiaMotion(SepiaMotion.state, value: history.isEmpty)
    }

    /// Everything that acts on the card rather than on the record inside it: edit this
    /// person, close the card. It rides over the scroller instead of in it, so the pair
    /// is reachable however deep the record is read. At rest it lands on the same corner
    /// the nav row used to hand it, so the card looks untouched until it is scrolled.
    private func pinnedActions(_ person: Person) -> some View {
        let name = person.displayNameLines(language: .current)
        return SepiaGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                // The name the header was carrying, taken up only once the header has
                // taken it away. A bar repeating a name that is still on screen is the
                // thing this card was built not to do. It keeps the split the header
                // made — surname over the rest — so the two are the same name in two
                // sizes rather than two different treatments of it — the header's
                // 20-over-15 pair, two steps down. Both lines are clipped at one line
                // each, because a bar that grows while you scroll is worse than a
                // truncated patronymic.
                VStack(alignment: .leading, spacing: 0) {
                    Text(name.primary)
                        .font(SepiaType.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundStyle(SepiaTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !name.secondary.isEmpty {
                        Text(name.secondary)
                            .font(SepiaType.body)
                            .foregroundStyle(SepiaTheme.inkSoft)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .opacity(showBarName ? 1 : 0)
                // A label, never a target: at rest it is invisible but still laid
                // out, and it must not swallow clicks meant for the record below.
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                Spacer(minLength: 8)

                // A pair of matching circles. Only the accent separates them: one acts on
                // the record, one dismisses the card. The word is carried by the tooltip
                // and the accessibility label, where a pencil has never needed it.
                if let onEdit {
                    Button { onEdit(person) } label: {
                        Image(systemName: "pencil")
                            .font(SepiaTheme.icon(size: 10.5, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .sepiaGlassProminentButton(.circle)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .tint(SepiaTheme.accent)
                    .help(L10n.tr("Редактировать"))
                    .accessibilityLabel(L10n.tr("Редактировать"))
                }

                Button { self.person = nil } label: {
                    Image(systemName: "xmark")
                        .font(SepiaTheme.icon(size: 10.5, weight: .semibold))
                        .foregroundStyle(SepiaTheme.ink)
                        .frame(width: 24, height: 24)
                }
                .sepiaGlassButton(.circle)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help(L10n.tr("Закрыть карточку"))
                .accessibilityLabel(L10n.tr("Закрыть карточку"))
            }
        }
        .padding(.top, 13)
        .padding(.horizontal, 16)
        .background(alignment: .top) { pinnedBackdrop }
        .sepiaMotion(SepiaMotion.crossfade, value: showBarName)
        .sepiaMotion(SepiaMotion.state, value: barCovered)
    }

    /// Paper rather than glass, and only once the record has actually climbed to the
    /// controls: the rows have to dissolve under the circles instead of colliding with
    /// them, and the fill the card is cut from is the only thing they can dissolve into.
    ///
    /// Solid for the whole height of the row and a good way past it, and only then a
    /// fade. A gradient that starts giving way at the top is already half transparent
    /// where the name sits, which is what let a section label read through the name —
    /// and the clearance is measured from the name, not the circles, since the name is
    /// now the taller of the two: at 0.74 of 84 the fade starts 15pt below the row.
    private var pinnedBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: SepiaTheme.panelBg, location: 0),
                .init(color: SepiaTheme.panelBg, location: 0.74),
                .init(color: SepiaTheme.panelBg.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 84)
        .opacity(barCovered ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// Who this is, on the card's own centre line. The name used to share a row with the
    /// portrait, which left it a column of `panel width − 125pt` — 120pt at the narrow
    /// end, where a surname set in 20pt serif simply does not fit, so it broke wherever
    /// the layout engine chose or ran off the edge. Stacked under a medallion it gets
    /// the full width instead, and the one break it still needs is the deliberate one
    /// `displayNameLines` makes between the surname and the rest.
    private func identityRow(_ person: Person) -> some View {
        let name = person.displayNameLines(language: .current)
        return VStack(spacing: 8) {
            // The portrait carries its own extra gap rather than the stack widening
            // its spacing: the rest of the block — maiden name, lifespan — is one
            // paragraph of text and reads as one only while its lines stay close.
            portrait(person)
                .padding(.bottom, 4)

            VStack(spacing: 2) {
                Text(name.primary)
                    .font(SepiaType.title)
                    .fontWeight(.semibold)
                    .foregroundColor(SepiaTheme.ink)
                if !name.secondary.isEmpty {
                    Text(name.secondary)
                        .font(SepiaTheme.body(size: 15))
                        .foregroundColor(SepiaTheme.inkSoft)
                }
            }
            // One utterance to VoiceOver: two lines are a typographic choice, not two
            // separate things to hear.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let maiden = person.maidenName, !maiden.isEmpty, maiden != person.surname {
                Text(L10n.tr("урожд. \(maiden)"))
                    .font(SepiaTheme.body(size: 12.5))
                    .italic()
                    .foregroundColor(SepiaTheme.inkSoft)
            }
            if !person.lifespan.isEmpty {
                Text(person.lifespan)
                    .font(SepiaType.body)
                    .foregroundColor(SepiaTheme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        // The one measurement the pinned row needs: how far this row's foot still is
        // from the top of the card. Reading the row itself rather than a scroll offset
        // keeps it right whatever the header is carrying — a portrait, a photo strip,
        // a maiden name, none of them.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(Self.scrollSpace)).maxY
        } action: { identityBottom = $0 }
    }

    /// A medallion rather than a plate: off the text's line entirely, so nothing it does
    /// can narrow the name. Everywhere else in the app a portrait stays the 3:4 plate —
    /// only the card's own header is round. A real photo is a button onto the full-size
    /// copy; the placeholder stands for nothing to open.
    @ViewBuilder
    private func portrait(_ person: Person) -> some View {
        if person.photoData != nil {
            Button { onOpenPhoto?(person, 0) } label: { portraitMedallion(person) }
                .buttonStyle(.plain)
                .onHover { $0 ? NSCursor.pointingHand.set() : NSCursor.arrow.set() }
                .help(L10n.tr("Открыть фото"))
                .accessibilityLabel(L10n.tr("Открыть фото"))
        } else {
            portraitMedallion(person).accessibilityHidden(true)
        }
    }

    /// The medallion's diameter, and how far down the photograph its window sits.
    ///
    /// `.scaledToFill()` alone centres that window, and a face lives in the upper third
    /// of a portrait, so a centred circle framed the chin and the chest — true even of
    /// the honest 3:4 crop `PhotoCropView` produces. The window is anchored to the top
    /// of the frame instead and then nudged back down by `portraitTopBias` so the hair
    /// never touches the rim. That bias is the one number to turn if crops come out
    /// high or low; it is a fraction of the diameter rather than of the photograph,
    /// which is exact for the 3:4 the crop tool stores and close enough for the other
    /// shapes that reach a record by restore or by merge.
    private static let portraitSide: CGFloat = 104
    private static let portraitTopBias: CGFloat = 0.09

    private func portraitMedallion(_ person: Person) -> some View {
        let side = SepiaTheme.scaled(Self.portraitSide)
        let monogram = person.monogram(language: .current)
        return Group {
            if let data = person.photoData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .offset(y: -side * Self.portraitTopBias)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [SepiaTheme.photoA, SepiaTheme.photoB],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    // Initials read at this size; the silhouette does not — at 64pt it
                    // is a blot. It stays for the records that have no name to set.
                    if monogram.isEmpty {
                        Image(systemName: "person.fill")
                            .font(SepiaTheme.icon(size: 34))
                            .foregroundColor(SepiaTheme.inkSoft.opacity(0.42))
                    } else {
                        Text(monogram)
                            .font(SepiaTheme.display(size: 34))
                            .tracking(1)
                            .foregroundColor(SepiaTheme.inkSoft.opacity(0.75))
                    }
                }
            }
        }
        .frame(width: side, height: side, alignment: .top)
        .clipShape(Circle())
        // Two hairlines, not one: the white is the glass edge catching light, the ink
        // inside it is the bezel a medallion has. Together they own the rim, so the
        // seam where the crop ends is never the strongest line in the circle.
        .overlay { Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1) }
        .overlay { Circle().strokeBorder(SepiaTheme.ink.opacity(0.10), lineWidth: 1).padding(1) }
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
                            .font(SepiaTheme.icon(size: 11, weight: .semibold))
                        Text(L10n.tr("Удалить человека"))
                            .font(SepiaType.control)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(SepiaTheme.danger)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                }
                .sepiaGlassButton(.capsule)
                .buttonBorderShape(.capsule)
                .help(L10n.tr("Удалить человека"))
                .accessibilityLabel(L10n.tr("Удалить человека"))
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
        fieldSection(L10n.tr("Основные сведения"), [
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
                // The thumbnail passes hit testing through so the card keeps scrolling;
                // the button around it restores a click target of its own.
                Button { onOpenMap?(p) } label: {
                    PersonMiniMap(person: p).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { $0 ? NSCursor.pointingHand.set() : NSCursor.arrow.set() }
                .help(L10n.tr("Открыть на карте"))
                .accessibilityLabel(L10n.tr("Открыть на карте"))
                .padding(.bottom, 12)
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
                    Button { onOpenPhoto?(p, 0) } label: {
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

    /// Evidence for this person, read-only. Shows `Person.citations` — an imported
    /// file can also hang citations on a birth, a name, a union or an attachment, and
    /// those are kept and exported but not listed here or in the editor.
    @ViewBuilder
    private func sourcesSection(_ p: Person) -> some View {
        if !p.citations.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L10n.tr("Источники"))
                ForEach(p.citations) { citation in
                    let source = tree.sourceRecords.first { $0.id == citation.sourceID }
                    let openable = WebLink(url: source?.url ?? "").openableURL
                    Button {
                        if let openable { NSWorkspace.shared.open(openable) }
                    } label: {
                        sourceRow(citation: citation, source: source)
                    }
                    .buttonStyle(.plain)
                    .disabled(openable == nil)
                    .help(L10n.tr("Открыть источник в браузере"))
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func sourceRow(citation: Citation, source: SourceRecord?) -> some View {
        // Шифр and лист read as one reference: "Ф. 350 · Оп. 2 · Д. 1841 · Л. 214 об."
        let reference = [source?.shelfmarkSummary ?? "", citation.page.map { L10n.tr("Л. \($0)") } ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text")
                .font(SepiaTheme.icon(size: 13))
                .foregroundColor(SepiaTheme.inkSoft)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 5).fill(SepiaTheme.photoA.opacity(0.3)))
            VStack(alignment: .leading, spacing: 2) {
                Text(source?.title ?? L10n.tr("Источник не найден"))
                    .font(SepiaType.body)
                    .foregroundColor(SepiaTheme.ink)
                    .lineLimit(1).truncationMode(.middle)
                if !reference.isEmpty {
                    Text(reference)
                        .font(SepiaTheme.ui(size: 9.5)).tracking(SepiaType.tracking(9.5))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let transcription = citation.transcription, !transcription.isEmpty {
                    Text(transcription)
                        .font(SepiaTheme.body(size: 11.5))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// Identifiers other programs stamped on this person and Swarm preserved. Read-only:
    /// they live in the file's own branches, and Swarm has no say in what they mean.
    @ViewBuilder
    private func externalIDsSection(_ p: Person) -> some View {
        let ids = GenealogySite.externalIDs(in: p.unknownBranches)
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L10n.tr("Внешние идентификаторы"))
                ForEach(ids) { entry in
                    if let url = entry.url {
                        Button { NSWorkspace.shared.open(url) } label: {
                            FieldRow(label: entry.label, value: entry.value)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tr("Открыть ссылку в браузере"))
                    } else {
                        FieldRow(label: entry.label, value: entry.value)
                    }
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
                                .font(SepiaTheme.icon(size: 13))
                                .foregroundColor(SepiaTheme.inkSoft)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 5).fill(SepiaTheme.photoA.opacity(0.3)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.displayTitle)
                                    .font(SepiaType.body)
                                    .foregroundColor(SepiaTheme.ink)
                                    .lineLimit(1).truncationMode(.middle)
                                Text(link.displaySubtitle)
                                    .font(SepiaTheme.ui(size: 9.5)).tracking(SepiaType.tracking(9.5))
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
                    .font(SepiaType.body)
                    .foregroundColor(SepiaTheme.ink)
                    .lineLimit(1).truncationMode(.middle)
                Text(format.isEmpty ? L10n.tr("Файл") : format)
                    .font(SepiaTheme.ui(size: 9.5)).tracking(SepiaType.tracking(9.5)).foregroundColor(SepiaTheme.inkSoft)
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
                SectionHeader(title: L10n.tr("Родственные связи"))
                if let f = parents.father { relRow(L10n.tr("Отец"), f) }
                if let m = parents.mother { relRow(L10n.tr("Мать"), m) }
                ForEach(spouses, id: \.id) { s in relRow(L10n.tr("Супруг"), s) }
                ForEach(children, id: \.id) { c in relRow(L10n.tr("Ребёнок"), c) }
                ForEach(siblings, id: \.id) { s in
                    relRow(s.sex == .male ? L10n.tr("Брат") : s.sex == .female ? L10n.tr("Сестра") : L10n.tr("Брат или сестра"), s)
                }
            }
        }
    }

    /// Label above value, matching `FieldRow` — a fixed label column here made these
    /// rows the only ones in the panel whose text started further right.
    private func relRow(_ tag: String, _ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tag.uppercased())
                .font(SepiaType.label).tracking(SepiaType.tracking(11)).foregroundColor(SepiaTheme.inkSoft)
            Button {
                if let current = self.person { history.append(current) }
                internalNav = true
                self.person = p
            } label: {
                HStack(spacing: 8) {
                    Text(p.displayName(language: .current))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(SepiaTheme.icon(size: 10, weight: .semibold))
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

/// A photo at the size the file actually holds. The card can only ever show a thumbnail
/// of it, and the pictures are usually the one thing on a record worth looking at closely
/// — a face, a uniform, a date written on the back.
///
/// Walks the whole of `Person.photoRefs`: the portrait, then the image attachments. An
/// overlay over the workspace rather than a sheet: a sheet is a separate window, and the
/// dimmed canvas around it belongs to the window underneath, which modality has already
/// stopped answering the mouse. Owning the dimmer is what lets a click on it close.
struct PortraitPreview: View {
    let person: Person
    let tree: FamilyTree
    var store: TreeStore
    @Binding var index: Int
    let onClose: () -> Void

    /// The photo currently on screen, tagged with the index it was loaded for: until
    /// those agree the next file is still being read, which is not the same thing as a
    /// file that isn't there.
    @State private var loaded: (index: Int, image: NSImage?)?

    private var photos: [PersonPhotoRef] { person.photoRefs }

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
            // click even when the window is barely bigger than the card. The arrows ride
            // beside the card rather than over the photo: a face or a line of a document
            // is exactly what sits under a centred overlay button.
            HStack(spacing: 12) {
                if photos.count > 1 { step(-1, icon: "chevron.left", title: L10n.tr("Предыдущее фото")) }
                card
                if photos.count > 1 { step(1, icon: "chevron.right", title: L10n.tr("Следующее фото")) }
            }
            .padding(20)
        }
        // The count is part of the key: deleting a picture from the record under an open
        // viewer has to reload it, not leave a file that is no longer attached on screen.
        .task(id: [index, photos.count]) {
            if index >= photos.count { index = max(0, photos.count - 1) }
            let image = await load()
            loaded = (index, image)
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            photo

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName(language: .current))
                        .font(SepiaType.body)
                        .foregroundColor(SepiaTheme.inkSoft)
                        .lineLimit(1).truncationMode(.tail)
                    if photos.count > 1 {
                        Text(L10n.tr("Фото \(index + 1) из \(photos.count)"))
                            .font(SepiaTheme.ui(size: 9.5)).tracking(SepiaType.tracking(9.5))
                            .foregroundColor(SepiaTheme.inkSoft)
                    }
                }
                Spacer(minLength: 8)
                Button(L10n.tr("Закрыть")) { onClose() }
                    .sepiaGlassButton(.capsule)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        // A ceiling, not a fixed size: in a small window the card shrinks with it instead
        // of running off the ends. Height is left to the picture — the photo above carries
        // the only height limit, so the card ends up the shape of what it is holding
        // rather than a fixed rectangle with bands of paper above and below it.
        .frame(maxWidth: cardWidthCeiling)
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

    @ViewBuilder
    private var photo: some View {
        if let loaded, loaded.index == index {
            if let image = loaded.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    // No height ceiling of its own: `maxHeight` would claim the whole
                    // window and centre the picture in it, which is the band of bare paper
                    // above and below a landscape scan. Fitting the aspect already bounds
                    // both sides.
                    //
                    // On the picture rather than on `photo` as a whole: applied to the
                    // builder it also squeezed the not-found message below into a portrait
                    // column, where one line of it truncated to an ellipsis.
                    .aspectRatio(photoAspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: SepiaTheme.ink.opacity(0.24), radius: 14, y: 6)
            } else {
                Text(L10n.tr("Портрет не найден"))
                    .font(SepiaTheme.body(size: 14))
                    .foregroundColor(SepiaTheme.inkSoft)
            }
        } else {
            // Reading the next file, which is not the same as not finding it. It keeps the
            // aspect so the card holds the last photo's shape while stepping instead of
            // collapsing between two of them.
            Color.clear
                .aspectRatio(photoAspect, contentMode: .fit)
        }
    }

    /// The shape of the picture on screen. Until a file has loaded this is the portrait
    /// column every other photo in the app is drawn in — and while stepping it stays on
    /// the last photo's shape rather than snapping back to that default between two
    /// landscape scans.
    private var photoAspect: CGFloat {
        guard let image = loaded?.image, image.size.height > 0 else { return SepiaTheme.portraitAspect }
        return image.size.width / image.size.height
    }

    /// How wide the card may grow for what it is holding: the height ceiling times the
    /// photo's own aspect. One width for every shape left a wide document small inside a
    /// portrait-shaped card, with the paper around it taking the space the scan needed.
    private var cardWidthCeiling: CGFloat {
        min(1240, max(440, 760 * photoAspect))
    }

    /// One arrow, beside the card on the dimmer.
    private func step(_ delta: Int, icon: String, title: String) -> some View {
        Button {
            // ponytail: wraps instead of disabling at the ends — no end state to style.
            index = (index + delta + photos.count) % photos.count
        } label: {
            Image(systemName: icon)
                .font(SepiaTheme.icon(size: 13, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .sepiaGlassButton(.circle)
        .buttonBorderShape(.circle)
        .keyboardShortcut(delta < 0 ? .leftArrow : .rightArrow, modifiers: [])
        .help(title)
        .accessibilityLabel(title)
    }

    /// The bytes come off disk on a background thread: at full size that is the one part
    /// of opening a photo worth keeping off the main actor. Only the visible file is read.
    private func load() async -> NSImage? {
        guard photos.indices.contains(index) else { return nil }
        switch photos[index] {
        case .portrait:
            // `photoDataUncached` already prefers bytes chosen this session over the file.
            guard let data = person.photoDataUncached() else { return nil }
            return await Task.detached(priority: .userInitiated) { NSImage(data: data) }.value
        case let .attachment(attachment):
            let url = store.attachmentURL(attachment, in: tree)
            return await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
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
