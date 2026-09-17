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
/// The numbers below are the unscaled points. Dynamic Type is still not adopted —
/// the canvas, fan chart and PDF share these metrics with hand-tuned card geometry —
/// but every step passes through `SepiaTheme`, which multiplies it by the reader's
/// `UIScale` setting. They are computed rather than stored for that reason: a `let`
/// would freeze whatever the scale was at first access.
enum SepiaType {
    // Display — serif semibold. Titles that name a screen or a sheet.

    /// Sheet and panel titles ("Экспорт", "Слияние").
    static var display: Font { SepiaTheme.display(size: 22) }
    /// Section titles inside a panel, and the inspector's person name.
    static var title: Font { SepiaTheme.display(size: 20) }

    // Body — serif regular. Everything the reader actually reads.

    /// Form values and primary record text.
    static var bodyLarge: Font { SepiaTheme.body(size: 15) }
    /// Default reading size: list rows, record fields, descriptions.
    static var body: Font { SepiaTheme.body(size: 13) }

    // UI — serif medium. Controls and labels, not prose.

    /// Button and control labels.
    static var control: Font { SepiaTheme.ui(size: 12) }
    /// Section headings inside a record ("Основные сведения", "Рождение"). One step above a
    /// field label so a group reads as a group rather than as another caption.
    static var sectionLabel: Font { SepiaTheme.ui(size: 13) }
    /// Small tracked caps: field labels, badges.
    static var label: Font { SepiaTheme.ui(size: 11) }
    /// The smallest legible step: legends, timestamps, card metadata.
    static var micro: Font { SepiaTheme.ui(size: 10) }

    /// Letter-spacing for small caps labels, as a fraction of the font size.
    ///
    /// The app had eight tracking values for one visual role. This is the ratio the
    /// screens actually use (9.5pt with 1.0, 10pt with 1.0, 11pt with 1.1); the
    /// 0.2 that `SepiaTrackedLabel` applied was the outlier, not the rule.
    static let trackingRatio: CGFloat = 0.1

    /// Tracking for a tracked-caps label at `size`, where `size` is the unscaled point
    /// value the call site passes to `SepiaTheme.ui`. Scaled to match, or the letter
    /// spacing on a tracked label would stay put while the glyphs around it grew.
    /// Only chrome uses this — the canvas tracks its labels with literals.
    static func tracking(_ size: CGFloat) -> CGFloat {
        SepiaTheme.scaled(size) * trackingRatio
    }
}
