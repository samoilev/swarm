import SwiftUI

/// The app's type scale. Sits beside the colour and motion tokens so a size is
/// chosen once rather than re-invented per view.
///
/// Seven steps, distilled from what the screens already use most: before this the
/// app requested 30 distinct sizes, half of them half-point (9.5, 10.5, 12.5, …),
/// which is drift rather than hierarchy. Each step below names the job it does; if
/// a view needs a size that is not here, the question is which job it is doing, not
/// which number looks right.
///
/// Sizes are fixed points, deliberately: the canvas, fan chart and PDF share these
/// metrics with hand-tuned card geometry, so Dynamic Type is not adopted. Every
/// call site routes through this enum, so that decision lives in one file.
enum SepiaType {
    // Display — serif semibold. Titles that name a screen or a sheet.

    /// Sheet and panel titles ("Экспорт", "Слияние").
    static let display = SepiaTheme.display(size: 22)
    /// Section titles inside a panel, and the inspector's person name.
    static let title = SepiaTheme.display(size: 20)

    // Body — serif regular. Everything the reader actually reads.

    /// Form values and primary record text.
    static let bodyLarge = SepiaTheme.body(size: 15)
    /// Default reading size: list rows, record fields, descriptions.
    static let body = SepiaTheme.body(size: 13)

    // UI — serif medium. Controls and labels, not prose.

    /// Button and control labels.
    static let control = SepiaTheme.ui(size: 12)
    /// Small tracked caps: field labels, section headers, badges.
    static let label = SepiaTheme.ui(size: 11)
    /// The smallest legible step: legends, timestamps, card metadata.
    static let micro = SepiaTheme.ui(size: 10)

    /// Letter-spacing for small caps labels, as a fraction of the font size. The
    /// app had eight different tracking values for the same visual role; this is
    /// the one `SepiaTrackedLabel` already applies.
    static let trackingRatio: CGFloat = 0.2

    /// Tracking for a tracked-caps label at `size`.
    static func tracking(_ size: CGFloat) -> CGFloat {
        size * trackingRatio
    }
}
