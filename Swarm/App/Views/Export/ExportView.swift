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
                            detail: L10n.tr("Папка с деревом, фотографиями и вложениями"),
                            systemImage: "archivebox",
                            style: .secondary(SepiaTheme.accent2)
                        )
                    }
                    .sepiaGlassButton(.rounded(SepiaLayout.Radius.card))
                    .buttonBorderShape(.roundedRectangle(radius: SepiaLayout.Radius.card))
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

    private var summaryLine: String {
        var parts = [L10n.count(tree.people.count, .person)]
        let photos = tree.people.reduce(into: 0) { $0 += $1.hasPhoto ? 1 : 0 }
        let attachments = tree.people.reduce(into: 0) { $0 += $1.attachments.count }
        if photos > 0 { parts.append(L10n.count(photos, .photo)) }
        if attachments > 0 { parts.append(L10n.count(attachments, .attachment)) }
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
        guard let data = PersonCardsPDFExporter.render(tree: tree, selectedIds: ids, showPhotos: showPhotos, attachmentsFolder: store.attachmentsFolderURL(for: tree)) else {
            exportError = L10n.tr("Чтобы создать PDF, сначала добавьте людей в дерево.")
            return
        }
        exportDoc = RenderedFileDocument(data: data, type: .pdf)
        exportName = selected ? "\(fileSlug)-selection.pdf" : "\(fileSlug)-tree.pdf"
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
                    let receipt = try await store.exportTree(tree, to: directory)
                    NSWorkspace.shared.activateFileViewerSelecting([receipt.finalURL])
                    dismiss()
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }
}
