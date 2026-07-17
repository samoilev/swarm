import AppKit
import FamilyTreeCore
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
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Экспорт").font(SepiaTheme.display(size: 22)).foregroundColor(SepiaTheme.ink)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundColor(SepiaTheme.inkSoft)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(tree.name.isEmpty ? "Дерево" : tree.name)
                        .font(SepiaTheme.display(size: 17)).fontWeight(.semibold).foregroundColor(SepiaTheme.ink)
                        .lineLimit(1)
                    Text("\(tree.people.count) чел.")
                        .font(SepiaTheme.ui(size: 11)).foregroundColor(SepiaTheme.inkSoft)
                }

                VStack(spacing: 10) {
                    Button { exportPDF(selected: false) } label: {
                        Label("PDF — всё дерево", systemImage: "tree").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SepiaButtonStyle(isActive: true)).controlSize(.large)
                    .disabled(tree.people.isEmpty)

                    Button { exportPDF(selected: true) } label: {
                        Label("PDF — выделенная часть", systemImage: "scope").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SepiaButtonStyle()).controlSize(.large)
                    .disabled(selectedIds.isEmpty)

                    Button { exportVerifiedTree() } label: {
                        Label("Проверенный GEDCOM-архив", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SepiaButtonStyle()).controlSize(.large)
                }

                Text("PDF начинается со схемы дерева (повёрнутой на 90°), затем по странице-карточке на каждого человека по алфавиту, с фото и вложениями. «Выделенная часть» — только выбранные на схеме люди. Архив GEDCOM сохраняет и проверяет файл дерева, портреты и вложения в отдельной папке.")
                    .font(SepiaTheme.body(size: 11.5)).foregroundColor(SepiaTheme.inkSoft).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(width: 360)
            .background(SepiaTheme.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
        }
        .frame(minWidth: 460, minHeight: 340)
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: exportDoc?.type ?? .data,
            defaultFilename: exportName
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("Не удалось сохранить файл", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var fileSlug: String {
        tree.name.replacingOccurrences(of: " ", with: "-").lowercased()
    }

    private func exportPDF(selected: Bool) {
        let ids: Set<UUID>? = selected ? selectedIds : nil
        guard let data = PersonCardsPDFExporter.render(tree: tree, selectedIds: ids, showPhotos: showPhotos, attachmentsFolder: store.attachmentsFolderURL(for: tree)) else { return }
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
        panel.prompt = "Экспортировать"
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
