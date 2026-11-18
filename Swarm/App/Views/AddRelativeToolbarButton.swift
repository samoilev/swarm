import SwarmCore
import SwiftUI

/// The toolbar's "Add relative" button. Lives outside `MainWorkspace`, which is at
/// its line cap.
struct AddRelativeToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text(L10n.tr("Добавить родственника"))
            }
            .fixedSize()
        }
        .sepiaGlassProminentButton()
        .tint(SepiaTheme.accent)
        .help(L10n.tr("Добавить человека"))
        .accessibilityLabel(L10n.tr("Добавить человека"))
        // Room between this and the export button beside it.
        .padding(.trailing, 6)
    }
}
