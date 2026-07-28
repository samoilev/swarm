import SwarmCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(TreeStore.self) private var store
    @State private var selectedTree: FamilyTree?
    @State private var showOnboarding = false
    @State private var showGEDCOMImporter = false
    @State private var importError: String?
    @State private var pendingImportURL: URL?
    @State private var importPreview: ImportResult?
    /// Confirmation the workspace shows once, on arrival, for a tree that was just
    /// written. Creating a whole family record used to be the app's only silent write.
    @State private var pendingToast: String?

    private var gedcomType: UTType {
        UTType(filenameExtension: "ged") ?? .plainText
    }

    var body: some View {
        Group {
            if let tree = selectedTree {
                MainWorkspace(
                    tree: tree,
                    store: store,
                    initialToast: pendingToast,
                    onBack: {
                        selectedTree = nil
                        pendingToast = nil
                    }
                )
            } else {
                TreeLibraryView(
                    trees: store.trees,
                    onSelect: { selectedTree = $0 },
                    onCreate: { showOnboarding = true },
                    onImport: { showGEDCOMImporter = true },
                    onRevealInFinder: { tree in
                        let url = store.gedFileURL(for: tree)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                )
            }
        }
        // The sheet reports its own failures inline and dismisses itself on success, so
        // a write that fails no longer surfaces as an *import* error over a live form.
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { newTree in
                _ = try await store.addTreeVerified(newTree)
                pendingToast = L10n.tr("Дерево «\(newTree.name)» создано")
                selectedTree = newTree
            }
        }
        // No auto-presented sheet on an empty library. The empty state itself offers
        // both ways in (create and import), which a modal that appears before the user
        // has seen the app cannot do.
        .onReceive(NotificationCenter.default.publisher(for: .newTreeRequested)) { _ in
            showOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTreeRequested)) { note in
            guard let id = note.object as? UUID,
                  let tree = store.trees.first(where: { $0.id == id }) else { return }
            selectedTree = tree
        }
        .fileImporter(isPresented: $showGEDCOMImporter, allowedContentTypes: [gedcomType]) { result in
            switch result {
            case .success(let url): previewGEDCOM(from: url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .sheet(isPresented: Binding(
            get: { importPreview != nil },
            set: { if !$0 { cancelImportPreview() } }
        )) {
            if let importPreview {
                ImportPreviewView(result: importPreview, onCancel: cancelImportPreview, onImport: commitImportPreview)
            }
        }
        .onOpenURL { url in previewGEDCOM(from: url) }
        .alert(L10n.tr("Не удалось импортировать файл"), isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func previewGEDCOM(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let localCopy = try store.prepareImportPreview(from: url)
            let result = try GEDCOMCodec.parse(localCopy)
            pendingImportURL = localCopy
            importPreview = result
        } catch {
            importError = L10n.tr("Файл повреждён или имеет неподдерживаемый формат.\n\n\(error.localizedDescription)")
        }
    }

    private func commitImportPreview() {
        guard let url = pendingImportURL else { return }
        Task { @MainActor in
            do {
                let result = try await store.importGEDCOM(from: url)
                store.discardImportPreview(at: url)
                pendingImportURL = nil
                importPreview = nil
                selectedTree = result.tree
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func cancelImportPreview() {
        if let pendingImportURL { store.discardImportPreview(at: pendingImportURL) }
        pendingImportURL = nil
        importPreview = nil
    }
}
