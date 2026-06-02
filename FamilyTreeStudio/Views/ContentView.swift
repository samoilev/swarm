import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(TreeStore.self) private var store
    @State private var selectedTree: FamilyTree?
    @State private var showOnboarding = false
    @State private var showGEDCOMImporter = false
    @State private var importError: String?

    private var gedcomType: UTType { UTType(filenameExtension: "ged") ?? .plainText }
    
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
                store.addTree(newTree)
                selectedTree = newTree
                showOnboarding = false
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
            case .success(let url): importGEDCOM(from: url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .alert("Не удалось импортировать файл", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func importGEDCOM(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let tree = try store.importGEDCOM(from: url)
            selectedTree = tree
        } catch {
            importError = "Файл повреждён или имеет неподдерживаемый формат.\n\n\(error.localizedDescription)"
        }
    }
}
