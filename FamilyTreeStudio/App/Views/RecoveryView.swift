import AppKit
import FamilyTreeCore
import SwiftUI

struct RecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TreeStore
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
        VStack(spacing: 0) {
            header
            Divider().overlay(SepiaTheme.toolbarLine)
            treePicker
            Divider().overlay(SepiaTheme.cardLine)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    migrationSection

                    if items.isEmpty {
                        emptyState
                    } else {
                        group(
                            .revision,
                            title: L10n.tr("Предыдущие версии"),
                            explanation: L10n.tr("Состояние дерева после каждого сохранения. Хранятся последние 50.")
                        )
                        group(
                            .deletedFile,
                            title: L10n.tr("Удалённые файлы"),
                            explanation: L10n.tr("Фотографии и документы, убранные из карточек. Доступны 30 дней, затем удаляются.")
                        )
                        group(
                            .migrationBackup,
                            title: L10n.tr("Полные копии архива"),
                            explanation: L10n.tr("Снимок всего дерева перед крупной операцией — обновлением формата, слиянием. Хранятся бессрочно.")
                        )
                        group(
                            .archivedTree,
                            title: L10n.tr("Архивированные деревья"),
                            explanation: L10n.tr("Деревья, убранные из библиотеки вместе с файлами. Можно вернуть обратно.")
                        )
                    }
                }
                .padding(20)
            }

            if let statusMessage {
                Divider().overlay(SepiaTheme.cardLine)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").font(.system(size: 11))
                    Text(statusMessage).font(SepiaTheme.ui(size: 11))
                }
                .foregroundStyle(SepiaTheme.accent2)
                .padding(10)
            }
        }
        .frame(width: 760, height: 560)
        .background(SepiaTheme.paper)
        .onAppear {
            if selectedTreeID == nil { selectedTreeID = store.trees.first?.id }
            refresh()
        }
        .onChange(of: selectedTreeID) { _, _ in restoreTargets = [:]; refresh() }
        .alert(L10n.tr("Не удалось восстановить"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button(L10n.tr("Закрыть"), role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("Восстановление")).font(SepiaTheme.display(size: 22)).foregroundStyle(SepiaTheme.ink)
                Text(L10n.tr("Здесь лежат прошлые версии дерева, удалённые файлы и резервные копии. Ничего не перезаписывается без вашего подтверждения."))
                    .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(SepiaIconButtonStyle())
                .accessibilityLabel(L10n.tr("Закрыть восстановление"))
        }.padding(20)
    }

    private var treePicker: some View {
        HStack(spacing: 12) {
            Picker(L10n.tr("Архив"), selection: $selectedTreeID) {
                Text(L10n.tr("Все архивы")).tag(nil as UUID?)
                ForEach(store.trees, id: \.id) { Text($0.name).tag($0.id as UUID?) }
            }
            .frame(width: 280)
            .help(L10n.tr("Выберите дерево, историю которого нужно посмотреть"))
            Spacer()
        }.padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32)).foregroundStyle(SepiaTheme.inkSoft.opacity(0.6))
            Text(selectedTree == nil ? L10n.tr("Выберите архив") : L10n.tr("Пока нечего восстанавливать"))
                .font(SepiaTheme.body(size: 15)).foregroundStyle(SepiaTheme.ink)
            Text(selectedTree == nil
                ? L10n.tr("Выберите дерево выше, чтобы увидеть его версии и удалённые файлы.")
                : L10n.tr("Копии появятся сами, когда вы начнёте сохранять изменения и удалять файлы."))
                .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Migration

    @ViewBuilder private var migrationSection: some View {
        if !store.pendingMigrations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L10n.tr("Обновление формата"), count: store.pendingMigrations.count)
                Text(L10n.tr("Эти файлы записаны в старом формате. Они открываются и читаются, но сохранить в них изменения нельзя, пока формат не обновлён."))
                    .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
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
                            .buttonStyle(SepiaButtonStyle())
                    }
                    .padding(10)
                    .background(SepiaTheme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }

                HStack(spacing: 10) {
                    Button(L10n.tr("Обновить всё (\(store.pendingMigrations.count))")) { runMigrations() }
                        .buttonStyle(SepiaButtonStyle(isActive: true)).disabled(isWorking)
                    Text(L10n.tr("Перед обновлением создаётся полная резервная копия. Исходные файлы не удаляются — они переезжают в раздел копий ниже."))
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
                    .font(SepiaTheme.ui(size: 11)).foregroundStyle(SepiaTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(groupItems) { row($0) }
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        Text("\(title.uppercased()) · \(count)")
            .font(SepiaTheme.ui(size: 10)).tracking(1).foregroundStyle(SepiaTheme.inkSoft)
    }

    private func row(_ item: RecoveryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(item.kind)).foregroundStyle(SepiaTheme.accent2).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle).font(SepiaTheme.body(size: 14)).foregroundStyle(SepiaTheme.ink).lineLimit(1)
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(SepiaTheme.ui(size: 10.5)).foregroundStyle(SepiaTheme.inkSoft)
            }
            Spacer()
            if item.kind == .deletedFile { personPicker(for: item) }
            Button(actionLabel(item.kind)) { restore(item) }
                .buttonStyle(SepiaButtonStyle())
                .disabled(isWorking || (item.kind == .deletedFile && restoreTargets[item.id] == nil))
                .help(item.kind == .deletedFile && restoreTargets[item.id] == nil
                    ? L10n.tr("Сначала выберите, в чью карточку вернуть файл")
                    : actionLabel(item.kind))
        }
        .padding(10)
        .background(SepiaTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 7))
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
                Text(L10n.tr("Выберите персону…")).tag(nil as UUID?)
                ForEach(tree.people.sorted(by: { $0.listName < $1.listName }), id: \.id) {
                    Text($0.listName).tag($0.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(width: 210)
            .accessibilityLabel(L10n.tr("Вернуть файл в карточку персоны"))
        }
    }

    // MARK: - Actions

    private func refresh() {
        items = store.recoveryItems(for: selectedTree)
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func restore(_ item: RecoveryItem) {
        isWorking = true
        Task { @MainActor in
            do {
                switch item.kind {
                case .revision:
                    guard let tree = selectedTree else { return }
                    _ = try await store.restoreRevision(item, to: tree)
                    statusMessage = L10n.tr("Версия от \(item.createdAt.formatted(date: .abbreviated, time: .shortened)) восстановлена.")
                case .deletedFile:
                    guard let tree = selectedTree,
                          let id = restoreTargets[item.id],
                          let person = tree.person(byId: id) else { return }
                    _ = try await store.restoreDeletedFile(item, to: person, in: tree, asPortrait: item.isPortrait)
                    statusMessage = L10n.tr("«\(item.displayTitle)» возвращён в карточку: \(person.listName).")
                case .migrationBackup:
                    guard let tree = selectedTree else { return }
                    _ = try await store.restoreFullBackup(item, to: tree)
                    statusMessage = L10n.tr("Архив восстановлен из копии «\(item.displayTitle)».")
                case .archivedTree:
                    let restored = try store.restoreArchivedTree(item)
                    statusMessage = L10n.tr("«\(restored.name)» снова в библиотеке.")
                }
                refresh()
            } catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
    }

    private func runMigrations() {
        isWorking = true
        Task { @MainActor in
            do {
                let receipts = try store.performPendingMigrations()
                statusMessage = L10n.tr("Формат обновлён. Обновлено файлов: \(receipts.count). Резервные копии — в разделе «Полные копии архива».")
                if selectedTreeID == nil { selectedTreeID = store.trees.first?.id }
                refresh()
            } catch { errorMessage = error.localizedDescription }
            isWorking = false
        }
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
