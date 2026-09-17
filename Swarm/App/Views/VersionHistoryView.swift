import SwarmCore
import SwiftUI

/// The tree's own save history, reachable from the save clock in the workspace toolbar.
/// `RecoveryView` lists the same revisions among three other kinds of backup and lives in
/// the library; this panel answers the narrower question asked from inside an open tree —
/// "what did this look like before?" — and hands the rest off to Recovery.
struct VersionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let tree: FamilyTree
    let store: TreeStore
    /// Opens the full Recovery panel on this tree. The parent owns that sheet: two sheets
    /// cannot be swapped from inside the one being dismissed.
    let onOpenRecovery: () -> Void
    /// Called after a version is applied, so the workspace can rebuild what it derived
    /// from the tree that was just replaced. The library derives nothing and passes none.
    var onRestored: () -> Void = {}

    @State private var items: [RecoveryItem] = []
    /// Record counts per revision, keyed by `RecoveryItem.id`. Filled in the background
    /// after the list is already on screen — reading 50 files must not delay the panel.
    @State private var summaries: [String: RevisionSummary] = [:]
    @State private var pendingRestore: RecoveryItem?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ZStack {
            LiquidGlassPanelBackground()

            VStack(spacing: 0) {
                header
                    .padding(14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        currentRow
                        if items.isEmpty {
                            emptyState
                        } else {
                            ForEach(items) { revisionRow($0) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                // A row cut by the scroll edge should not land on the footer's rule; the
                // gap is what keeps the last visible row reading as part of the list.
                .padding(.bottom, 8)

                footer
            }
        }
        .frame(width: SepiaTheme.scaledPanel(620, axis: .horizontal), height: SepiaTheme.scaledPanel(520, axis: .vertical))
        .onAppear { refresh() }
        .task(id: items.map(\.id)) { await loadSummaries() }
        .confirmationDialog(
            L10n.tr("Вернуть версию от \(pendingRestore.map { formattedTimestamp($0.createdAt) } ?? "")?"),
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.tr("Вернуть версию"), role: .destructive) {
                if let item = pendingRestore { restore(item) }
                pendingRestore = nil
            }
            Button(L10n.tr("Отмена"), role: .cancel) { pendingRestore = nil }
        } message: {
            Text(L10n.tr("Текущая версия сохранится в истории. Вы сможете восстановить её позже."))
        }
        .alert(L10n.tr("Не удалось восстановить"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button(L10n.tr("Закрыть"), role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Chrome

    private var header: some View {
        LiquidGlassPanelHeader(
            title: L10n.tr("Предыдущие версии"),
            subtitle: L10n.tr("Хранятся последние 50 версий дерева. Фотографии и вложения в них не входят."),
            minimumHeight: 68,
            closeLabel: L10n.tr("Закрыть предыдущие версии"),
            closeDisabled: isWorking,
            onClose: { dismiss() }
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    .accessibilityElement(children: .combine)
            }

            HStack(spacing: 10) {
                // A revision is GEDCOM text only; files removed since then come back from
                // the 30-day trash instead. Naming both halves in that order stops the
                // sentence reading as "the files are gone, and also they are kept".
                Text(L10n.tr("Удалённые фотографии и вложения доступны в разделе «Восстановление» в течение 30 дней."))
                    .font(SepiaTheme.ui(size: 10.5))
                    .foregroundStyle(SepiaTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button(L10n.tr("Удалённые файлы и копии…")) {
                    dismiss()
                    onOpenRecovery()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(isWorking)
                .fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .overlay(alignment: .top) {
            // The list scrolls right up to this edge. Without a rule and some air above it,
            // the note reads as one more row of the list rather than a footnote under it.
            Rectangle()
                .fill(SepiaTheme.cardLine)
                .frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32)).foregroundStyle(SepiaTheme.inkSoft.opacity(0.6))
            Text(L10n.tr("Пока нет предыдущих версий"))
                .font(SepiaType.bodyLarge).foregroundStyle(SepiaTheme.ink)
            Text(L10n.tr("Версия записывается при каждом сохранении. Первая появится после следующей правки."))
                .font(SepiaType.label).foregroundStyle(SepiaTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    // MARK: - Rows

    /// The live tree, at the top of its own history. Without it the newest file reads as
    /// the current state, and it is not: history holds what the tree looked like *before*
    /// each save.
    private var currentRow: some View {
        let counts = "\(L10n.count(tree.people.count, .person)) · \(L10n.count(tree.unions.count, .family))"
        return HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(SepiaTheme.accent2).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("Сейчас · сохранено в \(AppLanguage.current.formatted(tree.updatedAt, dateStyle: .none, timeStyle: .short))"))
                    .font(SepiaTheme.body(size: 14)).foregroundStyle(SepiaTheme.ink)
                Text(counts)
                    .font(SepiaTheme.ui(size: 10.5)).foregroundStyle(SepiaTheme.inkSoft)
            }
            Spacer()
        }
        .padding(12)
        .background(SepiaTheme.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SepiaTheme.accent2.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func revisionRow(_ item: RecoveryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(SepiaTheme.accent2).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(formattedTimestamp(item.createdAt))
                    .font(SepiaTheme.body(size: 14)).foregroundStyle(SepiaTheme.ink).lineLimit(1)
                Text(detail(for: item))
                    .font(SepiaTheme.ui(size: 10.5)).foregroundStyle(SepiaTheme.inkSoft)
            }
            Spacer()
            Button(L10n.tr("Вернуть эту версию")) { pendingRestore = item }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(SepiaTheme.accent)
                .disabled(isWorking)
                .help(L10n.tr("Вернуть эту версию"))
        }
        .padding(12)
        .background(SepiaTheme.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SepiaTheme.cardLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("Версия от \(formattedTimestamp(item.createdAt)). \(detail(for: item))"))
    }

    /// Counts plus how the revision differs from the tree as it stands, which is the part
    /// that tells two saves a minute apart from each other.
    private func detail(for item: RecoveryItem) -> String {
        guard let summary = summaries[item.id] else { return L10n.tr("Загрузка…") }
        let counts = "\(L10n.count(summary.people, .person)) · \(L10n.count(summary.families, .family))"
        let delta = summary.people - tree.people.count
        if delta == 0 { return counts }
        return delta > 0
            ? L10n.tr("\(counts) · на \(L10n.count(delta, .person)) больше, чем сейчас")
            : L10n.tr("\(counts) · на \(L10n.count(-delta, .person)) меньше, чем сейчас")
    }

    // MARK: - Actions

    private func refresh() {
        items = store.recoveryItems(for: tree).filter { $0.kind == .revision }
    }

    private func loadSummaries() async {
        for item in items where summaries[item.id] == nil {
            let url = item.url
            guard let summary = await Task.detached(priority: .utility, operation: {
                RevisionSummary.read(at: url)
            }).value else { continue }
            summaries[item.id] = summary
        }
    }

    private func restore(_ item: RecoveryItem) {
        isWorking = true
        Task { @MainActor in
            // Every path has to clear the flag: it gates the close button as well as the
            // restore buttons, so an early return would strand the panel.
            defer { isWorking = false }
            do {
                _ = try await store.restoreRevision(item, to: tree)
                let message = L10n.tr("Версия от \(formattedTimestamp(item.createdAt)) восстановлена.")
                statusMessage = message
                sepiaAnnounce(message)
                // The restore is itself a save, so the pre-restore state is now the newest
                // revision and the counts shift by one row.
                summaries = [:]
                refresh()
                onRestored()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func formattedTimestamp(_ date: Date) -> String {
        AppLanguage.current.formatted(date, dateStyle: .medium, timeStyle: .short)
    }
}
