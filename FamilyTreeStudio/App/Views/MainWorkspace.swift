import AppKit
import FamilyTreeCore
import SwiftUI

struct MainWorkspace: View {
    @Bindable var tree: FamilyTree
    var store: TreeStore
    let onBack: () -> Void

    @State private var viewMode: ViewMode = .tree
    @State private var direction: TreeDirection = .topDown
    @State private var selectedPerson: Person?
    @State private var secondaryPerson: Person?
    @State private var zoom: CGFloat = 0.85
    @State private var showExportModal = false
    @State private var showAddSheet = false
    @State private var editingPerson: Person?
    @State private var toastMessage: String?
    @State private var highlightedBranch: Set<UUID> = []
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

    enum ViewMode: String { case tree, fan, map }
    enum TreeDirection: String { case topDown = "TB", leftRight = "LR" }

    var body: some View {
        ZStack {
            SepiaTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar

                HStack(spacing: 0) {
                    ZStack {
                        SepiaTheme.paper

                        if viewMode == .tree {
                            TreeCanvasView(tree: tree, direction: direction, zoom: $zoom, selectedPerson: $selectedPerson, secondaryPerson: $secondaryPerson, highlightedIds: highlightedBranch, lineageLabels: lineageLabels, fitRequest: $fitRequest, showPhotos: showPhotos)
                        } else if viewMode == .fan {
                            FanChartView(tree: tree, zoom: $zoom, selectedPerson: $selectedPerson, fitRequest: $fitRequest, maxGen: $fanLevels)
                        } else {
                            MapChartView(tree: tree, zoom: $zoom, selectedPerson: $selectedPerson, fitRequest: $fitRequest)
                        }

                        if tree.people.isEmpty {
                            emptyTreeState
                        }
                    }
                    .overlay(alignment: .top) { dualSelectHint }
                    .overlay(alignment: .top) { relationshipBanner }
                    .overlay(alignment: .top) { searchBar }
                    .overlay(alignment: .bottomLeading) {
                        if viewMode == .tree, !tree.people.isEmpty { commandHints }
                    }

                    if selectedPerson != nil {
                        InspectorPanel(person: $selectedPerson, tree: tree, store: store, width: $inspectorWidth, onEdit: { person in
                            editingPerson = person
                        }, onDelete: { person in
                            personToDelete = person
                            showDeleteConfirm = true
                        })
                        .transition(.move(edge: .trailing))
                    }
                }
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
            }
        }
        .sheet(isPresented: $showExportModal) {
            ExportView(tree: tree, store: store, selectedIds: highlightedBranch, showPhotos: showPhotos)
        }
        .sheet(isPresented: $showAddSheet) {
            AddPersonView(tree: tree, store: store) { newPerson in
                selectedPerson = newPerson
                showToast("Добавлен: \(newPerson.listName)")
            }
        }
        .sheet(item: $editingPerson) { person in
            EditPersonView(person: person, tree: tree, store: store, onSaved: { saved in
                showToast("Сохранено: \(saved.listName)")
            })
        }
        .alert("Удалить персону?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) { personToDelete = nil }
            Button("Удалить", role: .destructive) { deletePerson() }
        } message: {
            if let p = personToDelete {
                Text("«\(p.listName)» будет удалена из дерева, а все её связи разорваны. Действие можно отменить сразу после удаления (⌘Z).")
            }
        }
        .alert("Не удалось сохранить", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { store.lastSaveError = nil }
        } message: {
            Text(store.lastSaveError ?? "")
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: selectedPerson?.id) { _, newValue in
            recomputeHighlight()
            // Auto-collapse the hints to an icon when a card opens; restore when browsing.
            withAnimation(.easeOut(duration: 0.22)) { hintsExpanded = (newValue == nil) }
        }
        .onChange(of: secondaryPerson?.id) { _, newValue in
            recomputeHighlight()
            if newValue != nil { dualSelectHintSeen = true }
        }
        .onChange(of: store.lastSaveError) { _, newValue in showSaveError = (newValue != nil) }
        // Snapshot the tree when an editing session opens and record an undo entry
        // when it closes (only if something actually changed).
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

    /// Shown over an empty canvas (no people yet) — the library has an empty state,
    /// the workspace should too, and it gives a clear first action.
    private var emptyTreeState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 46))
                .foregroundColor(SepiaTheme.inkSoft)
            Text("В дереве пока никого нет")
                .font(SepiaTheme.body(size: 18))
                .foregroundColor(SepiaTheme.ink)
            Text("Добавьте первого человека, чтобы начать родословную")
                .font(SepiaTheme.body(size: 14))
                .foregroundColor(SepiaTheme.inkSoft)
            Button { showAddSheet = true } label: {
                Label("Добавить первую персону", systemImage: "plus")
            }
            .buttonStyle(SepiaButtonStyle(isActive: true))
            .padding(.top, 4)
        }
        .padding(32)
    }

    /// One-time hint that teaches the ⌘-click dual-select kinship feature. Appears
    /// once a single person is selected, dismissible, and never returns once seen.
    @ViewBuilder
    private var dualSelectHint: some View {
        if viewMode == .tree, selectedPerson != nil, secondaryPerson == nil, !dualSelectHintSeen, !searchActive {
            HStack(spacing: 10) {
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 12))
                    .foregroundColor(SepiaTheme.accent2)
                Text("⌘-щелчок по второму человеку покажет, кем они приходятся друг другу")
                    .font(SepiaTheme.body(size: 12.5))
                    .foregroundColor(SepiaTheme.ink)
                Button { dualSelectHintSeen = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(SepiaTheme.inkSoft)
                }
                .buttonStyle(.plain)
                .help("Скрыть подсказку")
                .accessibilityLabel("Скрыть подсказку")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(SepiaTheme.panelBg)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .padding(.top, 14)
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
                    Text("\(p.listName) → \(s.listName)")
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
                .help("Сбросить второго человека")
                .accessibilityLabel("Сбросить второго человека")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(SepiaTheme.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
            .padding(.top, 12)
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
                    TextField("Найти персону…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(SepiaTheme.body(size: 14))
                        .foregroundColor(SepiaTheme.ink)
                        .focused($searchFieldFocused)
                        .onSubmit { selectSearchHighlight() }
                    Button { closeSearch() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(SepiaTheme.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .help("Закрыть поиск")
                }
                .padding(.horizontal, 12).padding(.vertical, 9)

                if !results.isEmpty {
                    Divider().overlay(SepiaTheme.cardLine)
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { idx, p in
                            Button { selectSearchResult(p) } label: {
                                HStack(spacing: 8) {
                                    Text(p.listName).font(SepiaTheme.body(size: 13.5)).foregroundColor(SepiaTheme.ink).lineLimit(1)
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
                    Text("Никого не найдено")
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
            .filter { $0.listName.localizedStandardContains(q) || $0.fullName.localizedStandardContains(q) }
            .sorted { $0.listName.localizedStandardCompare($1.listName) == .orderedAscending }
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
                withAnimation(.easeOut(duration: 0.22)) { hintsExpanded.toggle() }
            } label: {
                Image(systemName: hintsExpanded ? "chevron.left" : "keyboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .frame(width: 18, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(hintsExpanded ? "Скрыть подсказки" : "Показать горячие клавиши")
            .accessibilityLabel(hintsExpanded ? "Скрыть подсказки" : "Показать горячие клавиши")

            if hintsExpanded {
                HStack(spacing: 9) {
                    hint("⌘F", "Поиск")
                    hintDivider
                    hint("⌘0", "Вписать")
                    hintDivider
                    hint("⌘±", "Масштаб")
                    hintDivider
                    hint("↑↓←→", "Родня")
                    hintDivider
                    hint("⌘Z", "Отмена")
                    hintDivider
                    hint("⌘-клик", "Родство")
                }
                .fixedSize()
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(SepiaTheme.paper.opacity(0.9))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(SepiaTheme.cardLine.opacity(0.6), lineWidth: 0.5))
        .padding(12)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(SepiaTheme.ui(size: 10))
                .foregroundColor(SepiaTheme.ink)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(SepiaTheme.btnBg)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(SepiaTheme.cardLine.opacity(0.5), lineWidth: 0.5))
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
            // Dual selection: find path between the two
            let finder = RelationshipPathFinder(index: idx)
            if let result = finder.findPath(from: primary.id, to: secondary.id) {
                highlightedBranch = result.ids
                lineageLabels = result.labels
            } else {
                // No path found — just highlight both
                highlightedBranch = [primary.id, secondary.id]
                lineageLabels = [primary.id: "①", secondary.id: "②"]
            }
            // Name the kinship (the ⌘-click feature now carries what the modal showed).
            relationshipName = RelationshipCalculator(tree: tree).relationship(from: primary, to: secondary)?.name ?? "Связь не найдена"
        } else if let person = selectedPerson {
            // Single selection: show lineage as before
            let calc = LineageCalculator(index: idx)
            let result = calc.compute(for: person)
            highlightedBranch = result.ids
            lineageLabels = result.labels
            relationshipName = nil
        } else {
            highlightedBranch = []
            lineageLabels = [:]
            relationshipName = nil
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(SepiaIconButtonStyle())
            .help("Вернуться к списку деревьев")
            .accessibilityLabel("Вернуться к списку деревьев")

            titleBlock

            Divider().frame(height: 26).overlay(SepiaTheme.toolbarLine)

            // The view/direction/zoom controls collapse into a native "…" menu
            // when the window is too narrow to show them all (instead of clipping).
            ViewThatFits(in: .horizontal) {
                fullControls
                compactControls
            }

            Spacer(minLength: 8)

            savedStatus

            actionButtons
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(SepiaTheme.toolbarBg)
        .overlay(alignment: .bottom) { Rectangle().fill(SepiaTheme.toolbarLine).frame(height: 1) }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(tree.name.isEmpty ? "Дерево" : tree.name)
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

    /// Wide layout: everything inline.
    private var fullControls: some View {
        HStack(spacing: 8) {
            viewModeControls
            if viewMode == .tree {
                directionControls
                photosControl
            }
            if viewMode == .fan {
                fanLevelControls
            }
            zoomControls
        }
    }

    /// Narrow layout: keep zoom inline, fold the rest into a native menu.
    private var compactControls: some View {
        HStack(spacing: 8) {
            zoomControls
            overflowMenu
        }
    }

    private var viewModeControls: some View {
        HStack(spacing: 4) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { viewMode = .tree } } label: {
                Image(systemName: "rectangle.connected.to.line.below")
            }
            .buttonStyle(SepiaButtonStyle(isActive: viewMode == .tree))
            .help("Древовидная схема")
            .accessibilityLabel("Древовидная схема")

            Button { withAnimation(.easeInOut(duration: 0.2)) { viewMode = .fan } } label: {
                Image(systemName: "chart.pie")
            }
            .buttonStyle(SepiaButtonStyle(isActive: viewMode == .fan))
            .help("Круговая диаграмма предков")
            .accessibilityLabel("Круговая диаграмма предков")

            Button { withAnimation(.easeInOut(duration: 0.2)) { viewMode = .map } } label: {
                Image(systemName: "map")
            }
            .buttonStyle(SepiaButtonStyle(isActive: viewMode == .map))
            .help("Карта мест жизни")
            .accessibilityLabel("Карта мест жизни")
        }
    }

    private var directionControls: some View {
        HStack(spacing: 4) {
            Button { withAnimation { direction = .topDown } } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(SepiaButtonStyle(isActive: direction == .topDown))
            .help("Сверху вниз")
            .accessibilityLabel("Направление: сверху вниз")
            Button { withAnimation { direction = .leftRight } } label: {
                Image(systemName: "arrow.right")
            }
            .buttonStyle(SepiaButtonStyle(isActive: direction == .leftRight))
            .help("Слева направо")
            .accessibilityLabel("Направление: слева направо")
        }
    }

    private var photosControl: some View {
        Button { showPhotos.toggle() } label: {
            Image(systemName: showPhotos ? "person.crop.square.fill" : "person.crop.square")
        }
        .buttonStyle(SepiaButtonStyle(isActive: showPhotos))
        .help(showPhotos ? "Скрыть фотографии" : "Показать фотографии")
        .accessibilityLabel(showPhotos ? "Скрыть фотографии" : "Показать фотографии")
    }

    private var fanLevelControls: some View {
        HStack(spacing: 3) {
            RepeatButton(action: { if fanLevels > 2 { fanLevels -= 1 } }) { Image(systemName: "minus") }
                .disabled(fanLevels <= 2)
            Text("\(fanLevels)")
                .font(SepiaTheme.ui(size: 10))
                .foregroundColor(SepiaTheme.ink)
                .frame(width: 14)
            RepeatButton(action: { if fanLevels < 8 { fanLevels += 1 } }) { Image(systemName: "plus") }
                .disabled(fanLevels >= 8)
            Text("ур.")
                .font(SepiaTheme.ui(size: 10))
                .foregroundColor(SepiaTheme.inkSoft)
        }
        .help("Количество поколений")
    }

    private var zoomControls: some View {
        HStack(spacing: 3) {
            RepeatButton(action: { zoom = max(0.25, zoom - 0.1) }) { Image(systemName: "minus") }
                .help("Уменьшить масштаб")
                .accessibilityLabel("Уменьшить масштаб")
            Text("\(Int(zoom * 100))%")
                .font(SepiaTheme.ui(size: 10))
                .foregroundColor(SepiaTheme.inkSoft)
                .frame(width: 34)
                .accessibilityLabel("Масштаб \(Int(zoom * 100)) процентов")
            RepeatButton(action: { zoom = min(1.6, zoom + 0.1) }) { Image(systemName: "plus") }
                .help("Увеличить масштаб")
                .accessibilityLabel("Увеличить масштаб")
            Button { fitRequest += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(SepiaIconButtonStyle())
                .help("Центрировать и вписать дерево")
                .accessibilityLabel("Центрировать и вписать дерево")
            Button { tree.optimizeRoot(); fitRequest += 1 } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                .buttonStyle(SepiaIconButtonStyle())
                .help("Обновить расположение дерева")
                .accessibilityLabel("Обновить расположение дерева")
        }
    }

    private var overflowMenu: some View {
        Menu {
            Picker("Вид", selection: $viewMode) {
                Label("Дерево", systemImage: "rectangle.connected.to.line.below").tag(ViewMode.tree)
                Label("Веер предков", systemImage: "chart.pie").tag(ViewMode.fan)
                Label("Карта", systemImage: "map").tag(ViewMode.map)
            }
            if viewMode == .tree {
                Picker("Направление", selection: $direction) {
                    Label("Сверху вниз", systemImage: "arrow.down").tag(TreeDirection.topDown)
                    Label("Слева направо", systemImage: "arrow.right").tag(TreeDirection.leftRight)
                }
                Toggle("Фотографии", isOn: $showPhotos)
            }
            if viewMode == .fan {
                Stepper("Поколений: \(fanLevels)", value: $fanLevels, in: 2 ... 8)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 30, height: 30)
                .foregroundColor(SepiaTheme.ink)
                .background(SepiaTheme.btnBg)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Ещё")
        .accessibilityLabel("Ещё настройки вида")
    }

    /// Quiet, always-visible reassurance that the vault is safe — edits persist
    /// immediately, so show that plainly rather than only warning when a save fails.
    private var savedStatus: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10))
            Text("Сохранено в \(tree.updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(SepiaTheme.ui(size: 10))
        }
        .foregroundColor(SepiaTheme.inkSoft)
        .help("Дерево сохраняется автоматически после каждого изменения")
        .accessibilityLabel("Сохранено в \(tree.updatedAt.formatted(date: .omitted, time: .shortened))")
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button { showAddSheet = true } label: { Image(systemName: "plus") }
                .buttonStyle(SepiaButtonStyle())
                .help("Добавить новую персону в дерево")
                .accessibilityLabel("Добавить новую персону в дерево")
            Button { showExportModal = true } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(SepiaButtonStyle())
                .help("Экспорт карточек в PDF или GEDCOM")
                .accessibilityLabel("Экспорт карточек в PDF или GEDCOM")
        }
    }

    private func deletePerson() {
        guard let person = personToDelete else { return }
        let name = person.listName
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

        // Clear selection and highlight
        selectedPerson = nil
        highlightedBranch = []
        personToDelete = nil

        tree.optimizeRoot()
        tree.updatedAt = Date()
        store.saveTree(tree)
        undo.commit(tree)
        showToast("Удалён: \(name)")
    }

    private func performUndo() {
        // Refuse while an add/edit sheet is open — restoring under it would discard
        // the editor's in-flight changes.
        guard !undo.isSessionActive, undo.undo(tree) else { return }
        reconcileSelectionAfterRestore()
        store.saveTree(tree)
        showToast("Отменено")
    }

    private func performRedo() {
        guard !undo.isSessionActive, undo.redo(tree) else { return }
        reconcileSelectionAfterRestore()
        store.saveTree(tree)
        showToast("Повторено")
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
        toastMessage = message
        announce(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { toastMessage = nil }
    }

    /// Speak a transient status message to VoiceOver — the toast is visual-only,
    /// so assistive tech needs an explicit announcement to learn a save happened.
    private func announce(_ message: String) {
        guard let window = NSApp.keyWindow else { return }
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}
