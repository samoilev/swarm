import AppKit
import SwarmCore
import SwiftUI

struct MainWorkspace: View {
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var tree: FamilyTree
    var store: TreeStore
    /// Shown once when the workspace opens: the confirmation for a write that happened
    /// on the previous screen (a tree just created, an archive just imported).
    var initialToast: String?
    /// The library card that is opening into this workspace. Its diagram nodes hand their
    /// geometry to the matching cards on the canvas, so the record grows out of the card
    /// rather than replacing it.
    var morphNamespace: Namespace.ID?
    var morphingTreeID: UUID?
    let onBack: () -> Void

    @State private var viewMode: ViewMode = .tree
    @State private var direction: TreeDirection = .topDown
    @State private var selectedPerson: Person?
    @State private var secondaryPerson: Person?
    @State private var treeZoom: CGFloat = 0.8
    @State private var fanZoom: CGFloat = 0.8
    @State private var mapZoom: CGFloat = 0.85
    @State private var showExportModal = false
    @State private var showAddSheet = false
    @State private var editingPerson: Person?
    @State private var toastMessage: String?
    @State private var highlightedBranch: Set<UUID> = []
    @State private var highlightedConnections: Set<FamilyConnection> = []
    @State private var lineageLabels: [UUID: String] = [:]
    /// Kinship name shown when two people are ⌘-selected (replaces the old modal).
    @State private var relationshipName: String?
    @State private var inspectorWidth: CGFloat = 320
    @State private var showDeleteConfirm = false
    @State private var personToDelete: Person?
    @State private var fitRequest: Int = 0
    @State private var fanLevels: Int = 4
    @State private var showPhotos: Bool = true
    @State private var showSaveError = false
    @State private var showMerge = false
    /// One-time teaching hint for the ⌘-click dual-select kinship feature.
    @AppStorage("dualSelectHintSeen") private var dualSelectHintSeen = false
    @State private var undo = TreeUndoController()
    @State private var searchActive = false
    @State private var searchQuery = ""
    @State private var searchHighlight = 0
    @FocusState private var searchFieldFocused: Bool
    /// Command-hints row: expanded (full row) while browsing, auto-collapsed to an icon
    /// when a card is open (re-openable by clicking the icon).
    @State private var hintsExpanded = true
    @State private var workspaceIndex: TreeWorkspaceIndexes
    @State private var didShowInitialToast = false
    /// Opening a tree gets one authored arrival: fit the whole record, then focus its
    /// home person at 80%. Switching views later must not replay that entrance.
    @State private var didPerformInitialTreeFocus = false
    /// The compact toolbar is driven by the actual window width, not a device or screen
    /// assumption. At minimum width, secondary controls move into a Notes-style overflow.
    @State private var workspaceWidth: CGFloat = 1200

    enum ViewMode: String, CaseIterable { case tree, fan, map, people, timeline, places, review }
    enum TreeDirection: String { case topDown = "TB", bottomUp = "BT", leftRight = "LR" }

    private var usesCompactToolbar: Bool { workspaceWidth < 1080 }

    /// Tree and fan are free canvases: they can be drawn edge to edge and centred in
    /// whatever is left uncovered. Map and the four list views cannot, so they keep the
    /// inspector in a column of its own.
    private var inspectorFloats: Bool { [.tree, .fan].contains(viewMode) }

    /// How much of the canvas's trailing edge the floating card is sitting on.
    private var canvasTrailingInset: CGFloat {
        selectedPerson != nil && inspectorFloats ? inspectorWidth : 0
    }

    private var inspectorPanel: some View {
        InspectorPanel(
            person: $selectedPerson,
            tree: tree,
            store: store,
            width: $inspectorWidth,
            onEdit: { editingPerson = $0 },
            onDelete: { person in
                personToDelete = person
                showDeleteConfirm = true
            }
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var activeZoom: CGFloat {
        switch viewMode {
        case .tree: treeZoom
        case .fan: fanZoom
        case .map: mapZoom
        default: treeZoom
        }
    }

    /// Exactly the people the library card drew. Only those can receive geometry from it;
    /// everyone else arrives on the entrance cascade the canvas already runs.
    private var morphNodeIDs: Set<UUID> {
        guard tree.id == morphingTreeID, morphNamespace != nil else { return [] }
        return Set(store.diagram(for: tree).nodes.map(\.personId))
    }

    init(
        tree: FamilyTree,
        store: TreeStore,
        initialToast: String? = nil,
        morphNamespace: Namespace.ID? = nil,
        morphingTreeID: UUID? = nil,
        onBack: @escaping () -> Void
    ) {
        self.tree = tree
        self.store = store
        self.initialToast = initialToast
        self.morphNamespace = morphNamespace
        self.morphingTreeID = morphingTreeID
        self.onBack = onBack
        _workspaceIndex = State(initialValue: TreeWorkspaceIndexes(tree: tree))
    }

    private var workspaceSurface: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    canvasArea

                    // A list-shaped view gets its own column: its rows run to the edge,
                    // and anything sliding under floating glass would simply be hidden.
                    if selectedPerson != nil, !inspectorFloats {
                        inspectorPanel
                    }
                }
                // A free canvas keeps its full width and the card floats over it, so the
                // record carries on beneath the glass instead of ending at a seam. The
                // canvas is told how much of its trailing edge is covered, so fitting and
                // centring still answer to the part of it the reader can see.
                .overlay(alignment: .trailing) {
                    if selectedPerson != nil, inspectorFloats {
                        inspectorPanel
                    }
                }
                // Keyed on *whether* a person is selected, not on which one: the panel
                // slides in when it opens and out when it closes, but stays put while the
                // user walks from relative to relative inside it.
                .sepiaMotion(SepiaMotion.panel, value: selectedPerson == nil)
            }

            if let msg = toastMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(SepiaTheme.body(size: 13.5))
                        .foregroundColor(SepiaTheme.paper)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(SepiaTheme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                        .padding(.bottom, 48)
                        .accessibilityElement()
                        .accessibilityLabel(msg)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sepiaMotion(SepiaMotion.state, value: toastMessage != nil)
        .toolbar { workspaceToolbar }
        .toolbarBackground(SepiaTheme.toolbarBg, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
    }

    var body: some View {
        workspaceSurface
            .sheet(isPresented: $showExportModal) {
                ExportView(tree: tree, store: store, selectedIds: highlightedBranch, showPhotos: showPhotos)
            }
            .sheet(isPresented: $showAddSheet) {
                AddPersonView(tree: tree, store: store) { newPerson in
                    selectedPerson = newPerson
                    workspaceIndex.update(person: newPerson, in: tree)
                    showToast(L10n.tr("Добавлен: \(newPerson.displayName(language: .current))"))
                }
            }
            .sheet(item: $editingPerson) { person in
                EditPersonView(person: person, tree: tree, store: store, onSaved: { saved in
                    workspaceIndex.update(person: saved, in: tree)
                    showToast(L10n.tr("Сохранено: \(saved.displayName(language: .current))"))
                })
            }
            .sheet(isPresented: $showMerge) {
                TreeMergeView(localTree: tree, store: store) {
                    workspaceIndex.rebuild(tree: tree)
                    showToast(L10n.tr("Слияние проверено и сохранено"))
                }
            }
            .alert(L10n.tr("Удалить персону?"), isPresented: $showDeleteConfirm) {
                Button(L10n.tr("Отмена"), role: .cancel) { personToDelete = nil }
                Button(L10n.tr("Удалить"), role: .destructive) { deletePerson() }
            } message: {
                if let p = personToDelete {
                    Text(L10n.tr("«\(p.displayName(language: .current))» будет удалена из дерева, а все её связи разорваны. Действие можно отменить сразу после удаления (⌘Z)."))
                }
            }
            .alert(L10n.tr("Не удалось сохранить"), isPresented: $showSaveError) {
                Button("OK", role: .cancel) { store.lastSaveError = nil }
            } message: {
                Text(store.lastSaveError ?? "")
            }
            .frame(minWidth: 900, minHeight: 600)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                workspaceWidth = newWidth
            }
            .onAppear {
                guard let initialToast, !didShowInitialToast else { return }
                didShowInitialToast = true
                showToast(initialToast)
            }
            .onChange(of: selectedPerson?.id) { _, newValue in
                recomputeHighlight()
                // Auto-collapse the hints to an icon when a card opens; restore when browsing.
                withAnimation(reduceMotion ? nil : SepiaMotion.state) { hintsExpanded = (newValue == nil) }
            }
            .onChange(of: secondaryPerson?.id) { _, newValue in
                recomputeHighlight()
                if newValue != nil { dualSelectHintSeen = true }
            }
            .onChange(of: store.lastSaveError) { _, newValue in showSaveError = (newValue != nil) }
            .onChange(of: locale.identifier) { _, _ in
                workspaceIndex.rebuild(tree: tree)
                recomputeHighlight()
            }
            // Snapshot the tree when an editing session opens and record an undo entry
            // when it closes (only if something changed).
            .onChange(of: showAddSheet) { _, isShown in
                if isShown { undo.begin(tree) } else { undo.commit(tree) }
            }
            .onChange(of: editingPerson?.id) { oldValue, newValue in
                if newValue != nil { undo.begin(tree) } else if oldValue != nil { undo.commit(tree) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .undoRequested)) { _ in performUndo() }
            .onReceive(NotificationCenter.default.publisher(for: .redoRequested)) { _ in performRedo() }
            .onReceive(NotificationCenter.default.publisher(for: .findPersonRequested)) { _ in openSearch() }
            // Zoom-in/out notifications are handled inside TreeCanvasView where
            // panOffset and viewport size are available for center-anchored zooming.
            .onReceive(NotificationCenter.default.publisher(for: .zoomFitRequested)) { _ in fitRequest += 1 }
    }

    /// The workspace canvas and everything layered over it. Kept out of `body` because
    /// the combined expression pushed the Swift type checker past its budget on CI, which
    /// fails the build outright rather than merely compiling slowly.
    private var canvasArea: some View {
        ZStack {
            SepiaTheme.paper

            Group {
                if viewMode == .tree {
                    TreeCanvasView(
                        tree: tree,
                        direction: direction,
                        zoom: $treeZoom,
                        selectedPerson: $selectedPerson,
                        secondaryPerson: $secondaryPerson,
                        highlightedIds: highlightedBranch,
                        highlightedConnections: highlightedConnections,
                        lineageLabels: lineageLabels,
                        fitRequest: $fitRequest,
                        initialFocusCompleted: $didPerformInitialTreeFocus,
                        showPhotos: showPhotos,
                        morphNamespace: tree.id == morphingTreeID ? morphNamespace : nil,
                        morphNodeIDs: morphNodeIDs,
                        trailingInset: canvasTrailingInset
                    )
                } else if viewMode == .fan {
                    FanChartView(
                        tree: tree,
                        zoom: $fanZoom,
                        selectedPerson: $selectedPerson,
                        fitRequest: $fitRequest,
                        maxGen: $fanLevels,
                        trailingInset: canvasTrailingInset
                    )
                } else if viewMode == .map {
                    MapChartView(tree: tree, zoom: $mapZoom, selectedPerson: $selectedPerson, fitRequest: $fitRequest)
                } else if viewMode == .people {
                    PeopleWorkspaceView(
                        tree: tree,
                        index: workspaceIndex,
                        selectedPerson: $selectedPerson,
                        onEdit: { editingPerson = $0 }
                    )
                } else if viewMode == .timeline {
                    TimelineWorkspaceView(tree: tree, index: workspaceIndex, selectedPerson: $selectedPerson)
                } else if viewMode == .places {
                    PlacesWorkspaceView(tree: tree, index: workspaceIndex, selectedPerson: $selectedPerson)
                } else {
                    ReviewWorkspaceView(
                        tree: tree,
                        index: workspaceIndex,
                        selectedPerson: $selectedPerson,
                        onEdit: { editingPerson = $0 },
                        onDeleteDuplicate: { person in
                            personToDelete = person
                            showDeleteConfirm = true
                        }
                    )
                }
            }
            .transition(.opacity)

            if tree.people.isEmpty, [.tree, .fan, .map].contains(viewMode) {
                emptyTreeState
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        // One crossfade for the whole canvas stack: swapping tree → fan → map used to be a
        // hard cut, which read as the window being replaced rather than the same tree being
        // drawn a different way.
        .sepiaMotion(SepiaMotion.crossfade, value: viewMode)
        .sepiaMotion(SepiaMotion.state, value: tree.people.isEmpty)
        // The record may run under the inspector card, but nothing the user is meant to
        // read or click may: these centre themselves in the uncovered part of the canvas.
        .overlay(alignment: .top) {
            dualSelectHint
                .sepiaMotion(SepiaMotion.state, value: dualSelectHintSeen)
                .padding(.trailing, canvasTrailingInset)
        }
        .overlay(alignment: .top) {
            relationshipBanner
                .sepiaMotion(SepiaMotion.state, value: relationshipName)
                .padding(.trailing, canvasTrailingInset)
        }
        .overlay(alignment: .top) {
            searchBar
                .sepiaMotion(SepiaMotion.state, value: searchActive)
                .padding(.trailing, canvasTrailingInset)
        }
        .overlay(alignment: .bottom) {
            firstRelativePrompt
                .sepiaMotion(SepiaMotion.state, value: tree.people.count)
                .padding(.trailing, canvasTrailingInset)
        }
        // Six shortcuts are noise on a tree nobody can navigate yet: ↑↓←→ walks kin,
        // ⌘-click names a relationship, ⌘F searches. All of it needs a second person.
        .overlay(alignment: .bottomLeading) {
            if viewMode == .tree, tree.people.count >= 2 { commandHints }
        }
    }

    /// Shown over an empty canvas (no people yet) — the library has an empty state,
    /// the workspace should too, and it gives a clear first action.
    private var emptyTreeState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 46))
                .foregroundColor(SepiaTheme.inkSoft)
            Text(L10n.tr("В дереве пока никого нет"))
                .font(SepiaTheme.body(size: 18))
                .foregroundColor(SepiaTheme.ink)
            Text(L10n.tr("Добавьте первого человека, чтобы начать родословную"))
                .font(SepiaTheme.body(size: 14))
                .foregroundColor(SepiaTheme.inkSoft)
            Button { showAddSheet = true } label: {
                Label(L10n.tr("Добавить первую персону"), systemImage: "plus")
            }
            .buttonStyle(SepiaButtonStyle(isActive: true))
            .padding(.top, 4)
        }
        .padding(32)
    }

    /// A tree with exactly one person is not yet a tree, and onboarding's relationship
    /// step is skippable — so the invitation carries forward here rather than leaving
    /// the user with one card, no labelled action, and a hint about a second person who
    /// doesn't exist.
    @ViewBuilder
    private var firstRelativePrompt: some View {
        if [.tree, .fan].contains(viewMode), tree.people.count == 1, !searchActive, selectedPerson == nil {
            VStack(spacing: 8) {
                Text(L10n.tr("В дереве пока один человек"))
                    .font(SepiaTheme.body(size: 14.5))
                    .foregroundColor(SepiaTheme.ink)
                Text(L10n.tr("Добавьте родственника — тогда появятся связи, родство и круговая диаграмма."))
                    .font(SepiaTheme.ui(size: 11.5))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showAddSheet = true } label: {
                    Label(L10n.tr("Добавить родственника"), systemImage: "person.badge.plus")
                }
                .buttonStyle(SepiaButtonStyle(isActive: true))
                .padding(.top, 4)
            }
            .frame(maxWidth: 380)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(SepiaTheme.panelBg)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
            // Both this and the toast live at the bottom centre; the prompt steps up
            // for the 2.5s a toast is on screen instead of being covered by it.
            .padding(.bottom, toastMessage == nil ? 28 : 96)
            .sepiaMotion(SepiaMotion.state, value: toastMessage == nil)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }

    /// One-time hint that teaches the ⌘-click dual-select kinship feature. Appears
    /// once a single person is selected, dismissible, and never returns once seen.
    /// It needs two people to be true, so it waits for the second one.
    @ViewBuilder
    private var dualSelectHint: some View {
        if viewMode == .tree, tree.people.count >= 2, selectedPerson != nil, secondaryPerson == nil, !dualSelectHintSeen, !searchActive {
            HStack(spacing: 10) {
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 12))
                    .foregroundColor(SepiaTheme.accent2)
                Text(L10n.tr("⌘-щелчок по второму человеку покажет, кем они приходятся друг другу"))
                    .font(SepiaTheme.body(size: 12.5))
                    .foregroundColor(SepiaTheme.ink)
                Button { dualSelectHintSeen = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(SepiaTheme.inkSoft)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("Скрыть подсказку"))
                .accessibilityLabel(L10n.tr("Скрыть подсказку"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(SepiaTheme.panelBg)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .padding(.top, 14)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Shown when two people are ⌘-selected — names the kinship (what the removed
    /// relationship modal used to display), right where the path is highlighted.
    @ViewBuilder
    private var relationshipBanner: some View {
        if viewMode == .tree, let p = selectedPerson, let s = secondaryPerson, let name = relationshipName {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13))
                    .foregroundColor(SepiaTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(SepiaTheme.body(size: 14))
                        .foregroundColor(SepiaTheme.ink)
                    Text("\(p.displayName(language: .current)) → \(s.displayName(language: .current))")
                        .font(SepiaTheme.ui(size: 10.5))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .lineLimit(1)
                }
                Button { secondaryPerson = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(SepiaTheme.inkSoft)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("Сбросить второго человека"))
                .accessibilityLabel(L10n.tr("Сбросить второго человека"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(SepiaTheme.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Find a person (⌘F)

    @ViewBuilder
    private var searchBar: some View {
        if searchActive {
            let results = searchResults
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(SepiaTheme.inkSoft)
                    TextField(L10n.tr("Найти персону…"), text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(SepiaTheme.body(size: 14))
                        .foregroundColor(SepiaTheme.ink)
                        .focused($searchFieldFocused)
                        .onSubmit { selectSearchHighlight() }
                    Button { closeSearch() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(SepiaTheme.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("Закрыть поиск"))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)

                if !results.isEmpty {
                    Divider().overlay(SepiaTheme.cardLine)
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { idx, p in
                            Button { selectSearchResult(p) } label: {
                                HStack(spacing: 8) {
                                    Text(p.displayName(language: .current)).font(SepiaTheme.body(size: 13.5)).foregroundColor(SepiaTheme.ink).lineLimit(1)
                                    Spacer(minLength: 8)
                                    if !p.lifespan.isEmpty {
                                        Text(p.lifespan).font(SepiaTheme.ui(size: 11)).foregroundColor(SepiaTheme.inkSoft)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(idx == searchHighlight ? SepiaTheme.accent.opacity(0.12) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    Divider().overlay(SepiaTheme.cardLine)
                    Text(L10n.tr("Никого не найдено"))
                        .font(SepiaTheme.body(size: 13)).foregroundColor(SepiaTheme.inkSoft)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            .frame(width: 340)
            .background(SepiaTheme.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onExitCommand { closeSearch() }
            .onMoveCommand { moveSearchHighlight($0) }
            .onChange(of: searchQuery) { _, _ in searchHighlight = 0 }
        }
    }

    /// People whose name contains the query (diacritic + case insensitive), capped and sorted.
    private var searchResults: [Person] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return tree.people
            .filter {
                $0.displayName(language: .current)
                    .localizedCaseInsensitiveContains(q)
                    || $0.fullName.localizedCaseInsensitiveContains(q)
            }
            .sorted { $0.sortName(language: .current) < $1.sortName(language: .current) }
            .prefix(8)
            .map { $0 }
    }

    private func selectSearchResult(_ p: Person) {
        selectedPerson = p
        closeSearch()
    }

    private func selectSearchHighlight() {
        let r = searchResults
        guard !r.isEmpty else { return }
        selectSearchResult(r[min(max(searchHighlight, 0), r.count - 1)])
    }

    private func moveSearchHighlight(_ dir: MoveCommandDirection) {
        let count = searchResults.count
        guard count > 0 else { return }
        switch dir {
        case .up: searchHighlight = (searchHighlight - 1 + count) % count
        case .down: searchHighlight = (searchHighlight + 1) % count
        default: break
        }
    }

    private func openSearch() {
        searchQuery = ""
        searchHighlight = 0
        searchActive = true
        DispatchQueue.main.async { searchFieldFocused = true }
    }

    private func closeSearch() {
        searchActive = false
        searchQuery = ""
        searchFieldFocused = false
    }

    // MARK: - Keyboard/gesture hints (bottom-left)

    private var commandHints: some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(reduceMotion ? nil : SepiaMotion.state) { hintsExpanded.toggle() }
            } label: {
                Image(systemName: hintsExpanded ? "chevron.left" : "keyboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .frame(width: 18, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(hintsExpanded ? L10n.tr("Скрыть подсказки") : L10n.tr("Показать горячие клавиши"))
            .accessibilityLabel(hintsExpanded ? L10n.tr("Скрыть подсказки") : L10n.tr("Показать горячие клавиши"))

            if hintsExpanded {
                HStack(spacing: 9) {
                    hint("⌘F", L10n.tr("Поиск"))
                    hintDivider
                    hint("⌘0", L10n.tr("Вписать"))
                    hintDivider
                    hint("⌘±", L10n.tr("Масштаб"))
                    hintDivider
                    hint(symbol: "arrowkeys", L10n.tr("Родня"))
                    hintDivider
                    hint("⌘Z", L10n.tr("Отмена"))
                    hintDivider
                    hint(L10n.tr("⌘-клик"), L10n.tr("Родство"))
                }
                .fixedSize()
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(SepiaTheme.paper.opacity(0.58), in: Capsule())
        .glassEffect(.regular.interactive(), in: Capsule())
        .contentShape(Capsule())
        .padding(12)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        hint(label) {
            Text(key)
                .font(SepiaTheme.ui(size: 10))
                .foregroundColor(SepiaTheme.ink)
        }
    }

    /// The arrow-key hint draws the keys themselves. Four glyphs typed out as "↑↓←→" read
    /// as a direction, not as a thing on the keyboard the reader is meant to press.
    private func hint(symbol: String, _ label: String) -> some View {
        hint(label) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundColor(SepiaTheme.ink)
                .accessibilityHidden(true)
        }
    }

    private func hint(_ label: String, @ViewBuilder key: () -> some View) -> some View {
        HStack(spacing: 4) {
            key()
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(SepiaTheme.btnBg.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(SepiaTheme.cardLine.opacity(0.62), lineWidth: 1)
                }
            Text(label).font(SepiaTheme.ui(size: 10.5)).foregroundColor(SepiaTheme.inkSoft)
        }
        .fixedSize()
    }

    private var hintDivider: some View {
        Rectangle().fill(SepiaTheme.cardLine.opacity(0.4)).frame(width: 1, height: 12)
    }

    private func recomputeHighlight() {
        let idx = FamilyIndex(tree: tree)

        if let primary = selectedPerson, let secondary = secondaryPerson {
            let finder = RelationshipPathFinder(index: idx)
            if let result = finder.findPath(from: primary.id, to: secondary.id) {
                highlightedBranch = result.ids
                highlightedConnections = result.connections
                lineageLabels = result.labels
            } else {
                // Two disconnected people remain selected, but there is no route
                // between them to color.
                highlightedBranch = [primary.id, secondary.id]
                highlightedConnections = []
                lineageLabels = [primary.id: "①", secondary.id: "②"]
            }
            // Name the kinship (the ⌘-click feature now carries what the modal showed).
            relationshipName = RelationshipCalculator(tree: tree).relationship(from: primary, to: secondary)?.name ?? L10n.tr("Связь не найдена")
        } else if let person = selectedPerson {
            // Single selection: show lineage as before
            let calc = LineageCalculator(index: idx)
            let result = calc.compute(for: person)
            highlightedBranch = result.ids
            highlightedConnections = result.connections
            lineageLabels = result.labels
            relationshipName = nil
        } else {
            highlightedBranch = []
            highlightedConnections = []
            lineageLabels = [:]
            relationshipName = nil
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: onBack) {
                Image(systemName: "house.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .foregroundStyle(SepiaTheme.ink)
            .help(L10n.tr("Вернуться к списку деревьев"))
            .accessibilityLabel(L10n.tr("Вернуться к списку деревьев"))
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .navigation) {
            titleBlock
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.fixed)

        ToolbarItemGroup(placement: .automatic) {
            viewModeControls
                .padding(.horizontal, 3)
        }
        .sharedBackgroundVisibility(.visible)

        // The overflow sits beside the controls it stands in for, not across the bar
        // next to the save clock — it is the tail of this group, not a trailing action.
        if usesCompactToolbar {
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .automatic) {
                compactToolbarOverflow
            }
            .sharedBackgroundVisibility(.hidden)
        }

        if !usesCompactToolbar, viewMode == .tree {
            ToolbarSpacer(.fixed)
            ToolbarItemGroup(placement: .automatic) {
                HStack(spacing: 4) {
                    directionControls
                    photosControl
                }
                .padding(.horizontal, 3)
            }
            .sharedBackgroundVisibility(.visible)
        } else if !usesCompactToolbar, viewMode == .fan {
            ToolbarSpacer(.fixed)
            ToolbarItemGroup(placement: .automatic) {
                fanLevelControls
                    .padding(.horizontal, 3)
            }
            .sharedBackgroundVisibility(.visible)
        }

        if !usesCompactToolbar, [.tree, .fan, .map].contains(viewMode) {
            ToolbarSpacer(.fixed)
            ToolbarItemGroup(placement: .automatic) {
                zoomControls
                    .padding(.horizontal, 3)
            }
            .sharedBackgroundVisibility(.visible)
        }

        ToolbarSpacer(.flexible)

        // Save clock rides in the trailing group rather than as its own item: the
        // builder tops out at ten children and the compact overflow now claims one.
        ToolbarItemGroup(placement: .primaryAction) {
            savedStatus
                .padding(.trailing, 6)

            Button { showAddSheet = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(L10n.tr("Добавить родственника"))
                }
                .fixedSize()
            }
            .buttonStyle(.glassProminent)
            .tint(SepiaTheme.accent)
            .help(L10n.tr("Добавить новую персону в дерево"))
            .accessibilityLabel(L10n.tr("Добавить новую персону в дерево"))

            Button { showExportModal = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(SepiaTheme.ink)
            .help(L10n.tr("Экспорт карточек в PDF или GEDCOM"))
            .accessibilityLabel(L10n.tr("Экспорт карточек в PDF или GEDCOM"))
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var compactToolbarOverflow: some View {
        Menu {
            if viewMode == .tree {
                Picker(L10n.tr("Направление дерева"), selection: $direction) {
                    Label(L10n.tr("Сверху вниз"), systemImage: "arrow.down")
                        .tag(TreeDirection.topDown)
                    Label(L10n.tr("Снизу вверх"), systemImage: "arrow.up")
                        .tag(TreeDirection.bottomUp)
                    Label(L10n.tr("Слева направо"), systemImage: "arrow.right")
                        .tag(TreeDirection.leftRight)
                }
                Toggle(isOn: $showPhotos) {
                    Label(
                        showPhotos ? L10n.tr("Скрыть фотографии") : L10n.tr("Показать фотографии"),
                        systemImage: showPhotos ? "person.crop.square.fill" : "person.crop.square"
                    )
                }
            } else if viewMode == .fan {
                Button {
                    if fanLevels > 2 { fanLevels -= 1 }
                } label: {
                    Label(L10n.tr("Меньше поколений"), systemImage: "minus")
                }
                .disabled(fanLevels <= 2)
                Button {
                    if fanLevels < 8 { fanLevels += 1 }
                } label: {
                    Label(L10n.tr("Больше поколений"), systemImage: "plus")
                }
                .disabled(fanLevels >= 8)
            }

            if [.tree, .fan, .map].contains(viewMode) {
                Divider()
                Button { stepZoom(-0.1) } label: {
                    Label(L10n.tr("Уменьшить масштаб"), systemImage: "minus.magnifyingglass")
                }
                Button { stepZoom(0.1) } label: {
                    Label(L10n.tr("Увеличить масштаб"), systemImage: "plus.magnifyingglass")
                }
                Button { fitRequest += 1 } label: {
                    Label(L10n.tr("Центрировать и вписать дерево"), systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }

            if viewMode == .tree {
                Divider()
                treeFunctionMenuItems
            }
        } label: {
            Image(systemName: "chevron.right.2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SepiaTheme.ink)
                // 34, not 30: the export button and the Add Relative capsule beside it
                // are 34 tall, and a 30pt circle read as a different class of control.
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.tr("Показать скрытые элементы панели инструментов"))
        .accessibilityLabel(L10n.tr("Показать скрытые элементы панели инструментов"))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(tree.name.isEmpty ? L10n.tr("Дерево") : tree.name)
                .font(SepiaTheme.display(size: 16))
                .fontWeight(.semibold)
                .foregroundColor(SepiaTheme.ink)
                .lineLimit(1)
            if let sub = tree.subtitle, !sub.isEmpty {
                Text(sub.uppercased())
                    .font(SepiaTheme.ui(size: 9))
                    .tracking(1.5)
                    .foregroundColor(SepiaTheme.inkSoft)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 160, alignment: .leading)
    }

    private var viewModeControls: some View {
        HStack(spacing: 4) {
            Button { viewMode = .tree } label: {
                Image(systemName: "rectangle.connected.to.line.below")
            }
            .buttonStyle(WorkspaceToolbarIconButtonStyle(isActive: viewMode == .tree))
            .help(L10n.tr("Древовидная схема"))
            .accessibilityLabel(L10n.tr("Древовидная схема"))

            Button { viewMode = .map } label: {
                Image(systemName: "map")
            }
            .buttonStyle(WorkspaceToolbarIconButtonStyle(isActive: viewMode == .map))
            .help(L10n.tr("Карта мест жизни"))
            .accessibilityLabel(L10n.tr("Карта мест жизни"))

            Menu {
                Button { viewMode = .fan } label: { Label(L10n.tr("Веер предков"), systemImage: "chart.pie") }
                Divider()
                Button { viewMode = .people } label: { Label(L10n.tr("Люди"), systemImage: "person.3") }
                Button { viewMode = .timeline } label: { Label(L10n.tr("Хронология"), systemImage: "calendar") }
                Button { viewMode = .places } label: { Label(L10n.tr("Места"), systemImage: "mappin.and.ellipse") }
                Button { viewMode = .review } label: { Label(L10n.tr("Проверка"), systemImage: "checklist") }
            } label: {
                let isActive = [.fan, .people, .timeline, .places, .review].contains(viewMode)
                Image(systemName: isActive ? "square.grid.2x2.fill" : "square.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isActive ? .white : SepiaTheme.ink)
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            // The grid menu is one of the view-mode choices, so it wears the accent disc
            // when its section is the one on screen — the two buttons beside it do.
            .toolbarIconChrome(isActive: [.fan, .people, .timeline, .places, .review].contains(viewMode))
            .help(L10n.tr("Варианты отображения"))
            .accessibilityLabel(L10n.tr("Варианты отображения"))
        }
    }

    private var directionControls: some View {
        HStack(spacing: 4) {
            Button { direction = .topDown } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(WorkspaceToolbarIconButtonStyle(isActive: direction == .topDown))
            .help(L10n.tr("Сверху вниз"))
            .accessibilityLabel(L10n.tr("Направление: сверху вниз"))
            .accessibilityValue(direction == .topDown ? L10n.tr("Выбрано") : L10n.tr("Не выбрано"))
            .accessibilityAddTraits(direction == .topDown ? .isSelected : [])
            Button { direction = .bottomUp } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(WorkspaceToolbarIconButtonStyle(isActive: direction == .bottomUp))
            .help(L10n.tr("Снизу вверх"))
            .accessibilityLabel(L10n.tr("Направление: снизу вверх"))
            .accessibilityValue(direction == .bottomUp ? L10n.tr("Выбрано") : L10n.tr("Не выбрано"))
            .accessibilityAddTraits(direction == .bottomUp ? .isSelected : [])
            Button { direction = .leftRight } label: {
                Image(systemName: "arrow.right")
            }
            .buttonStyle(WorkspaceToolbarIconButtonStyle(isActive: direction == .leftRight))
            .help(L10n.tr("Слева направо"))
            .accessibilityLabel(L10n.tr("Направление: слева направо"))
            .accessibilityValue(direction == .leftRight ? L10n.tr("Выбрано") : L10n.tr("Не выбрано"))
            .accessibilityAddTraits(direction == .leftRight ? .isSelected : [])
        }
    }

    private var photosControl: some View {
        Button { withAnimation(reduceMotion ? nil : SepiaMotion.state) { showPhotos.toggle() } } label: {
            Image(systemName: showPhotos ? "person.crop.square.fill" : "person.crop.square")
        }
        .buttonStyle(WorkspaceToolbarIconButtonStyle(isActive: showPhotos))
        .help(showPhotos ? L10n.tr("Скрыть фотографии") : L10n.tr("Показать фотографии"))
        .accessibilityLabel(showPhotos ? L10n.tr("Скрыть фотографии") : L10n.tr("Показать фотографии"))
    }

    private var fanLevelControls: some View {
        HStack(spacing: 3) {
            RepeatButton(chrome: .toolbar, action: { if fanLevels > 2 { fanLevels -= 1 } }) { Image(systemName: "minus") }
                .disabled(fanLevels <= 2)
                .help(L10n.tr("Меньше поколений"))
                .accessibilityLabel(L10n.tr("Меньше поколений"))
            Text("\(fanLevels)")
                .font(SepiaTheme.ui(size: 10))
                .foregroundColor(SepiaTheme.ink)
                .frame(width: 14)
            RepeatButton(chrome: .toolbar, action: { if fanLevels < 8 { fanLevels += 1 } }) { Image(systemName: "plus") }
                .disabled(fanLevels >= 8)
                .help(L10n.tr("Больше поколений"))
                .accessibilityLabel(L10n.tr("Больше поколений"))
            Text(L10n.tr("ур."))
                .font(SepiaTheme.ui(size: 10))
                .foregroundColor(SepiaTheme.inkSoft)
        }
        .help(L10n.tr("Количество поколений"))
    }

    /// Step the zoom. On the tree canvas this goes through the same notification the ⌘±
    /// menu items use, so the step is anchored to the viewport centre and springs — the
    /// buttons used to set `zoom` directly, which left `panOffset` untouched and lurched
    /// the whole tree toward the top-left corner. Fan and map use their own bindings.
    private func stepZoom(_ delta: CGFloat) {
        if viewMode == .tree {
            NotificationCenter.default.post(name: delta > 0 ? .zoomInRequested : .zoomOutRequested, object: nil)
        } else {
            withAnimation(reduceMotion ? nil : SepiaMotion.state) {
                if viewMode == .fan {
                    fanZoom = min(1.6, max(0.25, fanZoom + delta))
                } else if viewMode == .map {
                    mapZoom = min(1.6, max(0.25, mapZoom + delta))
                }
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 3) {
            RepeatButton(chrome: .toolbar, action: { stepZoom(-0.1) }) { Image(systemName: "minus") }
                .help(L10n.tr("Уменьшить масштаб"))
                .accessibilityLabel(L10n.tr("Уменьшить масштаб"))
            Text("\(Int(activeZoom * 100))%")
                .font(SepiaTheme.ui(size: 10))
                .foregroundColor(SepiaTheme.inkSoft)
                .frame(width: 34)
                .contentTransition(.numericText())
                .sepiaMotion(SepiaMotion.state, value: Int(activeZoom * 100))
                .accessibilityLabel(L10n.tr("Масштаб \(Int(activeZoom * 100)) процентов"))
            RepeatButton(chrome: .toolbar, action: { stepZoom(0.1) }) { Image(systemName: "plus") }
                .help(L10n.tr("Увеличить масштаб"))
                .accessibilityLabel(L10n.tr("Увеличить масштаб"))
            Button { fitRequest += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(WorkspaceToolbarIconButtonStyle())
                .help(L10n.tr("Центрировать и вписать дерево"))
                .accessibilityLabel(L10n.tr("Центрировать и вписать дерево"))
            treeFunctionsMenu
        }
    }

    private var treeFunctionsMenu: some View {
        Menu {
            treeFunctionMenuItems
        } label: {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundColor(SepiaTheme.ink)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .toolbarIconChrome()
        .help(L10n.tr("Дополнительные функции дерева"))
        .accessibilityLabel(L10n.tr("Дополнительные функции дерева"))
    }

    @ViewBuilder
    private var treeFunctionMenuItems: some View {
        Button {
            tree.optimizeRoot()
            fitRequest += 1
        } label: {
            Label(L10n.tr("Обновить расположение дерева"), systemImage: "arrow.triangle.2.circlepath")
        }
        Button { showMerge = true } label: {
            Label(L10n.tr("Слить с локальным GEDCOM"), systemImage: "arrow.triangle.merge")
        }
    }

    /// Quiet, always-visible reassurance that the vault is safe — edits persist
    /// immediately, so show that plainly rather than only warning when a save fails.
    private var savedStatus: some View {
        let savedTime = AppLanguage.current.formatted(
            tree.updatedAt,
            dateStyle: .none,
            timeStyle: .short
        )
        return HStack(spacing: 4) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10))
            Text(L10n.tr("Сохранено в \(savedTime)"))
                .font(SepiaTheme.ui(size: 10))
                .contentTransition(.numericText())
                .sepiaMotion(SepiaMotion.state, value: tree.updatedAt)
        }
        .foregroundColor(SepiaTheme.inkSoft)
        .help(L10n.tr("Дерево сохраняется автоматически после каждого изменения"))
        .accessibilityLabel(L10n.tr("Сохранено в \(savedTime)"))
    }

    private func deletePerson() {
        guard let person = personToDelete else { return }
        let name = person.displayName(language: .current)
        undo.begin(tree)

        // Remove the person's attached files from the tree folder.
        store.deleteAttachmentFiles(of: person, in: tree)

        // Remove from all unions
        for union in tree.unions {
            union.childrenIds.removeAll { $0 == person.id }
            if union.partner1Id == person.id { union.partner1Id = nil }
            if union.partner2Id == person.id { union.partner2Id = nil }
        }
        // Remove unions that are now truly empty. A partner-less union that still has
        // children is a valid sibling grouping (possibly for unrelated people), so keep
        // it — only drop unions with no partners AND no children.
        tree.unions.removeAll { $0.partner1Id == nil && $0.partner2Id == nil && $0.childrenIds.isEmpty }

        // Update homePersonId if needed
        if tree.homePersonId == person.id {
            tree.homePersonId = tree.people.first(where: { $0.id != person.id })?.id
        }
        // Update rootUnionId if needed
        if let ruid = tree.rootUnionId, tree.unions.first(where: { $0.id == ruid }) == nil {
            tree.rootUnionId = tree.unions.first?.id
        }

        // Remove person
        tree.people.removeAll { $0.id == person.id }
        tree.parentLinks.removeAll { $0.parentID == person.id || $0.childID == person.id }

        // Clear selection and highlight
        selectedPerson = nil
        highlightedBranch = []
        personToDelete = nil

        tree.optimizeRoot()
        tree.updatedAt = Date()
        Task { @MainActor in
            do {
                _ = try await store.saveTree(tree)
                workspaceIndex.rebuild(tree: tree)
                undo.commit(tree)
                showToast(L10n.tr("Удалён: \(name)"))
            } catch {
                undo.cancel(tree)
                reconcileSelectionAfterRestore()
                workspaceIndex.rebuild(tree: tree)
                showSaveError = true
            }
        }
    }

    private func performUndo() {
        // Refuse while an add/edit sheet is open — restoring under it would discard
        // the editor's in-flight changes.
        guard !undo.isSessionActive, undo.undo(tree) else { return }
        reconcileSelectionAfterRestore()
        Task { @MainActor in
            do {
                _ = try await store.saveTree(tree)
                workspaceIndex.rebuild(tree: tree)
                showToast(L10n.tr("Отменено"))
            } catch {
                _ = undo.redo(tree)
                reconcileSelectionAfterRestore()
                workspaceIndex.rebuild(tree: tree)
                showSaveError = true
            }
        }
    }

    private func performRedo() {
        guard !undo.isSessionActive, undo.redo(tree) else { return }
        reconcileSelectionAfterRestore()
        Task { @MainActor in
            do {
                _ = try await store.saveTree(tree)
                workspaceIndex.rebuild(tree: tree)
                showToast(L10n.tr("Повторено"))
            } catch {
                _ = undo.undo(tree)
                reconcileSelectionAfterRestore()
                workspaceIndex.rebuild(tree: tree)
                showSaveError = true
            }
        }
    }

    /// A restore swaps in fresh Person instances, so the selection (which holds old
    /// references) must be re-resolved by id; anything now gone is cleared.
    private func reconcileSelectionAfterRestore() {
        // Undo/redo swaps in freshly-decoded Person instances that carry the portrait
        // filename but not its (transient) media folder — re-point them so photos load.
        store.refreshMediaFolders(for: tree)
        selectedPerson = selectedPerson.flatMap { sel in tree.people.first { $0.id == sel.id } }
        secondaryPerson = secondaryPerson.flatMap { sel in tree.people.first { $0.id == sel.id } }
        recomputeHighlight()
    }

    private func showToast(_ message: String) {
        withAnimation(reduceMotion ? nil : SepiaMotion.state) { toastMessage = message }
        announce(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(reduceMotion ? nil : SepiaMotion.state) { toastMessage = nil }
        }
    }

    /// Speak a transient status message to VoiceOver — the toast is visual-only,
    /// so assistive tech needs an explicit announcement to learn a save happened.
    private func announce(_ message: String) {
        sepiaAnnounce(message)
    }
}

/// The native toolbar owns the Liquid Glass surface. Items inside a shared glass
/// group keep their resting chrome clear and use the archival accent only for state.
///
/// One disc, one set of states, for every icon control in that shared group — buttons,
/// menus and the auto-repeat steppers alike. The system's own hover highlight only
/// reaches controls that carry their own glass (home, export, the compact overflow),
/// so without this the entire middle of the bar answered the pointer with nothing
/// while its two ends lit up.
struct WorkspaceToolbarIconChrome: ViewModifier {
    var isActive = false
    var isPressed = false

    @State private var isHovered = false
    /// A clamped stepper (fan levels at 2, say) must not light up under the pointer.
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .frame(width: 30, height: 30)
            .background {
                Circle()
                    .fill(
                        isActive
                            ? SepiaTheme.accent
                            : SepiaTheme.ink.opacity(isPressed ? 0.10 : isHovered && isEnabled ? 0.06 : 0)
                    )
            }
            .contentShape(Circle())
            .scaleEffect(isPressed ? 0.94 : 1)
            .onHover { isHovered = $0 }
            .sepiaMotion(SepiaMotion.hover, value: isHovered)
            .sepiaMotion(SepiaMotion.press, value: isPressed)
    }
}

extension View {
    /// Resting chrome for menus embedded in the shared native toolbar background.
    /// `isActive` tints the disc the same way a selected icon button is tinted.
    func toolbarIconChrome(isActive: Bool = false) -> some View {
        modifier(WorkspaceToolbarIconChrome(isActive: isActive))
    }
}

private struct WorkspaceToolbarIconButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isActive ? .white : SepiaTheme.ink)
            .modifier(
                WorkspaceToolbarIconChrome(isActive: isActive, isPressed: configuration.isPressed)
            )
    }
}
