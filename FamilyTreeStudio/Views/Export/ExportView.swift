import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportView: View {
    let tree: FamilyTree
    var store: TreeStore
    @Environment(\.dismiss) private var dismiss

    // Native file export (PDF cards via .fileExporter; GEDCOM via NSSavePanel).
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
                    Button { exportPersonCards() } label: {
                        Label("PDF — карточки людей", systemImage: "person.text.rectangle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SepiaButtonStyle(isActive: true)).controlSize(.large)
                    .disabled(tree.people.isEmpty)

                    Button { exportGEDCOM() } label: {
                        Label("Экспорт GEDCOM (.ged)", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SepiaButtonStyle()).controlSize(.large)
                }

                Text("«Карточки людей» — отдельная страница на каждого человека по алфавиту, с фото и изображениями из вложений. GEDCOM — стандартный файл, который можно открыть в Ancestry, Gramps или MacFamilyTree.")
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

    private func exportPersonCards() {
        guard let data = PersonCardsPDFExporter.render(tree: tree, attachmentsFolder: store.attachmentsFolderURL(for: tree)) else { return }
        exportDoc = RenderedFileDocument(data: data, type: .pdf)
        exportName = "\(fileSlug)-cards.pdf"
        showExporter = true
    }

    // GEDCOM export stays on NSSavePanel: it writes sibling `Media/` and `Attachments/`
    // folders next to the chosen .ged file, which doesn't fit the single-file
    // FileWrapper model used by .fileExporter (the app is effectively non-sandboxed).
    private func exportGEDCOM() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ged") ?? .plainText]
        panel.nameFieldStringValue = "\(fileSlug).ged"
        panel.begin { r in
            if r == .OK, let url = panel.url {
                store.exportGEDCOM(tree: tree, to: url)
            }
        }
    }
}
