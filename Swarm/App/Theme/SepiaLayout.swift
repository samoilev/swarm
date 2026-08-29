import SwiftUI

/// Spacing and corner-radius tokens.
///
/// The spacing steps are a 4pt grid. The app previously used 29 distinct padding
/// values and 21 spacing values, including 9, 11, 13, 22, 26 and 34 — off-grid
/// numbers that no other element could line up with.
///
/// The radii are a ladder by *role*, not by taste: a control, a field, a card and
/// a floating panel each have one radius, and nesting one inside another reads
/// correctly because the outer radius is always the larger. The values match what
/// the shipped screens already use, so adopting a token is not a restyle.
enum SepiaLayout {

    // MARK: - Spacing (4pt grid)

    /// Between a glyph and its label, or two parts of one word-sized thing.
    static let xs: CGFloat = 4
    /// Between related controls in a row.
    static let s: CGFloat = 8
    /// Default gap between elements in a stack.
    static let m: CGFloat = 12
    /// Padding inside a card or panel; gap between groups.
    static let l: CGFloat = 16
    /// Between sections of a form or sheet.
    static let xl: CGFloat = 24
    /// Around the content of a full screen.
    static let xxl: CGFloat = 32

    // MARK: - Corner radii (by role)

    enum Radius {
        /// Buttons, menus and other pressable chrome (`SepiaControlSurface`).
        static let control: CGFloat = 7
        /// Text inputs (`sepiaFieldChrome`).
        static let field: CGFloat = 6
        /// Person cards, list rows, thumbnails.
        static let card: CGFloat = 10
        /// Floating glass panels, sheets and their headers.
        static let panel: CGFloat = 18
    }
}
