import Foundation

public enum MapProviderSetting: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleMaps
    case offlineVector

    /// Used as the `@AppStorage` default everywhere the provider is read.
    public static let `default` = MapProviderSetting.appleMaps

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleMaps: "Apple Maps"
        case .offlineVector: L10n.tr("Офлайн-карта")
        }
    }

    public var summary: String {
        switch self {
        case .appleMaps: L10n.tr("Подробная. Нужна сеть.")
        case .offlineVector: L10n.tr("Контуры стран. Без сети.")
        }
    }
}
