import SwiftUI

// Section heading and read-only label/value row.
//
// Declared inside `InspectorPanel` but used from the add and edit sheets too, so
// the record-detail vocabulary lived in whichever view happened to define it.

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(SepiaTheme.ui(size: 11)).tracking(SepiaType.tracking(11)).foregroundColor(SepiaTheme.accent2).fontWeight(.semibold)
            .padding(.top, 16).padding(.bottom, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(SepiaTheme.fieldLine).frame(height: 1) }
            .padding(.bottom, 10)
    }
}

struct FieldRow: View {
    let label: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(SepiaTheme.ui(size: 11)).tracking(SepiaType.tracking(11)).foregroundColor(SepiaTheme.inkSoft)
            Text(value.isEmpty ? "—" : value).font(SepiaTheme.body(size: 14)).foregroundColor(SepiaTheme.ink)
        }
        .padding(.bottom, 12)
    }
}
