import SwarmCore
import SwiftUI

struct PlacePickerField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    /// Called with the exact selected record. Coordinates and stable identity travel
    /// with the selection; callers never need to parse the formatted display string.
    var onSelect: ((PlaceEntry) -> Void)?

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
                    .onChange(of: text) { old, newValue in
                        // Only show suggestions when the user is actively typing
                        // (i.e. the field is focused). This prevents the list from
                        // opening when the form loads with a pre-filled value.
                        if isFocused { updateSuggestions(newValue) }
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showSuggestions = false
                            }
                        }
                        // Do not refresh on focus gain: that opens the dropdown when an
                        // edit form starts with an existing place.
                    }
                    .onSubmit {
                        // Enter confirms the manually-typed text and closes the list.
                        showSuggestions = false
                        searchWork?.cancel()
                    }

                if showSuggestions && !suggestions.isEmpty {
                    suggestionsDropdown
                        .offset(y: 32)
                }
            }
        }
        .onAppear {
            db.whenReady {
                if isFocused { updateSuggestions(text) }
            }
        }
    }

    private var suggestionsDropdown: some View {
        let rowHeight: CGFloat = 44
        let visibleRows = min(suggestions.count, 6)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions) { place in
                    Button {
                        text = place.displayName
                        showSuggestions = false
                        onSelect?(place)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .font(SepiaTheme.body(size: 13.5))
                                .foregroundColor(SepiaTheme.ink)
                                .lineLimit(1)
                            if !place.region.isEmpty || !place.country.isEmpty {
                                Text([place.region, place.country].filter { !$0.isEmpty }.joined(separator: ", "))
                                    .font(SepiaTheme.ui(size: 11))
                                    .foregroundColor(SepiaTheme.inkSoft)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if place.id != suggestions.last?.id {
                        Divider().overlay(SepiaTheme.fieldLine.opacity(0.5))
                    }
                }
            }
        }
        .frame(height: CGFloat(visibleRows) * rowHeight)
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
        // Debounce, then run the ~455k-row scan on a background queue so typing never
        // blocks the main thread. Each work item checks its cancellation flag, so a
        // result whose query the user has already typed past is discarded (a later
        // keystroke cancels this item before starting its own).
        var work: DispatchWorkItem!
        work = DispatchWorkItem { [db] in
            let results = db.search(trimmed)
            DispatchQueue.main.async {
                guard !work.isCancelled else { return }
                suggestions = results
                showSuggestions = !results.isEmpty
            }
        }
        searchWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
