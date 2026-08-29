import SwiftUI

/// A single-line filter/search input in the sepia chrome.
///
/// Exists so the workspace and relationship screens stop reaching for
/// `.textFieldStyle(.roundedBorder)`, which draws the stock macOS field — a
/// different design system on the same row as the sepia controls — and, where it
/// was tinted with `.colorMultiply`, dimmed the system placeholder below AA
/// contrast. Owning the focus state here keeps the call sites one-liners.
struct SepiaSearchField: View {
    let placeholder: String
    @Binding var text: String
    /// Accessibility name. Defaults to the placeholder, which is usually the only
    /// thing naming the field on screen.
    var label: String?

    @FocusState private var isFocused: Bool

    init(_ placeholder: String, text: Binding<String>, label: String? = nil) {
        self.placeholder = placeholder
        _text = text
        self.label = label
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(SepiaType.body)
            .foregroundColor(SepiaTheme.ink)
            .focused($isFocused)
            .accessibilityLabel(label ?? placeholder)
            .sepiaFieldChrome(isFocused: isFocused, placeholder: placeholder, isEmpty: text.isEmpty)
    }
}
