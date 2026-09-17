import AppKit
import SwarmCore
import SwiftUI

struct RecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TreeStore
    /// Which tree the panel opens on. The library shows the whole storage folder and
    /// passes nothing; the workspace arrives from one open tree and passes its id.
    var initialTreeID: UUID?
    @State private var selectedTreeID: UUID?
    /// Which person a deleted file goes back to, chosen per row.
    @State private var restoreTargets: [String: UUID] = [:]
    @State private var items: [RecoveryItem] = []
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isWorking = false

    private var selectedTree: FamilyTree? {
        selectedTreeID.flatMap { id in store.trees.first(where: { $0.id == id }) }
    }

    private func items(_ kind: RecoveryItem.Kind) -> [RecoveryItem] {
        items.filter { $0.kind == kind }
    }

    var body: some View {
        ZStack {
            LiquidGlassPanelBackground()

            VStack(spacing: 0) {
                header
                    .padding(14)

                treePicker
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        migrationSection

                        if items.isEmpty {
                            emptyState
                        } else {
                            group(
                                .deletedFile,
                                title: L10n.tr("Удалённые файлы"),
                                explanation: L10n.tr("Фотографии и документы из карточек. Хранятся 30 дней после удаления.")
                            )
                            group(
                                .migrationBackup,
                                title: L10n.tr("Резервные копии"),
                                explanation: L10n.tr("Дерево со всеми файлами перед обновлением формата, объединением или восстановлением. Хранятся бессрочно.")
                            )
                            group(
                                .archivedTree,
                                title: L10n.tr("Архивированные деревья"),
                                explanation: L10n.tr("Деревья со всеми файлами, убранные из библиотеки. Хранятся до восстановления.")
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(SepiaType.label)
                        .foregroundStyle(SepiaTheme.accent2)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .glassEffect(
                            .regular.tint(SepiaTheme.toolbarBg.opacity(0.2)),
                            in: Capsule()
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                        .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(width: SepiaTheme.scaledPanel(760, axis: .horizontal), height: SepiaTheme.scaledPanel(560, axis: .vertical))
        .onAppear {
            if selectedTreeID == nil { selectedTreeID = initialTreeID ?? store.trees.first?.id }
            refresh()
        }
        .onChange(of: selectedTreeID) { _, _ in restoreTargets = [:]; refresh() }
        .alert(L10n.tr("Не удалось восстановить"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button(L10n.tr("Закрыть"), role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Chrome

    private var header: some View {
        LiquidGlassPanelHeader(
            title: L10n.tr("Восстановление"),
            minimumHeight: 68,
            closeLabel: L10n.tr("Закрыть восстановление"),
            closeDisabled: isWorking,
            onClose: { dismiss() }
        )
    }

    private var treePicker: some View {
        LiquidGlassActionRow {
            Label(L10n.tr("Дерево"), systemImage: "tree")
                .font(SepiaType.control)
                .foregroundStyle(SepiaTheme.ink)

            Picker(L10n.tr("Дерево"), selection: $selectedTreeID) {
                Text(L10n.tr("Все деревья"))
                    .tag(nil as UUID?)
                ForEach(store.trees, id: \.id) {
                    Text($0.name)
                        .tag($0.id as UUID?)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: SepiaTheme.scaled(260))
            .help(L10n.tr("Выберите дерево, файлы и копии которого нужно посмотреть"))

            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash.slash")
                .font(SepiaTheme.icon(size: 32)).foregroundStyle(SepiaTheme.inkSoft.opacity(0.6))
            Text(L10n.tr("Нет файлов или копий для восстановления"))
                .font(SepiaType.bodyLarge).foregroundStyle(SepiaTheme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Migration

    @ViewBuilder private var migrationSection: some View {
        if !store.pendingMigrations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L10n.tr("Обновление формата"), count: store.pendingMigrations.count)
                Text(L10n.tr("Обновите формат дерева, чтобы сохранять изменения. Просмотр доступен без обновления."))
                    .font(SepiaType.label).foregroundStyle(SepiaTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(store.pendingMigrations) { migration in
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.doc").foregroundStyle(SepiaTheme.accent2).frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(migration.title).font(SepiaTheme.body(size: 14)).foregroundStyle(SepiaTheme.ink)
                            Text(migration.source.label)
                                .font(SepiaTheme.ui(size: 10.5)).foregroundStyle(SepiaTheme.inkSoft)
                            Text(migration.url.path(percentEncoded: false))
                                .font(SepiaTheme.ui(size: 9.5)).foregroundStyle(SepiaTheme.inkSoft.opacity(0.8))
                                .lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Button(L10n.tr("Показать в Finder")) { reveal(migration.url) }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                    }
                    .padding(12)
                    .background(SepiaTheme.cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(SepiaTheme.cardLine, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 10) {
                    Button(L10n.tr("Обновить всё (\(store.pendingMigrations.count))")) { runMigrations() }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(SepiaTheme.accent)
                        .disabled(isWorking)
                    Text(L10n.tr("Исходные файлы сохранятся в разделе «Резервные копии»."))
                        .font(SepiaTheme.ui(size: 10.5)).foregroundStyle(SepiaTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Recovery groups

    @ViewBuilder
    private func group(_ kind: RecoveryItem.Kind, title: String, explanation: String) -> some View {
        let groupItems = items(kind)
        if !groupItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(title, count: groupItems.count)
                Text(explanation)
                    .font(SepiaType.label).foregroundStyle(SepiaTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(groupItems) { row($0) }
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count)")
            .font(SepiaTheme.display(size: 15))
            .foregroundStyle(SepiaTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: RecoveryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(item.kind)).foregroundStyle(SepiaTheme.accent2).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle).font(SepiaTheme.body(size: 14)).foregroundStyle(SepiaTheme.ink).lineLimit(1)
                Text(formattedTimestamp(item.createdAt))
                    .font(SepiaTheme.ui(size: 10.5)).foregroundStyle(SepiaTheme.inkSoft)
            }
            Spacer()
            if item.kind == .deletedFile { personPicker(for: item) }
            Button(actionLabel(item.kind)) { restore(item) }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(SepiaTheme.accent)
                .disabled(isWorking || (item.kind == .deletedFile && restoreTargets[item.id] == nil))
                .help(item.kind == .deletedFile && restoreTargets[item.id] == nil
                    ? L10n.tr("Сначала выберите, в чью карточку вернуть файл")
                    : actionLabel(item.kind))
        }
        .padding(12)
        .background(SepiaTheme.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SepiaTheme.cardLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// A deleted file has no owner once it is in the trash, so the target person is
    /// chosen on the row itself rather than in a window-wide picker whose scope is
    /// invisible.
    @ViewBuilder
    private func personPicker(for item: RecoveryItem) -> some View {
        if let tree = selectedTree {
            Picker(L10n.tr("Вернуть в карточку"), selection: Binding(
                get: { restoreTargets[item.id] },
                set: { restoreTargets[item.id] = $0 }
            )) {
                Text(L10n.tr("Выберите человека…")).tag(nil as UUID?)
                ForEach(tree.people.sorted(by: { $0.sortName(language: .current) < $1.sortName(language: .current) }), id: \.id) {
                    Text($0.displayName(language: .current)).tag($0.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(width: 210)
            .accessibilityLabel(L10n.tr("Вернуть файл в карточку человека"))
        }
    }

    // MARK: - Actions

    private func refresh() {
        // Revisions are listed by the version panel, which knows how to describe one.
        // Recovery keeps the three kinds nothing else surfaces.
        items = store.recoveryItems(for: selectedTree).filter { $0.kind != .revision }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func restore(_ item: RecoveryItem) {
        isWorking = true
        Task { @MainActor in
            // The guard-return paths below must not leave the sheet disabled
            // forever (isWorking gates every button, including Close).
            defer { isWorking = false }
            do {
                switch item.kind {
                case .revision:
                    // Filtered out of `items`; the version panel owns restoring these.
                    return
                case .deletedFile:
                    guard let tree = selectedTree,
                          let id = restoreTargets[item.id],
                          let person = tree.person(byId: id) else { return }
                    _ = try await store.restoreDeletedFile(item, to: person, in: tree, asPortrait: item.isPortrait)
                    statusMessage = L10n.tr("«\(item.displayTitle)» возвращён в карточку: \(person.displayName(language: .current)).")
                case .migrationBackup:
                    guard let tree = selectedTree else { return }
                    _ = try await store.restoreFullBackup(item, to: tree)
                    statusMessage = L10n.tr("Дерево восстановлено из копии «\(item.displayTitle)».")
                case .archivedTree:
                    let restored = try store.restoreArchivedTree(item)
                    statusMessage = L10n.tr("«\(restored.name)» снова в библиотеке.")
                }
                refresh()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func runMigrations() {
        isWorking = true
        Task { @MainActor in
            do {
                let receipts = try store.performPendingMigrations()
                statusMessage = L10n.tr("Формат обновлён. Обновлено файлов: \(receipts.count). Резервные копии доступны ниже.")
                if selectedTreeID == nil { selectedTreeID = store.trees.first?.id }
                refresh()
            } catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }

    private func formattedTimestamp(_ date: Date) -> String {
        AppLanguage.current.formatted(date, dateStyle: .medium, timeStyle: .short)
    }

    private func actionLabel(_ kind: RecoveryItem.Kind) -> String {
        switch kind {
        case .revision: L10n.tr("Вернуть эту версию")
        case .deletedFile: L10n.tr("Вернуть файл")
        case .migrationBackup: L10n.tr("Восстановить")
        case .archivedTree: L10n.tr("Вернуть в библиотеку")
        }
    }

    private func icon(_ kind: RecoveryItem.Kind) -> String {
        switch kind {
        case .revision: "clock.arrow.circlepath"
        case .deletedFile: "trash.slash"
        case .migrationBackup: "externaldrive.badge.timemachine"
        case .archivedTree: "archivebox"
        }
    }
}
