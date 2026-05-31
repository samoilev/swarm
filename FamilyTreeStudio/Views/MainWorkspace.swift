import SwiftUI

struct MainWorkspace: View {
    @Bindable var tree: FamilyTree
    var store: TreeStore
    let onBack: () -> Void
    
    @State private var viewMode: ViewMode = .tree
    @State private var direction: TreeDirection = .topDown
    @State private var selectedPerson: Person?
    @State private var zoom: CGFloat = 0.85
    @State private var showExportModal = false
    @State private var showAddSheet = false
    @State private var showEditSheet = false
    @State private var showRelationshipSheet = false
    @State private var toastMessage: String?
    @State private var highlightedBranch: Set<UUID> = []
    @State private var inspectorWidth: CGFloat = 320
    @State private var showDeleteConfirm = false
    @State private var personToDelete: Person?
    
    enum ViewMode: String { case tree, fan }
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
                            TreeCanvasView(tree: tree, direction: direction, zoom: $zoom, selectedPerson: $selectedPerson, highlightedIds: highlightedBranch)
                        } else {
                            FanChartView(tree: tree, zoom: zoom, selectedPerson: $selectedPerson)
                        }
                        
                        // Status bar
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Circle().fill(SepiaTheme.accent).frame(width: 8, height: 8)
                                Text("Домашний")
                                    .font(SepiaTheme.ui(size: 11))
                                    .foregroundColor(SepiaTheme.inkSoft)
                                Text("·").foregroundColor(SepiaTheme.inkSoft)
                                Text(viewMode == .fan ? "Нажмите на сектор для просмотра" : "Тяните для перемещения · колёсико для масштаба")
                                    .font(SepiaTheme.ui(size: 11))
                                    .foregroundColor(SepiaTheme.inkSoft)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(SepiaTheme.toolbarBg.opacity(0.9))
                        }
                    }
                    
                    if selectedPerson != nil {
                        InspectorPanel(person: $selectedPerson, tree: tree, width: $inspectorWidth, onEdit: { person in
                            showEditSheet = true
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
                showToast("Добавлен: \(newPerson.fullName)")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let person = selectedPerson {
                EditPersonView(person: person, tree: tree, store: store)
            }
        }
        .sheet(isPresented: $showRelationshipSheet) {
            RelationshipView(tree: tree, isPresented: $showRelationshipSheet, preselectedPerson: selectedPerson)
        }
        .alert("Удалить персону?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) { personToDelete = nil }
            Button("Удалить", role: .destructive) { deletePerson() }
        } message: {
            if let p = personToDelete {
                Text("«\(p.fullName)» будет удалена из дерева. Все связи с этой персоной будут разорваны. Это действие нельзя отменить.")
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
    
    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(SepiaIconButtonStyle())
            .help("Вернуться к списку деревьев")
            
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
            
            Divider().frame(height: 26).overlay(SepiaTheme.toolbarLine)
            
            // View mode
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
            }
            
            if viewMode == .tree {
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
            
            // Zoom
            HStack(spacing: 3) {
                Button { zoom = max(0.25, zoom - 0.1) } label: { Image(systemName: "minus") }
                    .buttonStyle(SepiaIconButtonStyle())
                    .help("Уменьшить масштаб")
                Text("\(Int(zoom * 100))%")
                    .font(SepiaTheme.ui(size: 10))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .frame(width: 34)
                Button { zoom = min(1.6, zoom + 0.1) } label: { Image(systemName: "plus") }
                    .buttonStyle(SepiaIconButtonStyle())
                    .help("Увеличить масштаб")
                Button { zoom = 0.85 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(SepiaIconButtonStyle())
                    .help("Вписать в экран")
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 6) {
                Button { toggleBranchHighlight() } label: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath") }
                    .buttonStyle(SepiaButtonStyle(isActive: !highlightedBranch.isEmpty))
                    .disabled(selectedPerson == nil)
                    .help("Подсветить ветку выбранной персоны")
                Button { showRelationshipSheet = true } label: { Image(systemName: "person.2.wave.2") }
                    .buttonStyle(SepiaButtonStyle())
                    .help("Определить степень родства между двумя персонами")
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
                    .buttonStyle(SepiaButtonStyle())
                    .help("Добавить новую персону в дерево")
                Button { showEditSheet = true } label: { Image(systemName: "pencil") }
                    .buttonStyle(SepiaButtonStyle())
                    .disabled(selectedPerson == nil)
                    .help("Редактировать выбранную персону")
                Button { showExportModal = true } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(SepiaButtonStyle(isActive: true))
                    .help("Экспорт дерева в PDF, PNG или GEDCOM")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(SepiaTheme.toolbarBg)
        .overlay(alignment: .bottom) { Rectangle().fill(SepiaTheme.toolbarLine).frame(height: 1) }
    }
    
    private func deletePerson() {
        guard let person = personToDelete else { return }
        let name = person.fullName
        
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
        
        tree.updatedAt = Date()
        store.save()
        showToast("Удалён: \(name)")
    }
    
    private func toggleBranchHighlight() {
        guard let person = selectedPerson else { highlightedBranch = []; return }
        if !highlightedBranch.isEmpty {
            highlightedBranch = []
            return
        }
        guard let homeId = tree.homePersonId else { return }
        highlightedBranch = computePath(from: homeId, to: person.id)
    }
    
    private func computePath(from startId: UUID, to targetId: UUID) -> Set<UUID> {
        let idx = FamilyIndex(tree: tree)
        var visited = Set<UUID>()
        
        func dfs(_ current: UUID) -> [UUID]? {
            if current == targetId { return [current] }
            if visited.contains(current) { return nil }
            visited.insert(current)
            
            // Go through children
            let unions = idx.unionsOf[current] ?? []
            for union in unions {
                for childId in union.childrenIds {
                    if let path = dfs(childId) { return [current] + path }
                }
                // Also check spouse (to reach via spouse's lineage)
                for pid in union.partnerIds where pid != current {
                    if let path = dfs(pid) { return [current] + path }
                }
            }
            
            // Go through parents
            if let parentUnion = idx.childOf[current] {
                for pid in parentUnion.partnerIds {
                    if let path = dfs(pid) { return [current] + path }
                }
                // Check siblings
                for sibId in parentUnion.childrenIds where sibId != current {
                    if let path = dfs(sibId) { return [current] + path }
                }
            }
            
            return nil
        }
        
        if let path = dfs(startId) {
            return Set(path)
        }
        return Set([startId, targetId])
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { toastMessage = nil }
    }
}
