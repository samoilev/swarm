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
    @State private var showRelationshipSheet = false
    @State private var toastMessage: String?
    @State private var highlightedBranch: Set<UUID> = []
    @State private var lineageLabels: [UUID: String] = [:]
    @State private var inspectorWidth: CGFloat = 320
    @State private var showDeleteConfirm = false
    @State private var personToDelete: Person?
    @State private var fitRequest: Int = 0
    @State private var fanLevels: Int = 4
    @State private var showPhotos: Bool = false
    
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
                    }
                    
                    if selectedPerson != nil {
                        InspectorPanel(person: $selectedPerson, tree: tree, width: $inspectorWidth, onEdit: { person in
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
                }
            }
        }
        .sheet(isPresented: $showExportModal) {
            ExportView(tree: tree, viewMode: viewMode)
        }
        .sheet(isPresented: $showAddSheet) {
            AddPersonView(tree: tree, store: store) { newPerson in
                selectedPerson = newPerson
                showToast("Добавлен: \(newPerson.listName)")
            }
        }
        .sheet(item: $editingPerson) { person in
            EditPersonView(person: person, tree: tree, store: store)
        }
        .sheet(isPresented: $showRelationshipSheet) {
            RelationshipView(tree: tree, isPresented: $showRelationshipSheet, preselectedPerson: selectedPerson)
        }
        .alert("Удалить персону?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) { personToDelete = nil }
            Button("Удалить", role: .destructive) { deletePerson() }
        } message: {
            if let p = personToDelete {
                Text("«\(p.listName)» будет удалена из дерева. Все связи с этой персоной будут разорваны. Это действие нельзя отменить.")
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: selectedPerson?.id) { _, _ in recomputeHighlight() }
        .onChange(of: secondaryPerson?.id) { _, _ in recomputeHighlight() }
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
        } else if let person = selectedPerson {
            // Single selection: show lineage as before
            let calc = LineageCalculator(index: idx)
            let result = calc.compute(for: person)
            highlightedBranch = result.ids
            lineageLabels = result.labels
        } else {
            highlightedBranch = []
            lineageLabels = [:]
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

            titleBlock

            Divider().frame(height: 26).overlay(SepiaTheme.toolbarLine)

            // The view/direction/zoom controls collapse into a native "…" menu
            // when the window is too narrow to show them all (instead of clipping).
            ViewThatFits(in: .horizontal) {
                fullControls
                compactControls
            }

            Spacer(minLength: 8)

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

    // Wide layout: everything inline.
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

    // Narrow layout: keep zoom inline, fold the rest into a native menu.
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

            Button { withAnimation(.easeInOut(duration: 0.2)) { viewMode = .fan } } label: {
                Image(systemName: "chart.pie")
            }
            .buttonStyle(SepiaButtonStyle(isActive: viewMode == .fan))
            .help("Круговая диаграмма предков")

            Button { withAnimation(.easeInOut(duration: 0.2)) { viewMode = .map } } label: {
                Image(systemName: "map")
            }
            .buttonStyle(SepiaButtonStyle(isActive: viewMode == .map))
            .help("Карта мест жизни")
        }
    }

    private var directionControls: some View {
        HStack(spacing: 4) {
            Button { withAnimation { direction = .topDown } } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(SepiaButtonStyle(isActive: direction == .topDown))
            .help("Сверху вниз")
            Button { withAnimation { direction = .leftRight } } label: {
                Image(systemName: "arrow.right")
            }
            .buttonStyle(SepiaButtonStyle(isActive: direction == .leftRight))
            .help("Слева направо")
        }
    }

    private var photosControl: some View {
        Button { showPhotos.toggle() } label: {
            Image(systemName: showPhotos ? "person.crop.square.fill" : "person.crop.square")
        }
        .buttonStyle(SepiaButtonStyle(isActive: showPhotos))
        .help(showPhotos ? "Скрыть фотографии" : "Показать фотографии")
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
            Text("\(Int(zoom * 100))%")
                .font(SepiaTheme.ui(size: 10))
                .foregroundColor(SepiaTheme.inkSoft)
                .frame(width: 34)
            RepeatButton(action: { zoom = min(1.6, zoom + 0.1) }) { Image(systemName: "plus") }
                .help("Увеличить масштаб")
            Button { fitRequest += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(SepiaIconButtonStyle())
                .help("Центрировать и вписать дерево")
            Button { tree.optimizeRoot(); fitRequest += 1 } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                .buttonStyle(SepiaIconButtonStyle())
                .help("Обновить расположение дерева")
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
                Stepper("Поколений: \(fanLevels)", value: $fanLevels, in: 2...8)
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
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button { showAddSheet = true } label: { Image(systemName: "plus") }
                .buttonStyle(SepiaButtonStyle())
                .help("Добавить новую персону в дерево")
            Button { editingPerson = selectedPerson } label: { Image(systemName: "pencil") }
                .buttonStyle(SepiaButtonStyle())
                .disabled(selectedPerson == nil)
                .help("Редактировать выбранную персону")
            Button { showExportModal = true } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(SepiaButtonStyle())
                .help("Экспорт дерева в PDF, PNG или GEDCOM")
        }
    }
    
    private func deletePerson() {
        guard let person = personToDelete else { return }
        let name = person.listName
        
        // Remove from all unions
        for union in tree.unions {
            union.childrenIds.removeAll { $0 == person.id }
            if union.partner1Id == person.id { union.partner1Id = nil }
            if union.partner2Id == person.id { union.partner2Id = nil }
        }
        // Remove empty unions (no partners left)
        tree.unions.removeAll { $0.partner1Id == nil && $0.partner2Id == nil }
        
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
        store.save()
        showToast("Удалён: \(name)")
    }
    
    
    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { toastMessage = nil }
    }
}
