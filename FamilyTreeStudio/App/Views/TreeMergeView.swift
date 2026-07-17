import FamilyTreeCore
import SwiftUI
import UniformTypeIdentifiers

struct TreeMergeView: View {
    @Environment(\.dismiss) private var dismiss
    let localTree: FamilyTree
    let store: TreeStore
    let onMerged: () -> Void
    @State private var showImporter = false
    @State private var pendingURL: URL?
    @State private var preview: MergePreview?
    @State private var errorMessage: String?
    @State private var isApplying = false

    private var gedcomType: UTType { UTType(filenameExtension: "ged") ?? .plainText }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Объединение деревьев").font(SepiaTheme.display(size: 22)).foregroundStyle(SepiaTheme.ink)
                    Text("Добавить людей и факты из другого GEDCOM в «\(localTree.name)», не создавая дубликатов.")
                        .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                }
                Spacer()
                Button { close() } label: { Image(systemName: "xmark") }.buttonStyle(SepiaIconButtonStyle())
            }.padding(20)
            Divider().overlay(SepiaTheme.toolbarLine)

            if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summary(preview)
                        mergeSection(
                            "Точно один и тот же человек",
                            count: preview.automaticMatches.count,
                            explanation: "Опознаны по идентификатору, записанному в самом файле. Объединятся автоматически."
                        ) {
                            ForEach(preview.automaticMatches) { match in matchRow(match, selected: true, toggle: nil) }
                        }
                        mergeSection(
                            "Возможно, один и тот же человек",
                            count: preview.heuristicSuggestions.count,
                            explanation: "Совпали имя, год рождения и ещё один факт. Отметьте тех, кого считаете одним человеком; остальные добавятся как новые."
                        ) {
                            if preview.heuristicSuggestions.isEmpty {
                                Text("Похожих людей не нашлось.").font(SepiaTheme.body(size: 12)).foregroundStyle(SepiaTheme.inkSoft)
                            }
                            ForEach(preview.heuristicSuggestions) { match in
                                matchRow(match, selected: preview.acceptedHeuristicMatchIDs.contains(match.id)) {
                                    toggleSuggestion(match.id)
                                }
                            }
                        }
                        mergeSection(
                            "Расхождения в фактах",
                            count: preview.conflicts.count,
                            explanation: "Один и тот же факт записан по-разному в двух деревьях. Выберите, что оставить."
                        ) {
                            ForEach(preview.conflicts.indices, id: \.self) { index in conflictRow(index) }
                        }
                    }.padding(20)
                }
            } else {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "arrow.triangle.merge").font(.system(size: 44)).foregroundStyle(SepiaTheme.inkSoft)
                    Text("Выберите файл для объединения").font(SepiaTheme.body(size: 16)).foregroundStyle(SepiaTheme.ink)
                    Text("Если родственник прислал своё дерево или вы выгрузили его из другого сервиса, объединение перенесёт недостающих людей, даты и источники в ваш архив. Совпадающие персоны сольются в одну, а не задвоятся.")
                        .font(SepiaTheme.body(size: 12.5)).foregroundStyle(SepiaTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460)
                    Text("Сначала вы увидите предпросмотр — до вашего подтверждения дерево не меняется.")
                        .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                    Button("Выбрать файл…") { showImporter = true }.buttonStyle(SepiaButtonStyle(isActive: true))
                }
                Spacer()
            }

            Divider().overlay(SepiaTheme.toolbarLine)
            HStack {
                Button("Отмена", action: close).buttonStyle(SepiaButtonStyle())
                Spacer()
                if preview != nil {
                    Button("Применить с резервной копией") { applyMerge() }
                        .buttonStyle(SepiaButtonStyle(isActive: true)).disabled(isApplying)
                }
            }.padding(16)
        }
        .frame(width: 760, height: 620)
        .background(SepiaTheme.paper)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [gedcomType]) { result in
            if case let .success(url) = result { loadPreview(url) }
            if case let .failure(error) = result { errorMessage = error.localizedDescription }
        }
        .alert("Слияние не выполнено", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .onDisappear { if let pendingURL { store.discardImportPreview(at: pendingURL) } }
    }

    private func summary(_ preview: MergePreview) -> some View {
        HStack(spacing: 28) {
            metric("Входящих персон", preview.incomingTree.people.count)
            metric("Надёжных совпадений", preview.automaticMatches.count)
            metric("Предложений", preview.heuristicSuggestions.count)
            metric("Новых персон", preview.incomingOnlyPersonIDs.count)
            Spacer()
        }
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(SepiaTheme.display(size: 19)).foregroundStyle(SepiaTheme.ink)
            Text(label.uppercased()).font(SepiaTheme.ui(size: 8.5)).foregroundStyle(SepiaTheme.inkSoft)
        }
    }

    private func mergeSection(
        _ title: String,
        count: Int,
        explanation: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(title.uppercased()) · \(count)")
                    .font(SepiaTheme.ui(size: 10)).tracking(1).foregroundStyle(SepiaTheme.inkSoft)
                Text(explanation)
                    .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }

    private func matchRow(_ match: MergePersonMatch, selected: Bool, toggle: (() -> Void)?) -> some View {
        let local = localTree.person(byId: match.localPersonID)?.listName ?? "?"
        let incoming = preview?.incomingTree.person(byId: match.incomingPersonID)?.listName ?? "?"
        return HStack(spacing: 10) {
            if let toggle { Toggle("", isOn: Binding(get: { selected }, set: { _ in toggle() })).labelsHidden() }
            else { Image(systemName: "checkmark.seal.fill").foregroundStyle(SepiaTheme.pinBirth) }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(local)  ←  \(incoming)").font(SepiaTheme.body(size: 13)).foregroundStyle(SepiaTheme.ink)
                Text(match.reasons.joined(separator: ", ")).font(SepiaTheme.ui(size: 10)).foregroundStyle(SepiaTheme.inkSoft)
            }
            Spacer()
        }.padding(10).background(SepiaTheme.cardBg).clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func conflictRow(_ index: Int) -> some View {
        HStack {
            Text(preview?.conflicts[index].field ?? "Факт").font(SepiaTheme.body(size: 13)).foregroundStyle(SepiaTheme.ink)
            Spacer()
            Picker("Выбор", selection: Binding(
                get: { preview?.conflicts[index].choice ?? .both },
                set: { choice in
                    guard var value = preview, value.conflicts.indices.contains(index) else { return }
                    value.conflicts[index].choice = choice
                    preview = value
                }
            )) {
                Text("Локальное").tag(MergeFactChoice.local)
                Text("Входящее").tag(MergeFactChoice.incoming)
                Text("Оба").tag(MergeFactChoice.both)
            }.pickerStyle(.segmented).frame(width: 260)
        }.padding(10).background(SepiaTheme.cardBg).clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func toggleSuggestion(_ id: String) {
        guard var value = preview else { return }
        if value.acceptedHeuristicMatchIDs.contains(id) { value.acceptedHeuristicMatchIDs.remove(id) }
        else { value.acceptedHeuristicMatchIDs.insert(id) }
        preview = value
    }

    private func loadPreview(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            if let pendingURL { store.discardImportPreview(at: pendingURL) }
            let localCopy = try store.prepareImportPreview(from: url)
            let imported = try GEDCOMCodec.parse(localCopy)
            guard imported.report.blockingErrors.isEmpty else { throw TreeStoreError.invalidImport(report: imported.report) }
            pendingURL = localCopy
            preview = TreeMergeEngine(store: store).preview(local: localTree, incoming: imported.tree)
        } catch { errorMessage = error.localizedDescription }
    }

    private func applyMerge() {
        guard let preview else { return }
        isApplying = true
        Task { @MainActor in
            do {
                _ = try await TreeMergeEngine(store: store).apply(preview, to: localTree)
                onMerged()
                close()
            } catch { errorMessage = error.localizedDescription; isApplying = false }
        }
    }

    private func close() {
        if let pendingURL { store.discardImportPreview(at: pendingURL) }
        pendingURL = nil
        dismiss()
    }
}
