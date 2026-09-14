import Foundation
@testable import SwarmCore
import Testing

struct UIScaleTests {
    @Test func stepsAscendAroundAnUnscaledStandard() {
        let factors = UIScale.allCases.map(\.factor)
        #expect(factors == factors.sorted())
        #expect(Set(factors).count == factors.count)
        #expect(UIScale.standard.factor == 1.0)
        #expect(UIScale.default == .standard)
        // The canvas, the export and the hand-tuned card metrics all assume the
        // unscaled case is exactly 1.0 — a 0.99 here silently resizes every screen.
        #expect(factors.first == 0.85)
        #expect(factors.last == 1.30)
    }

    @Test func summaryMatchesTheFactorItDescribes() {
        for scale in UIScale.allCases {
            #expect(scale.summary == "\(Int((scale.factor * 100).rounded()))%")
        }
        #expect(UIScale.standard.summary == "100%")
        #expect(UIScale.compact.summary == "92%")
    }

    @Test func rawValuesRoundTrip() {
        for scale in UIScale.allCases {
            #expect(UIScale(rawValue: scale.rawValue) == scale)
        }
    }

    @Test func absentOrUnreadablePreferenceFallsBackToStandard() throws {
        let suiteName = "swarm-scale-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        #expect(UIScale.current(in: defaults) == .default)

        defaults.set("gigantic", forKey: UIScale.storageKey)
        #expect(UIScale.current(in: defaults) == .default)

        defaults.set(UIScale.large.rawValue, forKey: UIScale.storageKey)
        #expect(UIScale.current(in: defaults) == .large)
    }

    @Test func sectionTitleIsBilingual() {
        #expect(L10n.tr("Размер интерфейса", language: .english) == "Interface size")
        #expect(L10n.tr("Размер интерфейса", language: .russian) == "Размер интерфейса")
    }
}
