import SwarmCore
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
                    Text(L10n.tr("Объединение деревьев")).font(SepiaTheme.display(size: 22)).foregroundStyle(SepiaTheme.ink)
                    Text(L10n.tr("Добавить людей и факты из другого GEDCOM в «\(localTree.name)», не создавая дубликатов."))
                        .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                }
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SepiaTheme.ink)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(L10n.tr("Закрыть"))
            }.padding(20)
            Divider().overlay(SepiaTheme.toolbarLine)

            if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summary(preview)
                        mergeSection(
                            L10n.tr("Точно один и тот же человек"),
                            count: preview.automaticMatches.count,
                            explanation: L10n.tr("Опознаны по идентификатору, записанному в самом файле. Объединятся автоматически.")
                        ) {
                            ForEach(preview.automaticMatches) { match in matchRow(match, selected: true, toggle: nil) }
                        }
                        mergeSection(
                            L10n.tr("Возможно, один и тот же человек"),
                            count: preview.heuristicSuggestions.count,
                            explanation: L10n.tr("Совпали имя, год рождения и ещё один факт. Отметьте тех, кого считаете одним человеком; остальные добавятся как новые.")
                        ) {
                            if preview.heuristicSuggestions.isEmpty {
                                Text(L10n.tr("Похожих людей не нашлось.")).font(SepiaTheme.body(size: 12)).foregroundStyle(SepiaTheme.inkSoft)
                            }
                            ForEach(preview.heuristicSuggestions) { match in
                                matchRow(match, selected: preview.acceptedHeuristicMatchIDs.contains(match.id)) {
                                    toggleSuggestion(match.id)
                                }
                            }
                        }
                        mergeSection(
                            L10n.tr("Расхождения в фактах"),
                            count: preview.conflicts.count,
                            explanation: L10n.tr("Один и тот же факт записан по-разному в двух деревьях. Выберите, что оставить.")
                        ) {
                            ForEach(preview.conflicts.indices, id: \.self) { index in conflictRow(index) }
                        }
                    }.padding(20)
                }
            } else {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "arrow.triangle.merge").font(.system(size: 44)).foregroundStyle(SepiaTheme.inkSoft)
                    Text(L10n.tr("Выберите файл для объединения")).font(SepiaTheme.body(size: 16)).foregroundStyle(SepiaTheme.ink)
                    Text(L10n.tr("Если родственник прислал своё дерево или вы выгрузили его из другого сервиса, объединение перенесёт недостающих людей, даты и источники в ваш архив. Совпадающие персоны сольются в одну, а не задвоятся."))
                        .font(SepiaTheme.body(size: 12.5)).foregroundStyle(SepiaTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460)
                    Text(L10n.tr("Сначала вы увидите предпросмотр — до вашего подтверждения дерево не меняется."))
                        .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                    Button(L10n.tr("Выбрать файл…")) { showImporter = true }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(SepiaTheme.accent)
                }
                Spacer()
            }

            Divider().overlay(SepiaTheme.toolbarLine)
            LiquidGlassActionRow {
                Button(L10n.tr("Отмена"), action: close)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if preview != nil {
                    Button(L10n.tr("Применить с резервной копией")) { applyMerge() }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(SepiaTheme.accent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isApplying)
                }
            }.padding(16)
        }
        .frame(width: 760, height: 620)
        .background(SepiaTheme.paper)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [gedcomType]) { result in
            if case let .success(url) = result { loadPreview(url) }
            if case let .failure(error) = result { errorMessage = error.localizedDescription }
        }
        .alert(L10n.tr("Слияние не выполнено"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .onDisappear { if let pendingURL { store.discardImportPreview(at: pendingURL) } }
    }

    private func summary(_ preview: MergePreview) -> some View {
        HStack(spacing: 28) {
            metric(L10n.tr("Входящих персон"), preview.incomingTree.people.count)
            metric(L10n.tr("Надёжных совпадений"), preview.automaticMatches.count)
            metric(L10n.tr("Предложений"), preview.heuristicSuggestions.count)
            metric(L10n.tr("Новых персон"), preview.incomingOnlyPersonIDs.count)
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
        let local = localTree.person(byId: match.localPersonID)?.displayName(language: .current) ?? "?"
        let incoming = preview?.incomingTree.person(byId: match.incomingPersonID)?
            .displayName(language: .current) ?? "?"
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
            Text(preview?.conflicts[index].field ?? L10n.tr("Факт")).font(SepiaTheme.body(size: 13)).foregroundStyle(SepiaTheme.ink)
            Spacer()
            Picker(L10n.tr("Выбор"), selection: Binding(
                get: { preview?.conflicts[index].choice ?? .both },
                set: { choice in
                    guard var value = preview, value.conflicts.indices.contains(index) else { return }
                    value.conflicts[index].choice = choice
                    preview = value
                }
            )) {
                Text(L10n.tr("Локальное")).tag(MergeFactChoice.local)
                Text(L10n.tr("Входящее")).tag(MergeFactChoice.incoming)
                Text(L10n.tr("Оба")).tag(MergeFactChoice.both)
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
