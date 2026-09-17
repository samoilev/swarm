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
        ZStack {
            ZStack {
                Rectangle().fill(.regularMaterial)
                SepiaTheme.paper.opacity(0.9)
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                exportHeader

                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        Button { exportPDF(selected: false) } label: {
                            exportButtonLabel(L10n.tr("PDF — всё дерево"), systemImage: "tree", detail: L10n.tr("Схема дерева и карточки людей с фотографиями и вложениями"))
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(SepiaTheme.accent)
                        .controlSize(.large)
                        .disabled(tree.people.isEmpty)

                        Button { exportPDF(selected: true) } label: {
                            exportButtonLabel(L10n.tr("PDF — выделенная часть"), systemImage: "scope")
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .disabled(selectedIds.isEmpty)

                        Button { exportVerifiedTree() } label: {
                            exportButtonLabel(L10n.tr("GEDCOM с файлами"), systemImage: "archivebox", detail: L10n.tr("Файл дерева, фотографии и вложения в отдельной папке"))
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                    }
                }

            }
            .padding(14)
        }
        .frame(width: 420, height: 390)
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
            subtitle: "\(tree.name.isEmpty ? L10n.tr("Дерево") : tree.name) · \(L10n.count(tree.people.count, .person))",
            onClose: { dismiss() }
        )
    }

    private func exportButtonLabel(_ title: String, systemImage: String, detail: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(SepiaTheme.icon(size: 13, weight: .semibold))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(SepiaType.micro)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(SepiaTheme.ui(size: 12.5))
            .fontWeight(.semibold)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .frame(minHeight: detail == nil ? 36 : 60)
    }

    private var fileSlug: String {
        tree.name.replacingOccurrences(of: " ", with: "-").lowercased()
    }

    private func exportPDF(selected: Bool) {
        let ids: Set<UUID>? = selected ? selectedIds : nil
        guard let data = PersonCardsPDFExporter.render(tree: tree, selectedIds: ids, showPhotos: showPhotos, attachmentsFolder: store.attachmentsFolderURL(for: tree)) else {
            exportError = L10n.tr("Не удалось создать PDF: в дереве нет людей.")
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
