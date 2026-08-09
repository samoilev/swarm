import SwarmCore
import SwiftUI

/// Field logic shared by the add-person and edit-person sheets. Both collect the same
/// dates and coordinates through the same controls, so the parsing lives once — a fork
/// here would sooner or later drift on what counts as a valid entry in one sheet only.

/// Fill a coordinate field from a place the user picked, which always carries its own
/// exact coordinates. A place with none leaves the field untouched.
func prefillCoords(for place: PlaceEntry, into coords: Binding<String>) {
    if let c = GeocodingService.shared.coordinate(for: place) {
        coords.wrappedValue = String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}

/// "55.75, 37.61" → a coordinate pair. Anything else is nil, so a half-typed field
/// never reaches the model as a real position.
func parseGraveCoords(_ s: String) -> (lat: Double, lon: Double)? {
    let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
    return (lat, lon)
}

/// Build a `GenealogyDate` from the editor's text, qualifier and optional range end.
/// Invalid input yields nil rather than a half-formed date.
///
/// `original` is the value the sheet opened with: an unparsed date the user did not
/// touch is returned verbatim, so simply opening and saving a record cannot silently
/// discard a date the app never understood. The add sheet has no original and omits it.
func parsedDate(
    text: String,
    end: String,
    qualifier: GenealogyDate.Qualifier,
    original: GenealogyDate? = nil
) -> GenealogyDate? {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    if let original, original.start == nil, text == original.rawValue, qualifier == original.qualifier {
        return original
    }
    let range = qualifier == .between || qualifier == .fromTo
    let value = GenealogyDate(userInput: text, qualifier: qualifier, endValue: range ? end : nil)
    return value.isValid ? value : nil
}
