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
    private var gedzipType: UTType { UTType(filenameExtension: "gdz") ?? .zip }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("Объединение деревьев")).font(SepiaType.display).foregroundStyle(SepiaTheme.ink)
                    Text(L10n.tr("Люди и сведения из другого дерева добавятся в «\(localTree.name)»."))
                        .font(SepiaType.label).foregroundStyle(SepiaTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                }
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(SepiaTheme.icon(size: 12, weight: .semibold))
                        .foregroundStyle(SepiaTheme.ink)
                        .frame(width: 30, height: 30)
                }
                .sepiaGlassButton(.circle)
                .buttonBorderShape(.circle)
                .accessibilityLabel(L10n.tr("Закрыть"))
            }.padding(20)
            Divider().overlay(SepiaTheme.toolbarLine)

            if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summary(preview)
                        mergeSection(
                            L10n.tr("Совпадения по идентификатору"),
                            count: preview.automaticMatches.count,
                            explanation: L10n.tr("У этих записей совпадают идентификаторы в файле. Они объединятся автоматически.")
                        ) {
                            ForEach(preview.automaticMatches) { match in matchRow(match, selected: true, toggle: nil) }
                        }
                        mergeSection(
                            L10n.tr("Возможно, это один человек"),
                            count: preview.heuristicSuggestions.count,
                            explanation: L10n.tr("Совпали имя, год рождения и ещё один факт. Отметьте записи об одном и том же человеке, чтобы объединить их. Остальные люди добавятся отдельно.")
                        ) {
                            if preview.heuristicSuggestions.isEmpty {
                                Text(L10n.tr("Похожих людей не найдено.")).font(SepiaTheme.body(size: 12)).foregroundStyle(SepiaTheme.inkSoft)
                            }
                            ForEach(preview.heuristicSuggestions) { match in
                                matchRow(match, selected: preview.acceptedHeuristicMatchIDs.contains(match.id)) {
                                    toggleSuggestion(match.id)
                                }
                            }
                        }
                        mergeSection(
                            L10n.tr("Расхождения в фактах"),
                            count: preview.activeConflicts.count,
                            explanation: L10n.tr("В двух деревьях указаны разные сведения об одном факте. Выберите, какие оставить.")
                        ) {
                            ForEach(preview.activeConflicts) { conflict in conflictRow(conflict) }
                        }
                    }.padding(20)
                }
            } else {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "arrow.triangle.merge").font(SepiaTheme.icon(size: 44)).foregroundStyle(SepiaTheme.inkSoft)
                    Text(L10n.tr("Выберите файл для объединения")).font(SepiaTheme.body(size: 16)).foregroundStyle(SepiaTheme.ink)
                    Text(L10n.tr("Сначала проверьте, что будет добавлено. Дерево изменится только после вашего подтверждения."))
                        .font(SepiaType.label).foregroundStyle(SepiaTheme.inkSoft)
                    Button(L10n.tr("Выбрать файл…")) { showImporter = true }
                        .sepiaGlassProminentButton(.capsule)
                        .buttonBorderShape(.capsule)
                        .tint(SepiaTheme.accent)
                }
                Spacer()
            }

            if preview != nil {
                Text(L10n.tr("Перед объединением будет создана резервная копия."))
                    .font(SepiaType.label).foregroundStyle(SepiaTheme.inkSoft)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            Divider().overlay(SepiaTheme.toolbarLine)
            LiquidGlassActionRow {
                Button(L10n.tr("Отмена"), action: close)
                    .sepiaGlassButton(.capsule)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if preview != nil {
                    Button(L10n.tr("Объединить")) { applyMerge() }
                        .sepiaGlassProminentButton(.capsule)
                        .buttonBorderShape(.capsule)
                        .tint(SepiaTheme.accent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isApplying)
                }
            }.padding(16)
        }
        .frame(width: SepiaTheme.scaledPanel(760, axis: .horizontal), height: SepiaTheme.scaledPanel(620, axis: .vertical))
        .background(SepiaTheme.paper)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [gedcomType, gedzipType]) { result in
            if case let .success(url) = result { loadPreview(url) }
            if case let .failure(error) = result { errorMessage = error.localizedDescription }
        }
        .alert(L10n.tr("Не удалось объединить деревья"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .tracksUnsavedDraft()
        .onDisappear { if let pendingURL { store.discardImportPreview(at: pendingURL) } }
    }

    private func summary(_ preview: MergePreview) -> some View {
        HStack(spacing: 28) {
            metric(L10n.tr("Людей в файле"), preview.incomingTree.people.count)
            metric(L10n.tr("По идентификатору"), preview.automaticMatches.count)
            metric(L10n.tr("Возможных совпадений"), preview.heuristicSuggestions.count)
            metric(L10n.tr("Новых людей"), preview.incomingOnlyPersonIDs.count)
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
                    .font(SepiaType.micro).tracking(SepiaType.tracking(10)).foregroundStyle(SepiaTheme.inkSoft)
                Text(explanation)
                    .font(SepiaType.label).foregroundStyle(SepiaTheme.inkSoft)
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
                Text("\(local)  ←  \(incoming)").font(SepiaType.body).foregroundStyle(SepiaTheme.ink)
                Text(match.reasons.joined(separator: ", ")).font(SepiaType.micro).foregroundStyle(SepiaTheme.inkSoft)
            }
            Spacer()
        }.padding(10).background(SepiaTheme.cardBg).clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func conflictRow(_ conflict: MergeConflict) -> some View {
        HStack {
            Text(conflict.field).font(SepiaType.body).foregroundStyle(SepiaTheme.ink)
            Spacer()
            Picker(L10n.tr("Выбор"), selection: Binding(
                get: { preview?.conflicts.first(where: { $0.id == conflict.id })?.choice ?? .both },
                set: { choice in
                    guard var value = preview,
                          let index = value.conflicts.firstIndex(where: { $0.id == conflict.id }) else { return }
                    value.conflicts[index].choice = choice
                    preview = value
                }
            )) {
                Text(L10n.tr("Из этого дерева")).tag(MergeFactChoice.local)
                Text(L10n.tr("Из файла")).tag(MergeFactChoice.incoming)
                Text(L10n.tr("Оба варианта")).tag(MergeFactChoice.both)
            }.pickerStyle(.segmented).frame(width: SepiaTheme.scaled(260))
        }.padding(10).background(SepiaTheme.cardBg).clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func toggleSuggestion(_ id: String) {
        guard var value = preview else { return }
        if value.acceptedHeuristicMatchIDs.contains(id) {
            value.acceptedHeuristicMatchIDs.remove(id)
        } else {
            // A record can only be the same person as one other record, so accepting a
            // suggestion drops any accepted one that shares either side of the pair.
            if let match = value.heuristicSuggestions.first(where: { $0.id == id }) {
                value.acceptedHeuristicMatchIDs.subtract(value.heuristicSuggestions.filter {
                    $0.id != id
                        && ($0.incomingPersonID == match.incomingPersonID || $0.localPersonID == match.localPersonID)
                }.map(\.id))
            }
            value.acceptedHeuristicMatchIDs.insert(id)
        }
        preview = value
    }

    private func loadPreview(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            if let pendingURL { store.discardImportPreview(at: pendingURL) }
            let localCopy = try store.stageImport(from: url)
            do {
                let imported = try GEDCOMCodec.parse(localCopy)
                guard imported.report.blockingErrors.isEmpty else { throw TreeStoreError.invalidImport(report: imported.report) }
                pendingURL = localCopy
                preview = TreeMergeEngine(store: store).preview(local: localTree, incoming: imported.tree)
            } catch {
                store.discardImportPreview(at: localCopy)
                throw error
            }
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
