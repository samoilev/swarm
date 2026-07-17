import AppKit
import FamilyTreeCore
import SwiftUI
import UniformTypeIdentifiers

struct TreeLibraryView: View {
    let trees: [FamilyTree]
    let onSelect: (FamilyTree) -> Void
    let onCreate: () -> Void
    var onImport: (() -> Void)?
    var onRevealInFinder: ((FamilyTree) -> Void)?

    @Environment(TreeStore.self) private var store

    // Delete flow
    @State private var treeToDelete: FamilyTree?
    @State private var treeToExport: FamilyTree?
    @State private var showExporter = false
    // Rename flow
    @State private var treeToRename: FamilyTree?
    @State private var renameName = ""
    @State private var renameSubtitle = ""
    /// Errors
    @State private var errorMessage: String?
    /// Set from `store.lastLoadError` when trees on disk failed to parse at launch.
    @State private var showLoadError = false
    @State private var showRecovery = false

    var body: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Родословная")
                        .font(SepiaTheme.display(size: 32))
                        .foregroundColor(SepiaTheme.ink)
                    Text("СЕМЕЙНЫЙ АРХИВ")
                        .font(SepiaTheme.ui(size: 10))
                        .tracking(3)
                        .foregroundColor(SepiaTheme.inkSoft)
                }
                .padding(.top, 48)
                .padding(.bottom, 32)

                // Action toolbar — always visible above the grid
                HStack(spacing: 10) {
                    Spacer()
                    Button(action: { showRecovery = true }) {
                        Label("Восстановление", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(SepiaButtonStyle())
                    Button(action: { onImport?() }) {
                        Label("Импорт GEDCOM", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(SepiaButtonStyle())
                    Button(action: onCreate) {
                        Label("Новое дерево", systemImage: "plus")
                    }
                    .buttonStyle(SepiaButtonStyle(isActive: true))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

                Divider().overlay(SepiaTheme.line)

                migrationBanner

                if trees.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tree")
                            .font(.system(size: 48))
                            .foregroundColor(SepiaTheme.inkSoft)
                        Text("Деревьев пока нет")
                            .font(SepiaTheme.body(size: 18))
                            .foregroundColor(SepiaTheme.ink)
                        Text("Создайте первое родословное дерево")
                            .font(SepiaTheme.body(size: 14))
                            .foregroundColor(SepiaTheme.inkSoft)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 20)
                        ], spacing: 20) {
                            ForEach(trees, id: \.id) { tree in
                                TreeCardView(
                                    tree: tree,
                                    onSelect: { onSelect(tree) },
                                    onReveal: { onRevealInFinder?(tree) },
                                    onRename: { startRename(tree) },
                                    onDelete: { treeToDelete = tree }
                                )
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .confirmationDialog(
            "Удалить дерево «\(treeToDelete?.name ?? "")»?",
            isPresented: Binding(get: { treeToDelete != nil }, set: { if !$0 { treeToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить вместе с файлами", role: .destructive) {
                if let tree = treeToDelete { store.deleteTree(tree) }
                treeToDelete = nil
            }
            Button("Архивировать (оставить файлы)") {
                if let tree = treeToDelete {
                    let url = store.archiveTree(tree)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                treeToDelete = nil
            }
            Button("Экспортировать копию и удалить…") {
                treeToExport = treeToDelete
                treeToDelete = nil
                // Defer so the dialog finishes dismissing before the open panel appears.
                DispatchQueue.main.async { showExporter = true }
            }
            Button("Отмена", role: .cancel) { treeToDelete = nil }
        } message: {
            Text("Выберите, что сделать с файлом GEDCOM и фотографиями этого дерева.")
        }
        .alert("Переименовать дерево", isPresented: Binding(get: { treeToRename != nil }, set: { if !$0 { treeToRename = nil } })) {
            TextField("Название", text: $renameName)
            TextField("Подзаголовок (необязательно)", text: $renameSubtitle)
            Button("Сохранить") {
                guard let tree = treeToRename else { return }
                Task { @MainActor in
                    do {
                        _ = try await store.renameTreeVerified(tree, name: renameName, subtitle: renameSubtitle)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    treeToRename = nil
                }
            }
            Button("Отмена", role: .cancel) { treeToRename = nil }
        } message: {
            Text("Измените название и подзаголовок дерева.")
        }
        .fileImporter(isPresented: $showExporter, allowedContentTypes: [.folder]) { result in
            guard let tree = treeToExport else { return }
            treeToExport = nil
            switch result {
            case .success(let directory):
                Task { @MainActor in
                    let scoped = directory.startAccessingSecurityScopedResource()
                    defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
                    do {
                        let receipt = try await store.exportTree(tree, to: directory)
                        guard store.deleteTree(tree) else {
                            throw TreeStoreError.commitFailed(reason: store.lastSaveError ?? "Экспорт проверен, но исходное дерево не перемещено в Корзину.")
                        }
                        NSWorkspace.shared.activateFileViewerSelecting([receipt.finalURL])
                    } catch {
                        errorMessage = "Не удалось экспортировать дерево.\n\n\(error.localizedDescription)"
                    }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Некоторые деревья не открылись", isPresented: $showLoadError) {
            Button("Показать в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([store.storageFolderURL])
                store.lastLoadError = nil
            }
            Button("Закрыть", role: .cancel) { store.lastLoadError = nil }
        } message: {
            Text(store.lastLoadError ?? "")
        }
        .onAppear { if store.lastLoadError != nil { showLoadError = true } }
        .onChange(of: store.lastLoadError) { _, newValue in showLoadError = (newValue != nil) }
        .sheet(isPresented: $showRecovery) { RecoveryView(store: store) }
    }

    /// Old-format archives open and read fine — only saving is gated — so this is a calm
    /// inline notice naming the affected trees, not a launch alert.
    @ViewBuilder private var migrationBanner: some View {
        if !store.pendingMigrations.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 15))
                    .foregroundColor(SepiaTheme.accent2)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(migrationHeadline)
                        .font(SepiaTheme.body(size: 13.5))
                        .foregroundColor(SepiaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Открывать и просматривать можно уже сейчас. Обновление нужно, чтобы сохранять изменения — оно делает резервную копию и не удаляет исходные файлы.")
                        .font(SepiaTheme.ui(size: 11))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Обновить формат…") { showRecovery = true }
                    .buttonStyle(SepiaButtonStyle(isActive: true))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(SepiaTheme.cardBg)
            .overlay(alignment: .bottom) { Rectangle().fill(SepiaTheme.line).frame(height: 1) }
        }
    }

    private var migrationHeadline: String {
        let names = Set(store.pendingMigrations.map(\.title)).sorted().map { "«\($0)»" }
        let subject = switch names.count {
        case 0: ""
        case 1, 2: names.joined(separator: ", ")
        default: "\(names.prefix(2).joined(separator: ", ")) и ещё \(names.count - 2)"
        }
        return "\(subject) — в старом формате хранения"
    }

    private func startRename(_ tree: FamilyTree) {
        renameName = tree.name
        renameSubtitle = tree.subtitle ?? ""
        treeToRename = tree
    }
}

struct TreeCardView: View {
    let tree: FamilyTree
    let onSelect: () -> Void
    var onReveal: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    @ViewBuilder private var menuItems: some View {
        Button { onRename?() } label: { Label("Переименовать…", systemImage: "pencil") }
        Button { onReveal?() } label: { Label("Показать в Finder", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { onDelete?() } label: { Label("Удалить…", systemImage: "trash") }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Image(systemName: "tree")
                        .font(.system(size: 28))
                        .foregroundColor(SepiaTheme.accent2)
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tree.name)
                        .font(SepiaTheme.display(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(SepiaTheme.ink)
                        .lineLimit(1)
                    if let subtitle = tree.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(SepiaTheme.body(size: 12))
                            .foregroundColor(SepiaTheme.inkSoft)
                            .lineLimit(1)
                    }
                    HStack {
                        Text("\(tree.people.count) чел.")
                            .font(SepiaTheme.ui(size: 11))
                            .foregroundColor(SepiaTheme.inkSoft)
                        Spacer()
                        Menu {
                            menuItems
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 13))
                                .foregroundColor(SepiaTheme.inkSoft)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Действия с деревом")
                        .accessibilityLabel("Действия с деревом")
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 160)
            .background(SepiaTheme.cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(SepiaTheme.cardLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contextMenu { menuItems }
    }
}
