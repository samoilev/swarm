import SwiftUI

struct PlacePickerField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    
    @State private var suggestions: [PlaceEntry] = []
    @State private var showSuggestions = false
    @State private var searchWork: DispatchWorkItem?
    @FocusState private var isFocused: Bool

    private let db = PlacesDatabase.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(SepiaTheme.ui(size: 9.5))
                .tracking(1.5)
                .foregroundColor(SepiaTheme.inkSoft)
            
            ZStack(alignment: .topLeading) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(SepiaTheme.body(size: 15))
                    .foregroundColor(SepiaTheme.ink)
                    .colorMultiply(Color(hex: "f5eed8"))
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        updateSuggestions(newValue)
                    }
                    .onChange(of: isFocused) { _, focused in
                        if focused && !text.isEmpty {
                            updateSuggestions(text)
                        } else if !focused {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showSuggestions = false
                            }
                        }
                    }
                
                if showSuggestions && !suggestions.isEmpty {
                    suggestionsDropdown
                        .offset(y: 32)
                }
            }
        }
    }
    
    private var suggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { place in
                Button {
                    text = place.displayName
                    showSuggestions = false
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(SepiaTheme.body(size: 13.5))
                            .foregroundColor(SepiaTheme.ink)
                        if !place.region.isEmpty || !place.country.isEmpty {
                            Text([place.region, place.country].filter { !$0.isEmpty }.joined(separator: ", "))
                                .font(SepiaTheme.ui(size: 11))
                                .foregroundColor(SepiaTheme.inkSoft)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.clear)
                .onHover { hovering in }
                
                if place.id != suggestions.last?.id {
                    Divider().overlay(SepiaTheme.fieldLine.opacity(0.5))
                }
            }
        }
        .background(SepiaTheme.cardBg)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .zIndex(100)
    }
    
    private func updateSuggestions(_ query: String) {
        searchWork?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 2 {
            suggestions = []
            showSuggestions = false
            return
        }
        // Debounce: only scan the place DB after the user pauses typing.
        let work = DispatchWorkItem {
            suggestions = db.search(trimmed)
            showSuggestions = !suggestions.isEmpty
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
