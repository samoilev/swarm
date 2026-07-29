import Foundation

/// Language-neutral relationship semantics. Calculators return this value; presentation
/// layers choose Russian or English through `KinshipFormatter`.
public enum KinshipDescriptor: Hashable, Sendable {
    public enum SiblingKind: Hashable, Sendable {
        case full
        case paternalHalf
        case maternalHalf
        case halfUnknown
    }

    public enum CousinDirection: Hashable, Sendable {
        case sameGeneration
        case younger
        case older
    }

    public enum InLawKind: Hashable, Sendable {
        case fatherHusbandsSide
        case fatherWifesSide
        case motherHusbandsSide
        case motherWifesSide
        case brotherHusbandsSide
        case brotherWifesSide
        case sisterHusbandsSide
        case sisterWifesSide
        case brothersWife
        case sistersHusband
        case sonsWife
        case daughtersHusband
    }

    case samePerson
    case spouse(sex: Person.Sex)
    case parent(sex: Person.Sex, kind: ParentageKind)
    case child(sex: Person.Sex, kind: ParentageKind)
    case stepParent(sex: Person.Sex)
    case sibling(sex: Person.Sex, kind: SiblingKind)
    case ancestor(generation: Int, sex: Person.Sex)
    case descendant(generation: Int, sex: Person.Sex)
    case spouseOfDescendant(generation: Int, spouseSex: Person.Sex, descendantSex: Person.Sex)
    case auntOrUncle(greats: Int, sex: Person.Sex)
    case nieceOrNephew(greats: Int, sex: Person.Sex)
    case cousin(degree: Int, removed: Int, direction: CousinDirection, sex: Person.Sex)
    case inLaw(InLawKind)
    indirect case qualified(base: KinshipDescriptor, kind: ParentageKind)
    case relative
    case distantRelative
    case unconnected
}

public struct KinshipFormatter: Sendable {
    public enum Style: Sendable {
        case relationship
        case lineage
    }

    public let language: AppLanguage
    public let style: Style

    public init(language: AppLanguage = .current, style: Style = .relationship) {
        self.language = language
        self.style = style
    }

    public func label(for descriptor: KinshipDescriptor) -> String {
        switch language {
        case .russian:
            russianLabel(for: descriptor)
        case .english:
            englishLabel(for: descriptor)
        }
    }

    private func englishLabel(for descriptor: KinshipDescriptor) -> String {
        switch descriptor {
        case .samePerson:
            "Same Person"
        case let .spouse(sex):
            gendered(sex, male: "Husband", female: "Wife", neutral: "Spouse")
        case let .parent(sex, kind):
            englishParent(sex: sex, kind: kind)
        case let .child(sex, kind):
            englishChild(sex: sex, kind: kind)
        case let .stepParent(sex):
            gendered(sex, male: "Stepfather", female: "Stepmother", neutral: "Step-parent")
        case let .sibling(sex, kind):
            englishSibling(sex: sex, kind: kind)
        case let .ancestor(generation, sex):
            englishAncestor(generation: generation, sex: sex)
        case let .descendant(generation, sex):
            englishDescendant(generation: generation, sex: sex)
        case let .spouseOfDescendant(generation, spouseSex, descendantSex):
            englishSpouseOfDescendant(
                generation: generation,
                spouseSex: spouseSex,
                descendantSex: descendantSex
            )
        case let .auntOrUncle(greats, sex):
            englishAuntOrUncle(greats: greats, sex: sex)
        case let .nieceOrNephew(greats, sex):
            englishNieceOrNephew(greats: greats, sex: sex)
        case let .cousin(degree, removed, _, _):
            englishCousin(degree: degree, removed: removed)
        case let .inLaw(kind):
            englishInLaw(kind)
        case let .qualified(base, kind):
            qualifiedLabel(englishLabel(for: base), kind: kind, language: .english)
        case .relative:
            "Relative"
        case .distantRelative:
            "Distant Relative"
        case .unconnected:
            "No Relationship Found"
        }
    }

    private func russianLabel(for descriptor: KinshipDescriptor) -> String {
        switch descriptor {
        case .samePerson:
            "Это тот же человек"
        case let .spouse(sex):
            gendered(sex, male: "Муж", female: "Жена", neutral: "Супруг/супруга")
        case let .parent(sex, kind):
            russianParent(sex: sex, kind: kind)
        case let .child(sex, kind):
            russianChild(sex: sex, kind: kind)
        case let .stepParent(sex):
            gendered(sex, male: "Отчим", female: "Мачеха", neutral: "Неродной родитель")
        case let .sibling(sex, kind):
            russianSibling(sex: sex, kind: kind)
        case let .ancestor(generation, sex):
            russianAncestor(generation: generation, sex: sex)
        case let .descendant(generation, sex):
            russianDescendant(generation: generation, sex: sex)
        case let .spouseOfDescendant(generation, spouseSex, descendantSex):
            russianSpouseOfDescendant(
                generation: generation,
                spouseSex: spouseSex,
                descendantSex: descendantSex
            )
        case let .auntOrUncle(greats, sex):
            russianAuntOrUncle(greats: greats, sex: sex)
        case let .nieceOrNephew(greats, sex):
            russianNieceOrNephew(greats: greats, sex: sex)
        case let .cousin(degree, removed, direction, sex):
            russianCousin(degree: degree, removed: removed, direction: direction, sex: sex)
        case let .inLaw(kind):
            russianInLaw(kind)
        case let .qualified(base, kind):
            qualifiedLabel(russianLabel(for: base), kind: kind, language: .russian)
        case .relative:
            "Родственник"
        case .distantRelative:
            "Дальний родственник"
        case .unconnected:
            "Связь не найдена"
        }
    }

    private func englishParent(sex: Person.Sex, kind: ParentageKind) -> String {
        switch kind {
        case .biological:
            gendered(sex, male: "Father", female: "Mother", neutral: "Parent")
        case .adoptive:
            gendered(sex, male: "Adoptive Father", female: "Adoptive Mother", neutral: "Adoptive Parent")
        case .foster:
            gendered(sex, male: "Foster Father", female: "Foster Mother", neutral: "Foster Parent")
        case .step:
            gendered(sex, male: "Stepfather", female: "Stepmother", neutral: "Step-parent")
        case .uncertain:
            gendered(sex, male: "Uncertain Father", female: "Uncertain Mother", neutral: "Uncertain Parent")
        }
    }

    private func russianParent(sex: Person.Sex, kind: ParentageKind) -> String {
        switch kind {
        case .biological:
            gendered(sex, male: "Отец", female: "Мать", neutral: "Родитель")
        case .adoptive:
            gendered(sex, male: "Приёмный отец", female: "Приёмная мать", neutral: "Приёмный родитель")
        case .foster:
            "Опекун"
        case .step:
            gendered(sex, male: "Отчим", female: "Мачеха", neutral: "Неродной родитель")
        case .uncertain:
            gendered(sex, male: "Предполагаемый отец", female: "Предполагаемая мать", neutral: "Предполагаемый родитель")
        }
    }

    private func englishChild(sex: Person.Sex, kind: ParentageKind) -> String {
        switch kind {
        case .biological:
            gendered(sex, male: "Son", female: "Daughter", neutral: "Child")
        case .adoptive:
            gendered(sex, male: "Adoptive Son", female: "Adoptive Daughter", neutral: "Adoptive Child")
        case .foster:
            "Foster Child"
        case .step:
            gendered(sex, male: "Stepson", female: "Stepdaughter", neutral: "Stepchild")
        case .uncertain:
            gendered(sex, male: "Uncertain Son", female: "Uncertain Daughter", neutral: "Uncertain Child")
        }
    }

    private func russianChild(sex: Person.Sex, kind: ParentageKind) -> String {
        switch kind {
        case .biological:
            gendered(sex, male: "Сын", female: "Дочь", neutral: "Ребёнок")
        case .adoptive:
            gendered(sex, male: "Приёмный сын", female: "Приёмная дочь", neutral: "Приёмный ребёнок")
        case .foster:
            "Ребёнок под опекой"
        case .step:
            gendered(sex, male: "Пасынок", female: "Падчерица", neutral: "Неродной ребёнок")
        case .uncertain:
            gendered(sex, male: "Предполагаемый сын", female: "Предполагаемая дочь", neutral: "Предполагаемый ребёнок")
        }
    }

    private func englishSibling(sex: Person.Sex, kind: KinshipDescriptor.SiblingKind) -> String {
        let base = gendered(sex, male: "Brother", female: "Sister", neutral: "Sibling")
        switch kind {
        case .full:
            return base
        case .paternalHalf:
            return "Paternal Half-\(base.lowercased())"
        case .maternalHalf:
            return "Maternal Half-\(base.lowercased())"
        case .halfUnknown:
            return "Half-\(base.lowercased())"
        }
    }

    private func russianSibling(sex: Person.Sex, kind: KinshipDescriptor.SiblingKind) -> String {
        switch kind {
        case .full:
            gendered(sex, male: "Брат", female: "Сестра", neutral: "Брат/сестра")
        case .paternalHalf:
            gendered(sex, male: "Единокровный брат", female: "Единокровная сестра", neutral: "Неполнородный брат/сестра")
        case .maternalHalf:
            gendered(sex, male: "Единоутробный брат", female: "Единоутробная сестра", neutral: "Неполнородный брат/сестра")
        case .halfUnknown:
            "Неполнородный брат/сестра"
        }
    }

    private func englishAncestor(generation: Int, sex: Person.Sex) -> String {
        switch generation {
        case 1:
            gendered(sex, male: "Father", female: "Mother", neutral: "Parent")
        case 2:
            gendered(sex, male: "Grandfather", female: "Grandmother", neutral: "Grandparent")
        default:
            String(repeating: "Great-", count: max(1, generation - 2))
                + gendered(sex, male: "grandfather", female: "grandmother", neutral: "grandparent")
        }
    }

    private func russianAncestor(generation: Int, sex: Person.Sex) -> String {
        switch generation {
        case 1:
            gendered(sex, male: "Отец", female: "Мать", neutral: "Родитель")
        case 2:
            gendered(
                sex,
                male: style == .lineage ? "Дедушка" : "Дед",
                female: "Бабушка",
                neutral: "Родитель родителя"
            )
        case 3:
            gendered(
                sex,
                male: style == .lineage ? "Прадедушка" : "Прадед",
                female: "Прабабушка",
                neutral: "Прародитель"
            )
        case 4:
            gendered(
                sex,
                male: style == .lineage ? "Прапрадедушка" : "Прапрадед",
                female: "Прапрабабушка",
                neutral: "Пра-прародитель"
            )
        default:
            "\(generation)-й предок"
        }
    }

    private func englishDescendant(generation: Int, sex: Person.Sex) -> String {
        switch generation {
        case 1:
            gendered(sex, male: "Son", female: "Daughter", neutral: "Child")
        case 2:
            gendered(sex, male: "Grandson", female: "Granddaughter", neutral: "Grandchild")
        default:
            String(repeating: "Great-", count: max(1, generation - 2))
                + gendered(sex, male: "grandson", female: "granddaughter", neutral: "grandchild")
        }
    }

    private func russianDescendant(generation: Int, sex: Person.Sex) -> String {
        switch generation {
        case 1:
            gendered(sex, male: "Сын", female: "Дочь", neutral: "Ребёнок")
        case 2:
            gendered(sex, male: "Внук", female: "Внучка", neutral: "Внук/внучка")
        case 3:
            gendered(sex, male: "Правнук", female: "Правнучка", neutral: "Правнук/правнучка")
        case 4:
            gendered(sex, male: "Праправнук", female: "Праправнучка", neutral: "Праправнук/праправнучка")
        default:
            "\(generation)-й потомок"
        }
    }

    private func englishSpouseOfDescendant(
        generation: Int,
        spouseSex: Person.Sex,
        descendantSex: Person.Sex
    ) -> String {
        if generation == 1 {
            return gendered(
                spouseSex,
                male: "Son-in-law",
                female: "Daughter-in-law",
                neutral: "Child-in-law"
            )
        }
        let descendant = englishDescendant(generation: generation, sex: descendantSex).lowercased()
        return gendered(
            spouseSex,
            male: "Husband of \(descendant)",
            female: "Wife of \(descendant)",
            neutral: "Spouse of \(descendant)"
        )
    }

    private func russianSpouseOfDescendant(
        generation: Int,
        spouseSex: Person.Sex,
        descendantSex: Person.Sex
    ) -> String {
        if generation == 1 {
            return gendered(spouseSex, male: "Зять", female: "Невестка", neutral: "Супруг(а) ребёнка")
        }
        let descendant = russianDescendantGenitive(generation: generation, sex: descendantSex)
        return gendered(
            spouseSex,
            male: "Муж \(descendant)",
            female: "Жена \(descendant)",
            neutral: "Супруг(а) \(descendant)"
        )
    }

    private func russianDescendantGenitive(generation: Int, sex: Person.Sex) -> String {
        let female = sex == .female
        switch generation {
        case 1: return female ? "дочери" : sex == .male ? "сына" : "ребёнка"
        case 2: return female ? "внучки" : sex == .male ? "внука" : "внука/внучки"
        case 3: return female ? "правнучки" : sex == .male ? "правнука" : "правнука/правнучки"
        case 4: return female ? "праправнучки" : sex == .male ? "праправнука" : "праправнука/праправнучки"
        default:
            let prefix = String(repeating: "пра", count: max(1, generation - 1))
            return female ? "\(prefix)внучки" : sex == .male ? "\(prefix)внука" : "\(prefix)внука/внучки"
        }
    }

    private func englishAuntOrUncle(greats: Int, sex: Person.Sex) -> String {
        let prefix = greats == 0 ? "" : String(repeating: "Great-", count: greats)
        return prefix + gendered(sex, male: "uncle", female: "aunt", neutral: "aunt or uncle")
            .capitalizingFirstLetter
    }

    private func russianAuntOrUncle(greats: Int, sex: Person.Sex) -> String {
        switch greats {
        case 0:
            gendered(sex, male: "Дядя", female: "Тётя", neutral: "Дядя/тётя")
        case 1:
            gendered(sex, male: "Двоюродный дед", female: "Двоюродная бабушка", neutral: "Двоюродный прародитель")
        default:
            "\(greats + 1)-юродный предок боковой линии"
        }
    }

    private func englishNieceOrNephew(greats: Int, sex: Person.Sex) -> String {
        let prefix = greats == 0 ? "" : String(repeating: "Great-", count: greats)
        return prefix + gendered(sex, male: "nephew", female: "niece", neutral: "niece or nephew")
            .capitalizingFirstLetter
    }

    private func russianNieceOrNephew(greats: Int, sex: Person.Sex) -> String {
        switch greats {
        case 0:
            gendered(sex, male: "Племянник", female: "Племянница", neutral: "Племянник/племянница")
        case 1:
            gendered(sex, male: "Внучатый племянник", female: "Внучатая племянница", neutral: "Внучатый племянник/племянница")
        default:
            "\(greats + 1)-юродный потомок боковой линии"
        }
    }

    private func englishCousin(degree: Int, removed: Int) -> String {
        let ordinal = switch max(1, degree) {
        case 1: "First"
        case 2: "Second"
        case 3: "Third"
        case 4: "Fourth"
        default: Self.englishOrdinal(max(1, degree))
        }
        let base = "\(ordinal) Cousin"
        guard removed > 0 else { return base }
        let removal = switch removed {
        case 1: "Once"
        case 2: "Twice"
        case 3: "Three Times"
        default: "\(removed) Times"
        }
        return "\(base) \(removal) Removed"
    }

    private func russianCousin(
        degree: Int,
        removed: Int,
        direction: KinshipDescriptor.CousinDirection,
        sex: Person.Sex
    ) -> String {
        let adjective = russianCousinAdjective(degree: degree, sex: sex)
        if removed == 0 {
            let noun = gendered(sex, male: "брат", female: "сестра", neutral: "брат/сестра")
            return "\(adjective) \(noun)".capitalizingFirstLetter
        }
        if removed == 1 {
            let noun = switch direction {
            case .younger:
                gendered(sex, male: "племянник", female: "племянница", neutral: "племянник/племянница")
            case .older:
                gendered(sex, male: "дядя", female: "тётя", neutral: "дядя/тётя")
            case .sameGeneration:
                gendered(sex, male: "родственник", female: "родственница", neutral: "родственник")
            }
            return "\(adjective) \(noun)".capitalizingFirstLetter
        }
        let directionText = direction == .younger ? "младше" : "старше"
        return "\(adjective.capitalizingFirstLetter) родственник (\(directionText) на \(removed) поколения)"
    }

    private func russianCousinAdjective(degree: Int, sex: Person.Sex) -> String {
        switch degree {
        case 1:
            gendered(sex, male: "двоюродный", female: "двоюродная", neutral: "двоюродный/двоюродная")
        case 2:
            gendered(sex, male: "троюродный", female: "троюродная", neutral: "троюродный/троюродная")
        case 3:
            gendered(sex, male: "четвероюродный", female: "четвероюродная", neutral: "четвероюродный/четвероюродная")
        default:
            "\(degree + 1)-юродный"
        }
    }

    private func englishInLaw(_ kind: KinshipDescriptor.InLawKind) -> String {
        switch kind {
        case .fatherHusbandsSide, .fatherWifesSide:
            "Father-in-law"
        case .motherHusbandsSide, .motherWifesSide:
            "Mother-in-law"
        case .brotherHusbandsSide, .brotherWifesSide, .sistersHusband:
            "Brother-in-law"
        case .sisterHusbandsSide, .sisterWifesSide, .brothersWife:
            "Sister-in-law"
        case .sonsWife:
            "Daughter-in-law"
        case .daughtersHusband:
            "Son-in-law"
        }
    }

    private func russianInLaw(_ kind: KinshipDescriptor.InLawKind) -> String {
        switch kind {
        case .fatherHusbandsSide: "Свёкор"
        case .fatherWifesSide: "Тесть"
        case .motherHusbandsSide: "Свекровь"
        case .motherWifesSide: "Тёща"
        case .brotherHusbandsSide: "Деверь"
        case .brotherWifesSide: "Шурин"
        case .sisterHusbandsSide: "Золовка"
        case .sisterWifesSide: "Свояченица"
        case .brothersWife: "Невестка (жена брата)"
        case .sistersHusband: "Зять (муж сестры)"
        case .sonsWife: "Невестка (сноха)"
        case .daughtersHusband: "Зять (муж дочери)"
        }
    }

    private func qualifiedLabel(
        _ base: String,
        kind: ParentageKind,
        language: AppLanguage
    ) -> String {
        guard kind != .biological else { return base }
        switch language {
        case .english:
            let suffix = switch kind {
            case .biological: ""
            case .adoptive: "through adoption"
            case .foster: "through foster care"
            case .step: "through a step-family connection"
            case .uncertain: "through uncertain parentage"
            }
            return "\(base) \(suffix)"
        case .russian:
            let suffix = switch kind {
            case .biological: ""
            case .adoptive: "по приёмной линии"
            case .foster: "по опекунской линии"
            case .step: "по неродной линии"
            case .uncertain: "по предполагаемой линии"
            }
            return "\(base) \(suffix)"
        }
    }

    private func gendered(_ sex: Person.Sex, male: String, female: String, neutral: String) -> String {
        switch sex {
        case .male: male
        case .female: female
        case .unknown: neutral
        }
    }

    private static func englishOrdinal(_ value: Int) -> String {
        let remainder100 = value % 100
        let suffix = if (11 ... 13).contains(remainder100) {
            "th"
        } else {
            switch value % 10 {
            case 1: "st"
            case 2: "nd"
            case 3: "rd"
            default: "th"
            }
        }
        return "\(value)\(suffix)"
    }
}

private extension String {
    var capitalizingFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
