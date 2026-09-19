import SwarmCore
import SwiftUI

struct ImportPreviewView: View {
    let result: ImportResult
    let onCancel: () -> Void
    let onImport: () -> Void
    @State private var confirmedWarnings = false

    /// Anything the reader should see before committing. Errors that do not refuse
    /// the file still belong here: they are importable, but not silently.
    private var needsConfirmation: Bool {
        !result.report.errors.isEmpty || !result.report.warnings.isEmpty ||
            !result.report.preservedUnsupportedTags.isEmpty ||
            !result.report.unresolvedPointers.isEmpty || !result.report.missingMedia.isEmpty
    }

    private var acknowledgementLabel: String {
        result.report.errors.isEmpty
            ? L10n.tr("Продолжить с этими предупреждениями. Данные, которые нельзя редактировать в Swarm, сохранятся в GEDCOM.")
            : L10n.tr("Продолжить импорт с ошибками. Их можно исправить позже в разделе «Проверка».")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("Предпросмотр импорта")).font(SepiaType.display).foregroundStyle(SepiaTheme.ink)
                    Text(L10n.tr("Копия исходного файла сохранится под именем original-import.ged."))
                        .font(SepiaTheme.ui(size: 10.5)).foregroundStyle(SepiaTheme.inkSoft)
                }
                Spacer()
            }.padding(20)
            Divider().overlay(SepiaTheme.toolbarLine)

            HStack(spacing: 28) {
                metric(L10n.tr("Людей"), result.tree.people.count)
                metric(L10n.tr("Союзов"), result.tree.unions.count)
                metric(L10n.tr("Источников"), result.tree.sourceRecords.count)
                metric(L10n.tr("Ошибок"), result.report.errors.count)
                metric(L10n.tr("Предупреждений"), result.report.warnings.count)
                Spacer()
            }.padding(18)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // Positional identity: the report is fixed while this sheet is open,
                    // and a diagnostic id repeated across two findings would otherwise
                    // leave the list holding empty space where a row belongs.
                    ForEach(Array(result.report.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        diagnosticRow(diagnostic)
                    }
                    if !result.report.preservedUnsupportedTags.isEmpty {
                        reportRow(L10n.tr("Данные, которые нельзя редактировать"), result.report.preservedUnsupportedTags.sorted().joined(separator: ", "), icon: "shippingbox")
                    }
                    if !result.report.unresolvedPointers.isEmpty {
                        reportRow(L10n.tr("Ссылки на отсутствующие записи"), result.report.unresolvedPointers.sorted().joined(separator: ", "), icon: "link.badge.plus")
                    }
                    if !result.report.missingMedia.isEmpty {
                        reportRow(L10n.tr("Не найдены файлы"), result.report.missingMedia.sorted().joined(separator: ", "), icon: "photo.badge.exclamationmark")
                    }
                    if result.report.diagnostics.isEmpty, !needsConfirmation {
                        reportRow(L10n.tr("Ошибок не найдено."), "", icon: "checkmark.seal.fill")
                    }
                }.padding(18)
            }

            if needsConfirmation, result.report.blockingErrors.isEmpty {
                Toggle(acknowledgementLabel, isOn: $confirmedWarnings)
                    .toggleStyle(.checkbox).font(SepiaTheme.body(size: 12)).foregroundStyle(SepiaTheme.ink).padding(.horizontal, 18)
            }
            Divider().overlay(SepiaTheme.toolbarLine)
            LiquidGlassActionRow {
                Button(L10n.tr("Отмена"), action: onCancel)
                    .sepiaGlassButton(.capsule)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.tr("Импортировать"), action: onImport)
                    .sepiaGlassProminentButton(.capsule)
                    .buttonBorderShape(.capsule)
                    .tint(SepiaTheme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!result.report.blockingErrors.isEmpty || (needsConfirmation && !confirmedWarnings))
            }.padding(16)
        }
        .frame(width: SepiaTheme.scaledPanel(680, axis: .horizontal), height: SepiaTheme.scaledPanel(560, axis: .vertical))
        .background(SepiaTheme.paper)
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(SepiaType.title).foregroundStyle(SepiaTheme.ink)
            Text(label.uppercased()).font(SepiaTheme.ui(size: 9)).foregroundStyle(SepiaTheme.inkSoft)
        }
    }

    private func diagnosticRow(_ diagnostic: ImportDiagnostic) -> some View {
        reportRow(
            diagnostic.severity == .error ? L10n.tr("Ошибка") : L10n.tr("Предупреждение"),
            diagnostic.message,
            icon: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
        )
    }

    private func reportRow(_ title: String, _ message: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(SepiaTheme.accent2).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SepiaTheme.body(size: 14)).foregroundStyle(SepiaTheme.ink)
                if !message.isEmpty {
                    Text(message).font(SepiaTheme.ui(size: 10.5)).foregroundStyle(SepiaTheme.inkSoft).textSelection(.enabled)
                }
            }
            Spacer()
        }.padding(12).background(SepiaTheme.cardBg).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
