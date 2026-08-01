import SwarmCore
import SwiftUI

struct ImportPreviewView: View {
    let result: ImportResult
    let onCancel: () -> Void
    let onImport: () -> Void
    @State private var confirmedWarnings = false

    private var needsConfirmation: Bool {
        !result.report.warnings.isEmpty || !result.report.preservedUnsupportedTags.isEmpty ||
            !result.report.unresolvedPointers.isEmpty || !result.report.missingMedia.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("Предпросмотр импорта")).font(SepiaTheme.display(size: 22)).foregroundStyle(SepiaTheme.ink)
                    Text(L10n.tr("Исходный файл будет сохранён как original-import.ged"))
                        .font(SepiaTheme.ui(size: 10.5)).foregroundStyle(SepiaTheme.inkSoft)
                }
                Spacer()
            }.padding(20)
            Divider().overlay(SepiaTheme.toolbarLine)

            HStack(spacing: 28) {
                metric(L10n.tr("Персон"), result.tree.people.count)
                metric(L10n.tr("Союзов"), result.tree.unions.count)
                metric(L10n.tr("Источников"), result.tree.sourceRecords.count)
                metric(L10n.tr("Ошибок"), result.report.blockingErrors.count)
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
                        reportRow(L10n.tr("Сохранено без редактирования"), result.report.preservedUnsupportedTags.sorted().joined(separator: ", "), icon: "shippingbox")
                    }
                    if !result.report.unresolvedPointers.isEmpty {
                        reportRow(L10n.tr("Неразрешённые ссылки"), result.report.unresolvedPointers.sorted().joined(separator: ", "), icon: "link.badge.plus")
                    }
                    if !result.report.missingMedia.isEmpty {
                        reportRow(L10n.tr("Не найдены медиа"), result.report.missingMedia.sorted().joined(separator: ", "), icon: "photo.badge.exclamationmark")
                    }
                    if result.report.diagnostics.isEmpty, !needsConfirmation {
                        reportRow(L10n.tr("Проверка пройдена"), L10n.tr("Структура читается, ссылки разрешены."), icon: "checkmark.seal.fill")
                    }
                }.padding(18)
            }

            if needsConfirmation, result.report.blockingErrors.isEmpty {
                Toggle(L10n.tr("Я понимаю предупреждения; сохранённые структуры останутся в GEDCOM"), isOn: $confirmedWarnings)
                    .toggleStyle(.checkbox).font(SepiaTheme.body(size: 12)).foregroundStyle(SepiaTheme.ink).padding(.horizontal, 18)
            }
            Divider().overlay(SepiaTheme.toolbarLine)
            LiquidGlassActionRow {
                Button(L10n.tr("Отмена"), action: onCancel)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.tr("Импортировать проверенную копию"), action: onImport)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(SepiaTheme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!result.report.blockingErrors.isEmpty || (needsConfirmation && !confirmedWarnings))
            }.padding(16)
        }
        .frame(width: 680, height: 560)
        .background(SepiaTheme.paper)
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(SepiaTheme.display(size: 20)).foregroundStyle(SepiaTheme.ink)
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
                Text(message).font(SepiaTheme.ui(size: 10.5)).foregroundStyle(SepiaTheme.inkSoft).textSelection(.enabled)
            }
            Spacer()
        }.padding(12).background(SepiaTheme.cardBg).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
