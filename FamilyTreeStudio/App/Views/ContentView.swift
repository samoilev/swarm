import FamilyTreeCore
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

    private var gedcomType: UTType {
        UTType(filenameExtension: "ged") ?? .plainText
    }

    var body: some View {
        Group {
            if let tree = selectedTree {
                MainWorkspace(tree: tree, store: store, onBack: { selectedTree = nil })
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
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { newTree in
                Task { @MainActor in
                    do {
                        _ = try await store.addTreeVerified(newTree)
                        selectedTree = newTree
                        showOnboarding = false
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
        }
        .onAppear {
            if store.trees.isEmpty {
                showOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTreeRequested)) { _ in
            showOnboarding = true
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
        .alert("Не удалось импортировать файл", isPresented: Binding(
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
            importError = "Файл повреждён или имеет неподдерживаемый формат.\n\n\(error.localizedDescription)"
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
