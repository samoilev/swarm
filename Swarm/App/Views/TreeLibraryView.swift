import AppKit
import SwarmCore
import SwiftUI
import UniformTypeIdentifiers

/// How the library orders its cards. Recency is the default because the job people come
/// back to this page for is "continue where I left off", not "browse an alphabet".
enum TreeSortOrder: String, CaseIterable, Identifiable {
    case recentlyUpdated
    case nameAscending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentlyUpdated: L10n.tr("Сначала недавние")
        case .nameAscending: L10n.tr("По названию")
        }
    }

    static let storageKey = "treeLibrarySortOrder"
}

/// The identity facts a card shows instead of a decorative glyph: who is in this tree,
/// when they lived, and when the record was last touched. Everything here already exists
/// in the GEDCOM — the old card simply never surfaced it.
struct TreeSummary {
    let peopleCount: Int
    /// The two most common surnames, most frequent first.
    let surnames: [String]
    let firstYear: Int?
    let lastYear: Int?
    /// The person whose portrait anchors the card, when one has a photo.
    let portraitPerson: Person?
    let monogram: String

    // ponytail: recomputed per card body evaluation. It is one pass over `people` for
    // trees of a few thousand, which is microseconds. If trees grow past ~50k people,
    // cache this on TreeStore keyed by tree id + updatedAt instead.
    init(tree: FamilyTree) {
        peopleCount = tree.people.count

        var surnameCounts: [String: Int] = [:]
        var earliest: Int?
        var latestDeath: Int?
        var latestBirth: Int?
        for person in tree.people {
            let surname = person.displaySurname.trimmingCharacters(in: .whitespaces)
            if !surname.isEmpty { surnameCounts[surname, default: 0] += 1 }
            if let year = FamilyDate.parse(person.birthDate).year {
                earliest = min(earliest ?? year, year)
                latestBirth = max(latestBirth ?? year, year)
            }
            if let year = FamilyDate.parse(person.deathDate).year {
                earliest = min(earliest ?? year, year)
                latestDeath = max(latestDeath ?? year, year)
            }
        }
        // Ties break alphabetically so the same tree always shows the same two surnames.
        surnames = surnameCounts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(2)
            .map(\.key)
        firstYear = earliest
        lastYear = latestDeath ?? latestBirth

        let home = tree.homePerson
        portraitPerson = (home?.hasPhoto == true) ? home : tree.people.first(where: \.hasPhoto)

        let source = tree.name.trimmingCharacters(in: .whitespaces)
        monogram = source.isEmpty ? "·" : String(source.prefix(1)).uppercased()
    }

    /// "1876 — 1954", "1876", or nil when the tree carries no dated events at all.
    var lifespan: String? {
        guard let firstYear else { return nil }
        guard let lastYear, lastYear != firstYear else { return "\(firstYear)" }
        return "\(firstYear) — \(lastYear)"
    }

    var peopleLabel: String {
        L10n.count(peopleCount, .person)
    }
}

struct TreeLibraryView: View {
    let trees: [FamilyTree]
    let onSelect: (FamilyTree) -> Void
    let onCreate: () -> Void
    var onImport: (() -> Void)?
    var onRevealInFinder: ((FamilyTree) -> Void)?

    @Environment(TreeStore.self) private var store
    @Environment(\.locale) private var locale

    // Delete flow
    @State private var treeToDelete: FamilyTree?
    @State private var treeToExport: FamilyTree?
    @State private var showExporter = false
    // Rename flow
    @State private var treeToRename: FamilyTree?
    @State private var renameName = ""
    @State private var renameSubtitle = ""
    @State private var renameValidationMessage: String?
    @State private var renameSaving = false
    @FocusState private var renameNameFocused: Bool
    @FocusState private var renameSubtitleFocused: Bool
    /// Errors
    @State private var errorMessage: String?
    /// Set from `store.lastLoadError` when trees on disk failed to parse at launch.
    @State private var showLoadError = false
    @State private var showStorageMigrationWarning = false
    @State private var showRecovery = false
    // Find / sort / keyboard traversal
    @State private var filterText = ""
    @AppStorage(TreeSortOrder.storageKey) private var sortOrderRaw = TreeSortOrder.recentlyUpdated.rawValue
    @FocusState private var filterFocused: Bool
    @FocusState private var focusedTreeID: UUID?
    /// Column count of the current grid, measured so ↑/↓ can step a whole row.
    @State private var columnCount = 1

    /// The filter only appears once scanning by eye stops being realistic.
    private var showsFilter: Bool { trees.count >= 6 }

    private var sortOrder: TreeSortOrder {
        TreeSortOrder(rawValue: sortOrderRaw) ?? .recentlyUpdated
    }

    private var visibleTrees: [FamilyTree] {
        let sorted: [FamilyTree] = switch sortOrder {
        case .recentlyUpdated: trees.sorted { $0.updatedAt > $1.updatedAt }
        case .nameAscending:
            trees.sorted {
                $0.name.compare(
                    $1.name,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: nil,
                    locale: locale
                ) == .orderedAscending
            }
        }
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { tree in
            if tree.name.localizedCaseInsensitiveContains(query) { return true }
            if tree.subtitle?.localizedCaseInsensitiveContains(query) == true { return true }
            return tree.people.contains { $0.displaySurname.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                toolbar
                Divider().overlay(SepiaTheme.line)
                migrationBanner

                if trees.isEmpty {
                    emptyLibrary
                } else if visibleTrees.isEmpty {
                    noMatches
                } else {
                    grid
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onReceive(NotificationCenter.default.publisher(for: .findPersonRequested)) { _ in
            // ⌘F means "find" wherever you are; in the library that is the tree filter.
            guard showsFilter else { return }
            filterFocused = true
        }
        .confirmationDialog(
            L10n.tr("Удалить дерево «\(treeToDelete?.name ?? "")»?"),
            isPresented: Binding(get: { treeToDelete != nil }, set: { if !$0 { treeToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.tr("Удалить вместе с файлами"), role: .destructive) {
                if let tree = treeToDelete { store.deleteTree(tree) }
                treeToDelete = nil
            }
            Button(L10n.tr("Архивировать (оставить файлы)")) {
                if let tree = treeToDelete {
                    let url = store.archiveTree(tree)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                treeToDelete = nil
            }
            Button(L10n.tr("Экспортировать копию и удалить…")) {
                treeToExport = treeToDelete
                treeToDelete = nil
                // Defer so the dialog finishes dismissing before the open panel appears.
                DispatchQueue.main.async { showExporter = true }
            }
            Button(L10n.tr("Отмена"), role: .cancel) { treeToDelete = nil }
        } message: {
            Text(L10n.tr("Выберите, что сделать с файлом GEDCOM и фотографиями этого дерева."))
        }
        .sheet(isPresented: Binding(
            get: { treeToRename != nil },
            set: {
                if !$0 {
                    treeToRename = nil
                    renameValidationMessage = nil
                    renameSaving = false
                }
            }
        )) {
            renameSheet
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
                            throw TreeStoreError.commitFailed(reason: store.lastSaveError ?? L10n.tr("Экспорт проверен, но исходное дерево не перемещено в Корзину."))
                        }
                        NSWorkspace.shared.activateFileViewerSelecting([receipt.finalURL])
                    } catch {
                        errorMessage = L10n.tr("Не удалось экспортировать дерево.\n\n\(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert(L10n.tr("Ошибка"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(L10n.tr("Некоторые деревья не открылись"), isPresented: $showLoadError) {
            Button(L10n.tr("Показать в Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([store.storageFolderURL])
                store.lastLoadError = nil
            }
            Button(L10n.tr("Закрыть"), role: .cancel) { store.lastLoadError = nil }
        } message: {
            Text(store.lastLoadError ?? "")
        }
        .onAppear { if store.lastLoadError != nil { showLoadError = true } }
        .onChange(of: store.lastLoadError) { _, newValue in showLoadError = (newValue != nil) }
        .alert(L10n.tr("Проверка старого хранилища"), isPresented: $showStorageMigrationWarning) {
            Button(L10n.tr("Показать в Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([
                    store.storageMigrationWarningURL ?? store.storageFolderURL,
                ])
                store.storageMigrationWarning = nil
            }
            Button(L10n.tr("Закрыть"), role: .cancel) { store.storageMigrationWarning = nil }
        } message: {
            Text(store.storageMigrationWarning ?? "")
        }
        .onAppear {
            if store.storageMigrationWarning != nil { showStorageMigrationWarning = true }
        }
        .onChange(of: store.storageMigrationWarning) { _, newValue in
            showStorageMigrationWarning = (newValue != nil)
        }
        .sheet(isPresented: $showRecovery) { RecoveryView(store: store) }
    }

    // MARK: - Chrome

    private var header: some View {
        Text(L10n.tr("Swarm"))
            .font(SepiaTheme.display(size: 32))
            .foregroundColor(SepiaTheme.ink)
            .padding(.top, 34)
            .padding(.bottom, 24)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                if showsFilter {
                    filterField()
                }
                Spacer(minLength: 12)
                toolbarActions
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    toolbarActions
                }
                if showsFilter {
                    filterField(width: nil)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var toolbarActions: some View {
        if trees.count > 1 {
            sortMenu
        }

        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                // On an empty library these two live in the empty state itself, 300pt below.
                // Showing them twice on one screen is noise, not reinforcement.
                if !trees.isEmpty {
                    Button(action: { onImport?() }) {
                        Label(L10n.tr("Импорт GEDCOM"), systemImage: "square.and.arrow.down")
                            .lineLimit(1)
                            .frame(height: 16)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                    .fixedSize(horizontal: true, vertical: false)

                    // ⌘N is owned by the File menu command in SwarmApp; binding it here too
                    // would register the shortcut twice.
                    Button(action: onCreate) {
                        Label(L10n.tr("Новое дерево"), systemImage: "plus")
                            .lineLimit(1)
                            .frame(height: 16)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                    .tint(SepiaTheme.accent)
                    .fixedSize(horizontal: true, vertical: false)
                }

                // Recovery is a once-a-year rescue tool. It stays reachable, but it no
                // longer sits at the front door with the same weight as creating a tree.
                Menu {
                    Button(L10n.tr("Восстановить из резервной копии…")) { showRecovery = true }
                    Button(L10n.tr("Показать папку хранилища")) {
                        NSWorkspace.shared.activateFileViewerSelecting([store.storageFolderURL])
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SepiaTheme.ink)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L10n.tr("Обслуживание архива"))
                .accessibilityLabel(L10n.tr("Обслуживание архива"))
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker(L10n.tr("Порядок"), selection: $sortOrderRaw) {
                ForEach(TreeSortOrder.allCases) { order in
                    Text(order.label).tag(order.rawValue)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(sortOrder.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(SepiaTheme.ui(size: 12))
            .fontWeight(.semibold)
            .foregroundColor(SepiaTheme.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .sepiaControlChrome()
        .help(L10n.tr("Порядок деревьев"))
        .accessibilityLabel(L10n.tr("Порядок деревьев"))
    }

    private func filterField(width: CGFloat? = 230) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(SepiaTheme.inkSoft)
                .accessibilityHidden(true)
            TextField(L10n.tr("Название или фамилия"), text: $filterText)
                .textFieldStyle(.plain)
                .font(SepiaTheme.ui(size: 12))
                .foregroundColor(SepiaTheme.ink)
                .focused($filterFocused)
                .onSubmit { if let first = visibleTrees.first { onSelect(first) } }
            if !filterText.isEmpty {
                Button { filterText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Очистить фильтр"))
            }
        }
        .padding(.horizontal, 8)
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .sepiaControlChrome()
    }

    // MARK: - Content

    private var grid: some View {
        ScrollView {
            gridContent
                .padding(Self.pagePadding)
        }
        .background(widthReader)
    }

    /// Measures the grid's width so ↑/↓ can step a whole row. A plain `GeometryReader`
    /// wrapping the ScrollView both fights the scroll layout and blows up type-checking.
    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in
                columnCount = Self.columns(forWidth: width)
            }
        }
    }

    private static let cardMinWidth: CGFloat = 300
    private static let gridGutter: CGFloat = 16
    private static let pagePadding: CGFloat = 24

    /// Mirrors what `.adaptive(minimum:)` will do with the same width, so arrow-key
    /// row stepping matches what the user actually sees.
    static func columns(forWidth width: CGFloat) -> Int {
        let usable = width - pagePadding * 2 + gridGutter
        let perColumn = cardMinWidth + gridGutter
        return max(1, Int(usable / perColumn))
    }

    private var gridContent: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Self.cardMinWidth, maximum: 420), spacing: Self.gridGutter)],
            spacing: Self.gridGutter
        ) {
            ForEach(visibleTrees, id: \.id) { tree in
                card(for: tree)
            }
        }
    }

    private func card(for tree: FamilyTree) -> some View {
        TreeCardView(
            tree: tree,
            onSelect: { onSelect(tree) },
            onReveal: { onRevealInFinder?(tree) },
            onRename: { startRename(tree) },
            onDelete: { treeToDelete = tree }
        )
        .focused($focusedTreeID, equals: tree.id)
        .onMoveCommand { direction in move(direction, from: tree.id) }
        .onKeyPress(.return) {
            onSelect(tree)
            return .handled
        }
    }

    /// Arrow-key traversal across the grid: ←/→ step one card, ↑/↓ step a whole row.
    private func move(_ direction: MoveCommandDirection, from id: UUID) {
        let list = visibleTrees
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let target: Int
        switch direction {
        case .left:
            guard index % columnCount > 0 else { return }
            target = index - 1
        case .right:
            guard index % columnCount < columnCount - 1 else { return }
            target = index + 1
        case .up:
            target = index - columnCount
        case .down:
            target = index + columnCount
        @unknown default:
            return
        }
        guard list.indices.contains(target) else { return }
        focusedTreeID = list[target].id
    }

    /// First run. Both ways into the app are visible here, because roughly half of these
    /// users arrive holding a GEDCOM exported from Ancestry or MyHeritage rather than a
    /// blank page — and the old empty state told them to create a tree with nothing to click.
    private var emptyLibrary: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 10) {
                Text(L10n.tr("Здесь будут ваши деревья"))
                    .font(SepiaTheme.display(size: 22))
                    .foregroundColor(SepiaTheme.ink)
                Text(L10n.tr("Каждое дерево — это отдельный файл GEDCOM с фотографиями, который остаётся на этом Mac."))
                    .font(SepiaTheme.body(size: 13.5))
                    .foregroundColor(SepiaTheme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            .padding(.bottom, 22)

            HStack(spacing: 10) {
                Button(action: onCreate) {
                    Label(L10n.tr("Новое дерево"), systemImage: "plus")
                }
                .buttonStyle(SepiaButtonStyle(isActive: true))
                Button(action: { onImport?() }) {
                    Label(L10n.tr("Импорт GEDCOM"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SepiaButtonStyle())
            }

            Text(L10n.tr("Понимает файлы из Ancestry, Gramps и MyHeritage."))
                .font(SepiaTheme.ui(size: 11))
                .foregroundColor(SepiaTheme.inkSoft)
                .padding(.top, 14)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var noMatches: some View {
        VStack(spacing: 10) {
            Text(L10n.tr("Ничего не найдено"))
                .font(SepiaTheme.body(size: 16))
                .foregroundColor(SepiaTheme.ink)
            Text(L10n.tr("Ни одно дерево не совпадает с «\(filterText)» по названию или фамилии."))
                .font(SepiaTheme.body(size: 13))
                .foregroundColor(SepiaTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            Button(L10n.tr("Очистить фильтр")) { filterText = "" }
                .buttonStyle(SepiaButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(migrationHeadline)
                        .font(SepiaTheme.body(size: 13.5))
                        .foregroundColor(SepiaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.tr("Открывать и просматривать можно уже сейчас. Обновление нужно, чтобы сохранять изменения — оно делает резервную копию и не удаляет исходные файлы."))
                        .font(SepiaTheme.ui(size: 11))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button(L10n.tr("Обновить формат…")) { showRecovery = true }
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
        default: L10n.tr("\(names.prefix(2).joined(separator: ", ")) и ещё \(names.count - 2)")
        }
        return L10n.tr("\(subject) — в старом формате хранения")
    }

    private var renameSheet: some View {
        ZStack {
            LiquidGlassPanelBackground()

            VStack(spacing: 0) {
                LiquidGlassPanelHeader(
                    title: L10n.tr("Переименовать дерево"),
                    subtitle: L10n.tr("Измените название и подзаголовок дерева."),
                    closeDisabled: renameSaving,
                    onClose: {
                        treeToRename = nil
                        renameValidationMessage = nil
                    }
                )
                .padding(14)

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Название"))
                            .font(SepiaTheme.ui(size: 11))
                            .foregroundColor(SepiaTheme.inkSoft)
                        TextField("", text: $renameName)
                            .textFieldStyle(.plain)
                            .font(SepiaTheme.body(size: 14))
                            .foregroundColor(SepiaTheme.ink)
                            .focused($renameNameFocused)
                            .accessibilityLabel(L10n.tr("Название"))
                            .sepiaFieldChrome(isFocused: renameNameFocused)
                            .onChange(of: renameName) { _, newValue in
                                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    renameValidationMessage = nil
                                }
                            }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Подзаголовок (необязательно)"))
                            .font(SepiaTheme.ui(size: 11))
                            .foregroundColor(SepiaTheme.inkSoft)
                        TextField("", text: $renameSubtitle)
                            .textFieldStyle(.plain)
                            .font(SepiaTheme.body(size: 14))
                            .foregroundColor(SepiaTheme.ink)
                            .focused($renameSubtitleFocused)
                            .accessibilityLabel(L10n.tr("Подзаголовок (необязательно)"))
                            .sepiaFieldChrome(isFocused: renameSubtitleFocused)
                    }

                    if let renameValidationMessage {
                        Label(renameValidationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(SepiaTheme.ui(size: 12))
                            .foregroundColor(SepiaTheme.danger)
                            .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)

                LiquidGlassActionRow {
                    Spacer()

                    Button(L10n.tr("Отмена")) {
                        treeToRename = nil
                        renameValidationMessage = nil
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
                    .disabled(renameSaving)

                    Button(action: saveRenamedTree) {
                        HStack(spacing: 6) {
                            if renameSaving {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                                    .accessibilityHidden(true)
                            }
                            Text(L10n.tr("Сохранить"))
                            if !renameSaving {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(SepiaTheme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameSaving)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 440)
        .interactiveDismissDisabled(renameSaving)
        .onAppear {
            DispatchQueue.main.async { renameNameFocused = true }
        }
    }

    private func saveRenamedTree() {
        guard let tree = treeToRename else { return }
        guard !renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let message = L10n.tr("Введите название дерева.")
            renameValidationMessage = message
            renameNameFocused = true
            sepiaAnnounce(message)
            return
        }

        renameSaving = true
        Task { @MainActor in
            do {
                _ = try await store.renameTreeVerified(tree, name: renameName, subtitle: renameSubtitle)
                renameSaving = false
                treeToRename = nil
                renameValidationMessage = nil
            } catch {
                let message = error.localizedDescription
                renameSaving = false
                renameValidationMessage = message
                sepiaAnnounce(message)
            }
        }
    }

    private func startRename(_ tree: FamilyTree) {
        renameName = tree.name
        renameSubtitle = tree.subtitle ?? ""
        renameValidationMessage = nil
        renameSaving = false
        treeToRename = tree
        DispatchQueue.main.async { renameNameFocused = true }
    }
}

struct TreeCardView: View {
    let tree: FamilyTree
    let onSelect: () -> Void
    var onReveal: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    @Environment(\.locale) private var locale
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var summary: TreeSummary { TreeSummary(tree: tree) }

    @ViewBuilder private var menuItems: some View {
        Button { onRename?() } label: { Label(L10n.tr("Переименовать…"), systemImage: "pencil") }
        Button { onReveal?() } label: { Label(L10n.tr("Показать в Finder"), systemImage: "folder") }
        Divider()
        Button(role: .destructive) { onDelete?() } label: { Label(L10n.tr("Удалить…"), systemImage: "trash") }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 14) {
                TreePortrait(person: summary.portraitPerson, monogram: summary.monogram)
                    .frame(width: 66)
                    .frame(maxHeight: .infinity)

                // Fills the card's height so the Spacer below can actually push the
                // facts to the bottom edge. Without this the column sizes to its
                // content and a tree with no subtitle sits a line higher than its
                // neighbours — the grid stops reading as rows.
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(tree.name)
                            .font(SepiaTheme.display(size: 17))
                            .foregroundColor(SepiaTheme.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(tree.name)
                        // The actions menu is an overlay sibling of this Button, not
                        // part of its label. Reserve its visual footprint here.
                        Spacer(minLength: 34)
                    }

                    // The subtitle row is always rendered, blank or not. Trees without
                    // one would otherwise sit a line higher than their neighbours and
                    // the grid would stop reading as rows.
                    Text(subtitleText)
                        .font(SepiaTheme.body(size: 12))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .lineLimit(1)
                        .help(tree.subtitle ?? "")

                    Spacer(minLength: 6)

                    // Reserved for the same reason as the subtitle row above.
                    Text(summary.surnames.isEmpty ? " " : summary.surnames.joined(separator: " · "))
                        .font(SepiaTheme.ui(size: 12))
                        .foregroundColor(SepiaTheme.accent2)
                        .lineLimit(1)

                    Text(factsLine)
                        .font(SepiaTheme.ui(size: 11.5))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .lineLimit(1)

                    Text(updatedLabel)
                        .font(SepiaTheme.ui(size: 11))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .lineLimit(1)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            // Flexible first, then padded, then pinned to 116: a fixed frame applied
            // to an intrinsically-sized child centres it instead of stretching it,
            // which is what left the portrait short and the rows misaligned.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .frame(height: 116)
            .background(isHovering ? SepiaTheme.cardBgHover : SepiaTheme.cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isHovering ? SepiaTheme.cardLineStrong : SepiaTheme.cardLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                // Keyboard focus is drawn explicitly: `.plain` opts out of the system
                // ring, and without this the grid is untraversable for anyone not
                // using a pointer.
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(SepiaTheme.accent, lineWidth: 2)
                    .padding(-3)
                    .opacity(isFocused ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .focusable()
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(L10n.tr("Открыть дерево"))
        .overlay(alignment: .topTrailing) {
            // An overlay keeps this Menu outside the Button label, so macOS exposes
            // "open tree" and "tree actions" as two honest, focusable controls.
            actionsMenu
                .padding(.top, 8)
                .padding(.trailing, 12)
        }
        .contextMenu { menuItems }
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            }
        }
    }

    private var actionsMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SepiaTheme.inkSoft)
                // The glyph is 13pt; the hit area is not.
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .sepiaControlChrome(height: 24)
        .help(L10n.tr("Действия с деревом"))
        .accessibilityLabel(L10n.tr("Действия с деревом"))
    }

    private var subtitleText: String {
        guard let subtitle = tree.subtitle, !subtitle.isEmpty else { return " " }
        return subtitle
    }

    /// "1876 — 1954 · 42 чел.", degrading to just the count when the tree has no dates.
    private var factsLine: String {
        if let lifespan = summary.lifespan {
            return "\(lifespan) · \(summary.peopleLabel)"
        }
        return summary.peopleLabel
    }

    private var updatedLabel: String {
        let now = Date()
        // A tree parsed a moment ago has `updatedAt` equal to (or a hair past) now, and
        // RelativeDateTimeFormatter renders that as "in 0 seconds". Clamp to the past
        // and give the sub-minute case its own phrasing.
        let interval = now.timeIntervalSince(tree.updatedAt)
        guard interval >= 60 else { return L10n.tr("изменено только что") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return L10n.tr("изменено \(formatter.localizedString(for: tree.updatedAt, relativeTo: now))")
    }

    private var accessibilityDescription: String {
        var parts = [tree.name]
        if let subtitle = tree.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if !summary.surnames.isEmpty { parts.append(summary.surnames.joined(separator: ", ")) }
        parts.append(factsLine)
        parts.append(updatedLabel)
        return parts.joined(separator: ". ")
    }
}

/// The card's visual anchor. A real portrait when the tree has one, otherwise the tree's
/// own initial set in the archive's serif — never a shared icon, because an identical
/// glyph on every card is exactly what made the old library unreadable.
struct TreePortrait: View {
    let person: Person?
    let monogram: String

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [SepiaTheme.photoA, SepiaTheme.photoB],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Text(monogram)
                    .font(SepiaTheme.display(size: 30))
                    .foregroundColor(SepiaTheme.ink.opacity(0.55))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SepiaTheme.cardRule, lineWidth: 1))
        .accessibilityHidden(true)
        .task(id: person?.id) {
            guard let person, person.hasPhoto else {
                image = nil
                return
            }
            // Decoding off the main actor keeps a grid of portraits from stuttering
            // the first paint of the library.
            let data = person.photoData
            image = await Task.detached(priority: .utility) {
                data.flatMap { NSImage(data: $0) }
            }.value
        }
    }
}
