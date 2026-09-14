import Foundation

/// How large the interface chrome is drawn — panels, forms, lists, sheets and the
/// toolbar. Five steps either side of 100%.
///
/// This is the app's own scale, not the system's. `SepiaType` is a fixed-point scale
/// precisely because the canvas, fan chart and PDF share hand-tuned metrics with the
/// screens, so Dynamic Type stays unadopted; this multiplier applies to chrome only
/// and deliberately never reaches the canvas or the export.
///
/// `factor` is `Double` rather than `CGFloat`: SwarmCore is Foundation-only, and the
/// view layer converts once when it writes `SepiaTheme.scale`.
public enum UIScale: String, CaseIterable, Identifiable, Sendable {
    case small
    case compact
    case standard
    case large
    case extraLarge

    public static let storageKey = "uiScale"

    /// Used as the `@AppStorage` default everywhere the scale is read.
    public static let `default` = UIScale.standard

    public var id: String { rawValue }

    public var factor: Double {
        switch self {
        case .small: 0.85
        case .compact: 0.92
        case .standard: 1.0
        case .large: 1.15
        case .extraLarge: 1.30
        }
    }

    /// How a step names itself. The percentage is the whole label: the section header
    /// says what is being sized, and a word for each step ("Мелкий", "Очень крупный")
    /// only truncates in a five-wide row.
    public var summary: String {
        "\(Int((factor * 100).rounded()))%"
    }

    public static var current: UIScale { current(in: .standard) }

    /// Injectable form, so the fallback behaviour is testable without touching the
    /// standard defaults the running app uses.
    public static func current(in defaults: UserDefaults) -> UIScale {
        guard let rawValue = defaults.string(forKey: storageKey) else { return .default }
        return UIScale(rawValue: rawValue) ?? .default
    }
}
