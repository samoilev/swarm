import AppKit
import SwarmCore
import SwiftUI

struct ExportView: View {
    let tree: FamilyTree
    var store: TreeStore
    /// Currently highlighted people (lineage or ⌘-path). Empty ⇒ no selection export.
    var selectedIds: Set<UUID> = []
    /// Mirrors the canvas photo toggle so the PDF diagram matches what's on screen.
    var showPhotos: Bool = true
    @Environment(\.dismiss) private var dismiss

    // Native file export (PDF cards via .fileExporter; verified tree bundle via NSOpenPanel).
    @State private var exportDoc: RenderedFileDocument?
    @State private var exportName = ""
    @State private var showExporter = false
    @State private var exportError: String?
    /// Off by default: an export carries everything unless this particular one is
    /// asked to hold the living back.
    @State private var hideLivingPII = false
    /// Which specification the exported .ged is written in. 7.0 is the default because
    /// it is the current standard and what a file handed to another program should be;
    /// the tree's own storage is unaffected either way.
    @State private var exportVersion: GEDCOMVersion = .v70
    /// One file or a folder. GEDZIP is the default because it is the only shape that
    /// survives being emailed: a folder loses its photos the moment it is detached
    /// from the .ged beside them.
    @State private var packaging: TreeExportPackaging = .gedzip

    var body: some View {
        VStack(alignment: .leading, spacing: SepiaTheme.scaled(SepiaLayout.m)) {
            exportHeader

            SepiaGlassGroup(spacing: SepiaTheme.scaled(SepiaLayout.s)) {
                VStack(spacing: SepiaTheme.scaled(SepiaLayout.s)) {
                    Button { exportPDF(selected: false) } label: {
                        exportRowLabel(
                            title: L10n.tr("PDF — всё дерево"),
                            detail: L10n.tr("Схема дерева и карточки людей"),
                            systemImage: "tree",
                            style: .primary
                        )
                    }
                    // `.glass` tinted, not `.glassProminent`: the two render the same
                    // accent fill, but the prominent variant carries slightly different
                    // chrome metrics, which left this row a point or two taller than the
                    // two below it. One style for all three rows, one row pitch.
                    .sepiaGlassButton(.rounded(SepiaLayout.Radius.card))
                    .buttonBorderShape(.roundedRectangle(radius: SepiaLayout.Radius.card))
                    .tint(SepiaTheme.accent)
                    .disabled(tree.people.isEmpty)

                    // Disabled rather than hidden or replaced by a card: the row keeps
                    // the geometry of the two live ones, and `.glass` dims it so lightly
                    // that the sentence explaining how to unlock it stays readable.
                    Button { exportPDF(selected: true) } label: {
                        exportRowLabel(
                            title: L10n.tr("PDF — выделенная часть"),
                            detail: selectedIds.isEmpty
                                ? L10n.tr("Выделите ветвь на схеме, удерживая ⌘.")
                                : L10n.count(selectedIds.count, .person),
                            systemImage: "scope",
                            style: selectedIds.isEmpty ? .unavailable : .secondary(SepiaTheme.accent)
                        )
                    }
                    .sepiaGlassButton(.rounded(SepiaLayout.Radius.card))
                    .buttonBorderShape(.roundedRectangle(radius: SepiaLayout.Radius.card))
                    .disabled(selectedIds.isEmpty)

                    Button { exportVerifiedTree() } label: {
                        exportRowLabel(
                            title: L10n.tr("GEDCOM с файлами"),
                            detail: gedcomRowDetail,
                            systemImage: "archivebox",
                            style: .secondary(SepiaTheme.accent2)
                        )
                    }
                    .sepiaGlassButton(.rounded(SepiaLayout.Radius.card))
                    .buttonBorderShape(.roundedRectangle(radius: SepiaLayout.Radius.card))

                    versionPicker
                    packagingPicker
                    privacyToggle
                }
            }

            contentsSummary
        }
        .padding(SepiaTheme.scaled(SepiaLayout.l))
        // Width scales with the interface setting like every other panel; the height is
        // the content's own, so a longer translation or a larger step grows the sheet
        // instead of clipping inside a frame written for 100% Russian.
        .frame(width: SepiaTheme.scaledPanel(420, axis: .horizontal))
        .fixedSize(horizontal: false, vertical: true)
        .background(LiquidGlassPanelBackground())
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: exportDoc?.type ?? .data,
            defaultFilename: exportName
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert(L10n.tr("Не удалось сохранить файл"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    /// Applies to the GEDCOM export only — a PDF has no specification version.
    ///
    /// Disabled for GEDZIP: that format is defined only by GEDCOM 7.0, so offering 5.5.1
    /// alongside it would let the user ask for a file no other program is obliged to
    /// read. Same move the privacy checkbox makes when there is nobody living to hide.
    private var versionPicker: some View {
        Picker(selection: $exportVersion) {
            ForEach([GEDCOMVersion.v70, .v551], id: \.self) { version in
                Text(verbatim: "GEDCOM \(version.displayName)").tag(version)
            }
        } label: {
            Text(L10n.tr("Версия"))
                .font(SepiaType.control)
                .foregroundStyle(SepiaTheme.ink)
        }
        .pickerStyle(.menu)
        .disabled(packaging == .gedzip)
        .padding(.horizontal, SepiaTheme.scaled(SepiaLayout.s))
        .padding(.vertical, SepiaTheme.scaled(SepiaLayout.xs))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The GEDCOM row describes what the packaging picker below it will actually
    /// produce; saying "folder" under a one-file export is the kind of small lie that
    /// makes people distrust the rest of the sheet.
    private var gedcomRowDetail: String {
        switch packaging {
        case .gedzip: L10n.tr("Один файл с деревом, фотографиями и вложениями")
        case .folder: L10n.tr("Папка с деревом, фотографиями и вложениями")
        }
    }

    /// Whether the tree leaves as one file or as a folder. Applies to the GEDCOM export
    /// only; the PDF rows are unaffected.
    private var packagingPicker: some View {
        Picker(selection: $packaging) {
            Text(L10n.tr("Один файл (.gdz)")).tag(TreeExportPackaging.gedzip)
            Text(L10n.tr("Папка с файлами")).tag(TreeExportPackaging.folder)
        } label: {
            Text(L10n.tr("Упаковка"))
                .font(SepiaType.control)
                .foregroundStyle(SepiaTheme.ink)
        }
        .pickerStyle(.menu)
        .padding(.horizontal, SepiaTheme.scaled(SepiaLayout.s))
        .padding(.vertical, SepiaTheme.scaled(SepiaLayout.xs))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Applies to whichever of the three exports is used next. Deliberately per-export
    /// and unremembered: who a file is going to is what decides this, not a preference.
    /// What it removes is left to the footer's counts rather than spelled out — the
    /// label carries it, and a paragraph here pushed the three rows off their rhythm.
    private var privacyToggle: some View {
        Toggle(isOn: $hideLivingPII) {
            Text(L10n.tr("Скрыть данные живых людей"))
                .font(SepiaType.control)
                .foregroundStyle(SepiaTheme.ink)
        }
        .toggleStyle(.checkbox)
        .disabled(livingCount == 0)
        .padding(.horizontal, SepiaTheme.scaled(SepiaLayout.s))
        // On top of the group's own spacing, so the checkbox reads as its own thing
        // rather than a fourth row crowding the buttons above it.
        .padding(.vertical, SepiaTheme.scaled(SepiaLayout.xs))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exportHeader: some View {
        LiquidGlassPanelHeader(
            title: L10n.tr("Экспорт"),
            // The counts moved to the footer, where they describe what lands on disk;
            // repeating the person count here made the same number appear twice.
            subtitle: tree.name.isEmpty ? L10n.tr("Дерево") : tree.name,
            onClose: { dismiss() }
        )
    }

    /// What the export will actually contain. Metadata only — `hasPhoto` and the
    /// attachment list both answer without touching the disk, so opening the panel
    /// never walks the media folder.
    private var contentsSummary: some View {
        VStack(alignment: .leading, spacing: SepiaTheme.scaled(SepiaLayout.s)) {
            Rectangle()
                .fill(SepiaTheme.cardRule)
                .frame(height: 1)
                .accessibilityHidden(true)

            Text(summaryLine)
                .font(SepiaType.micro)
                .foregroundStyle(SepiaTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var livingCount: Int { tree.livingPeopleCount }

    private var summaryLine: String {
        // Counted against what actually lands on disk, so the footer stops promising
        // photos and files that the privacy toggle has just removed.
        let people = hideLivingPII ? tree.people.filter { !$0.isLiving } : tree.people
        var parts = [L10n.count(people.count, .person)]
        let photos = people.reduce(into: 0) { $0 += $1.hasPhoto ? 1 : 0 }
        let attachments = people.reduce(into: 0) { $0 += $1.attachments.count }
        if photos > 0 { parts.append(L10n.count(photos, .photo)) }
        if attachments > 0 { parts.append(L10n.count(attachments, .attachment)) }
        if hideLivingPII, livingCount > 0 {
            parts.append(L10n.tr("скрыто: \(L10n.count(livingCount, .person))"))
        }
        return parts.joined(separator: " · ")
    }

    /// How one row is coloured. Three states rather than a flag, so the row that cannot
    /// be used right now says so in its own colours rather than relying on the system's
    /// dimming alone, which `.glass` applies very lightly.
    private enum RowStyle {
        /// The recommended export: a filled row, white on accent.
        case primary
        /// An available export, tinted by format.
        case secondary(Color)
        /// Shown but not offered — nothing to export yet, and the row says what to do.
        case unavailable

        var chipTint: Color {
            switch self {
            case .primary: .white
            case .secondary(let colour): colour
            case .unavailable: SepiaTheme.inkSoft
            }
        }

        var chipFill: Color {
            switch self {
            case .primary: Color.white.opacity(0.18)
            case .secondary(let colour): colour.opacity(0.12)
            case .unavailable: SepiaTheme.ink.opacity(0.06)
            }
        }

        var titleColour: Color {
            switch self {
            case .primary: .white
            case .secondary: SepiaTheme.ink
            case .unavailable: SepiaTheme.inkSoft
            }
        }

        /// Both weights clear AA on the surface they sit on: 0.9 white over `accent`,
        /// and `inkSoft` over the glass rows.
        var detailColour: Color {
            switch self {
            case .primary: Color.white.opacity(0.9)
            case .secondary, .unavailable: SepiaTheme.inkSoft
            }
        }
    }

    private func exportRowLabel(
        title: String,
        detail: String,
        systemImage: String,
        style: RowStyle
    ) -> some View {
        HStack(spacing: SepiaTheme.scaled(SepiaLayout.m)) {
            Image(systemName: systemImage)
                .font(SepiaTheme.icon(size: 13, weight: .semibold))
                .foregroundStyle(style.chipTint)
                .frame(width: SepiaTheme.scaled(30), height: SepiaTheme.scaled(30))
                .background(
                    RoundedRectangle(cornerRadius: SepiaLayout.Radius.field, style: .continuous)
                        .fill(style.chipFill)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SepiaTheme.scaled(SepiaLayout.xs)) {
                Text(title)
                    .font(SepiaType.control)
                    .fontWeight(.semibold)
                    .foregroundStyle(style.titleColour)
                Text(detail)
                    .font(SepiaType.micro)
                    .foregroundStyle(style.detailColour)
            }
            // A button label is one line by default, which truncated the description
            // mid-word. Two lines and no truncation: the copy fits one line in both
            // languages, and a longer translation wraps instead of disappearing.
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SepiaTheme.scaled(SepiaLayout.s))
        // A minimum rather than a height: the row grows for a translation that wraps.
        .frame(maxWidth: .infinity, minHeight: SepiaTheme.scaled(56), alignment: .leading)
    }

    private var fileSlug: String {
        tree.name.replacingOccurrences(of: " ", with: "-").lowercased()
    }

    private func exportPDF(selected: Bool) {
        let ids: Set<UUID>? = selected ? selectedIds : nil
        // The renderer knows nothing about privacy — it draws whatever tree it is given,
        // so the redacted names reach the cards, the relatives named on *other* people's
        // cards and the poster alike. The attachments folder is still the real tree's:
        // the redaction removed the references, not the files.
        let source = hideLivingPII ? tree.redactingLivingPeople() : tree
        guard let data = PersonCardsPDFExporter.render(tree: source, selectedIds: ids, showPhotos: showPhotos, attachmentsFolder: store.attachmentsFolderURL(for: tree)) else {
            exportError = L10n.tr("Чтобы создать PDF, сначала добавьте людей в дерево.")
            return
        }
        exportDoc = RenderedFileDocument(data: data, type: .pdf)
        let suffix = hideLivingPII ? "-private" : ""
        exportName = selected ? "\(fileSlug)-selection\(suffix).pdf" : "\(fileSlug)-tree\(suffix).pdf"
        showExporter = true
    }

    private func exportVerifiedTree() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr("Экспортировать")
        panel.begin { r in
            guard r == .OK, let directory = panel.url else { return }
            Task { @MainActor in
                do {
                    let receipt = try await store.exportTree(
                        tree,
                        to: directory,
                        hidingLivingPeople: hideLivingPII,
                        version: exportVersion,
                        packaging: packaging
                    )
                    NSWorkspace.shared.activateFileViewerSelecting([receipt.finalURL])
                    dismiss()
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }
}
