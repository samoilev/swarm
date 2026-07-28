import SwarmCore
import SwiftUI

struct FanChartView: View {
    let tree: FamilyTree
    @Binding var zoom: CGFloat
    @Binding var selectedPerson: Person?
    @Binding var fitRequest: Int
    @Binding var maxGen: Int
    private let rootR: CGFloat = 78
    private let ringW: CGFloat = 92
    private let sweep: Double = 180

    @State private var panOffset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var magnifyStart: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            let layout = computeFan()

            ZStack {
                // Wedges
                ForEach(layout.wedges) { wedge in
                    FanWedgeShape(wedge: wedge, cx: layout.cx, cy: layout.cy, isSelected: selectedPerson?.id == wedge.personId, isHome: tree.homePersonId == wedge.personId)
                        .onTapGesture {
                            if let pid = wedge.personId, let p = tree.person(byId: pid) {
                                withAnimation(.easeInOut(duration: 0.15)) { selectedPerson = p }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityHidden(wedge.person == nil)
                        .accessibilityLabel(wedge.person?.accessibilityDescription ?? "")
                        .accessibilityHint(L10n.tr("Выбрать персону"))
                        .accessibilityAddTraits(selectedPerson?.id == wedge.personId ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction {
                            if let pid = wedge.personId, let p = tree.person(byId: pid) { selectedPerson = p }
                        }
                }
            }
            .frame(width: layout.width, height: layout.height, alignment: .topLeading)
            .fixedSize()
            .scaleEffect(zoom, anchor: .topLeading)
            .offset(x: panOffset.width, y: panOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        panOffset = CGSize(
                            width: dragStart.width + value.translation.width,
                            height: dragStart.height + value.translation.height
                        )
                    }
                    .onEnded { _ in dragStart = panOffset }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = min(2.0, max(0.2, magnifyStart * value.magnification))
                    }
                    .onEnded { _ in magnifyStart = zoom }
            )
            .onAppear {
                magnifyStart = zoom
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    fitToScreen(viewSize: geo.size, chartWidth: layout.width, chartHeight: layout.height)
                }
            }
            .onChange(of: zoom) { _, newVal in magnifyStart = newVal }
            .onChange(of: maxGen) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    fitToScreen(viewSize: geo.size, chartWidth: layout.width, chartHeight: layout.height)
                }
            }
            .onChange(of: fitRequest) { _, _ in
                fitToScreen(viewSize: geo.size, chartWidth: layout.width, chartHeight: layout.height)
            }
            .onChange(of: geo.size) { _, newSize in
                fitToScreen(viewSize: newSize, chartWidth: layout.width, chartHeight: layout.height)
            }
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selectedPerson = nil }
            }
        }
        .clipped()
    }

    private func fitToScreen(viewSize: CGSize, chartWidth: CGFloat, chartHeight: CGFloat) {
        guard chartWidth > 0, chartHeight > 0, viewSize.width > 0, viewSize.height > 0 else { return }
        let margin: CGFloat = 20
        let scaleW = (viewSize.width - margin * 2) / chartWidth
        let scaleH = (viewSize.height - margin * 2) / chartHeight
        let newZoom = max(0.2, min(min(scaleW, scaleH), 1.6))
        let scaledW = chartWidth * newZoom
        let scaledH = chartHeight * newZoom
        let offsetX = (viewSize.width - scaledW) / 2
        let offsetY = (viewSize.height - scaledH) / 2
        withAnimation(.easeInOut(duration: 0.3)) {
            zoom = newZoom
            panOffset = CGSize(width: offsetX, height: offsetY)
            dragStart = CGSize(width: offsetX, height: offsetY)
            magnifyStart = newZoom
        }
    }

    private func computeFan() -> FanData {
        let idx = FamilyIndex(tree: tree)
        var wedges: [Wedge] = []

        /// Upper half: home person's ancestors (180° sweep, angles 0..180)
        func walkUp(_ personId: UUID?, gen: Int, slot: Int) {
            let slots = Int(pow(2.0, Double(gen)))
            let w = sweep / Double(slots)
            let aStart = 180.0 - Double(slot + 1) * w
            let aEnd = 180.0 - Double(slot) * w
            let rInner = gen == 0 ? 0 : rootR + CGFloat(gen - 1) * ringW
            let rOuter = gen == 0 ? rootR : rInner + ringW

            let person = personId.flatMap { idx.byId[$0] }
            wedges.append(Wedge(
                id: UUID(), personId: personId, person: person,
                gen: gen, slot: slot,
                aStart: aStart, aEnd: aEnd,
                rInner: rInner, rOuter: rOuter
            ))

            guard gen < maxGen else { return }
            var fatherId: UUID? = nil
            var motherId: UUID? = nil
            if let pid = personId, let p = idx.byId[pid] {
                let par = idx.parentsOf(p)
                fatherId = par.father?.id
                motherId = par.mother?.id
            }
            walkUp(fatherId, gen: gen + 1, slot: 2 * slot)
            walkUp(motherId, gen: gen + 1, slot: 2 * slot + 1)
        }

        /// Lower half: spouse's ancestors (180° sweep, angles 180..360)
        func walkDown(_ personId: UUID?, gen: Int, slot: Int) {
            let slots = Int(pow(2.0, Double(gen)))
            let w = sweep / Double(slots)
            let aStart = 180.0 + Double(slot) * w
            let aEnd = 180.0 + Double(slot + 1) * w
            let rInner = gen == 0 ? 0 : rootR + CGFloat(gen - 1) * ringW
            let rOuter = gen == 0 ? rootR : rInner + ringW

            let person = personId.flatMap { idx.byId[$0] }
            wedges.append(Wedge(
                id: UUID(), personId: personId, person: person,
                gen: gen, slot: slot,
                aStart: aStart, aEnd: aEnd,
                rInner: rInner, rOuter: rOuter
            ))

            guard gen < maxGen else { return }
            var fatherId: UUID? = nil
            var motherId: UUID? = nil
            if let pid = personId, let p = idx.byId[pid] {
                let par = idx.parentsOf(p)
                fatherId = par.father?.id
                motherId = par.mother?.id
            }
            walkDown(fatherId, gen: gen + 1, slot: 2 * slot)
            walkDown(motherId, gen: gen + 1, slot: 2 * slot + 1)
        }

        // Home person — upper half
        walkUp(tree.homePersonId, gen: 0, slot: 0)

        // Spouse — lower half
        let spouseId: UUID? = {
            guard let hid = tree.homePersonId, let homePerson = idx.byId[hid] else { return nil }
            let spouses = idx.spousesOf(homePerson)
            return spouses.first?.id
        }()

        if let sid = spouseId {
            // Start spouse from gen 1 (skip center — it's shared with home person)
            // Add a small semicircle wedge for the spouse label at gen 0 level (bottom half)
            let spousePerson = idx.byId[sid]
            wedges.append(Wedge(
                id: UUID(), personId: sid, person: spousePerson,
                gen: 0, slot: 1,
                aStart: 180.0, aEnd: 360.0,
                rInner: 0, rOuter: rootR
            ))
            // Walk spouse's ancestors starting at gen 1
            var fatherId: UUID? = nil
            var motherId: UUID? = nil
            if let sp = spousePerson {
                let par = idx.parentsOf(sp)
                fatherId = par.father?.id
                motherId = par.mother?.id
            }
            walkDown(fatherId, gen: 1, slot: 0)
            walkDown(motherId, gen: 1, slot: 1)
        }

        let outerR = rootR + CGFloat(maxGen) * ringW
        let cx = outerR + 80
        let hasSpouse = spouseId != nil
        let cy = hasSpouse ? outerR + 80 : outerR + 80
        let totalH = hasSpouse ? 2 * outerR + 160 : outerR + 160
        return FanData(wedges: wedges, cx: cx, cy: cy, width: 2 * outerR + 160, height: totalH)
    }
}

struct Wedge: Identifiable {
    let id: UUID
    let personId: UUID?
    let person: Person?
    let gen: Int
    let slot: Int
    let aStart: Double
    let aEnd: Double
    let rInner: CGFloat
    let rOuter: CGFloat
}

struct FanData {
    let wedges: [Wedge]
    let cx: CGFloat
    let cy: CGFloat
    let width: CGFloat
    let height: CGFloat
}

struct FanWedgeShape: View {
    let wedge: Wedge
    let cx: CGFloat
    let cy: CGFloat
    var isSelected: Bool = false
    var isHome: Bool = false

    var body: some View {
        if wedge.gen == 0 && wedge.slot == 0 {
            centerTopView
        } else if wedge.gen == 0 && wedge.slot == 1 {
            centerBottomView
        } else {
            wedgeView
        }
    }

    private var centerTopView: some View {
        ZStack {
            WedgePath(cx: cx, cy: cy, rInner: 0, rOuter: wedge.rOuter,
                      startAngle: .degrees(0), endAngle: .degrees(180))
                .fill(isSelected ? SepiaTheme.fanSel : SepiaTheme.fanA)
            WedgePath(cx: cx, cy: cy, rInner: 0, rOuter: wedge.rOuter,
                      startAngle: .degrees(0), endAngle: .degrees(180))
                .stroke(SepiaTheme.fanLine, lineWidth: 1)
            if let person = wedge.person {
                VStack(spacing: 2) {
                    if AppLanguage.current == .russian {
                        Text(person.displaySurname.uppercased())
                            .font(SepiaTheme.ui(size: 8.5))
                            .tracking(1.0)
                            .foregroundColor(SepiaTheme.inkSoft)
                            .lineLimit(1)
                    }
                    if let maiden = person.maidenName, !maiden.isEmpty, maiden != person.surname {
                        Text("(\(maiden))".uppercased())
                            .font(SepiaTheme.ui(size: 7.5))
                            .tracking(0.8)
                            .foregroundColor(SepiaTheme.inkSoft.opacity(0.7))
                            .lineLimit(1)
                    }
                    Text(personFullGivenName(person))
                        .font(SepiaTheme.display(size: 13))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if !person.lifespan.isEmpty {
                        Text(person.lifespan)
                            .font(SepiaTheme.body(size: 9))
                            .foregroundColor(SepiaTheme.inkSoft)
                    }
                }
                .foregroundColor(SepiaTheme.ink)
                .position(x: cx, y: cy - wedge.rOuter * 0.4)
            }
        }
    }

    private var centerBottomView: some View {
        ZStack {
            WedgePath(cx: cx, cy: cy, rInner: 0, rOuter: wedge.rOuter,
                      startAngle: .degrees(180), endAngle: .degrees(360))
                .fill(isSelected ? SepiaTheme.fanSel : SepiaTheme.fanB)
            WedgePath(cx: cx, cy: cy, rInner: 0, rOuter: wedge.rOuter,
                      startAngle: .degrees(180), endAngle: .degrees(360))
                .stroke(SepiaTheme.fanLine, lineWidth: 1)
            if let person = wedge.person {
                VStack(spacing: 2) {
                    if AppLanguage.current == .russian {
                        Text(person.displaySurname.uppercased())
                            .font(SepiaTheme.ui(size: 8.5))
                            .tracking(1.0)
                            .foregroundColor(SepiaTheme.inkSoft)
                            .lineLimit(1)
                    }
                    if let maiden = person.maidenName, !maiden.isEmpty, maiden != person.surname {
                        Text("(\(maiden))".uppercased())
                            .font(SepiaTheme.ui(size: 7.5))
                            .tracking(0.8)
                            .foregroundColor(SepiaTheme.inkSoft.opacity(0.7))
                            .lineLimit(1)
                    }
                    Text(personFullGivenName(person))
                        .font(SepiaTheme.display(size: 13))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if !person.lifespan.isEmpty {
                        Text(person.lifespan)
                            .font(SepiaTheme.body(size: 9))
                            .foregroundColor(SepiaTheme.inkSoft)
                    }
                }
                .foregroundColor(SepiaTheme.ink)
                .position(x: cx, y: cy + wedge.rOuter * 0.4)
            }
        }
    }

    private var wedgeView: some View {
        ZStack {
            WedgePath(cx: cx, cy: cy, rInner: wedge.rInner, rOuter: wedge.rOuter,
                      startAngle: .degrees(wedge.aStart), endAngle: .degrees(wedge.aEnd))
                .fill(fillColor)
            WedgePath(cx: cx, cy: cy, rInner: wedge.rInner, rOuter: wedge.rOuter,
                      startAngle: .degrees(wedge.aStart), endAngle: .degrees(wedge.aEnd))
                .stroke(SepiaTheme.fanLine, lineWidth: 0.8)

            if let person = wedge.person {
                let midA = (wedge.aStart + wedge.aEnd) / 2
                let midR = (wedge.rInner + wedge.rOuter) / 2
                let tx = cx + midR * CGFloat(cos(midA * .pi / 180))
                let ty = cy - midR * CGFloat(sin(midA * .pi / 180))

                // Available arc length determines text detail level
                let arcSpan = wedge.aEnd - wedge.aStart
                let arcLen = midR * CGFloat(arcSpan * .pi / 180)

                wedgeText(person: person, arcLen: arcLen, gen: wedge.gen)
                    .rotationEffect(textAngle(midA))
                    .position(x: tx, y: ty)
            }
        }
    }

    @ViewBuilder
    private func wedgeText(person: Person, arcLen: CGFloat, gen: Int) -> some View {
        let fontSize = max(7.5, 11 - CGFloat(gen) * 0.8)

        if arcLen > 140 {
            // Large: "Фамилия И.О." + "(девичья)" + year
            VStack(spacing: 1) {
                Text(personShortName(person))
                    .font(SepiaTheme.ui(size: fontSize))
                    .fontWeight(.medium)
                    .foregroundColor(SepiaTheme.ink)
                    .lineLimit(1)
                if let maiden = person.maidenName, !maiden.isEmpty, maiden != person.surname {
                    Text("(\(maiden))".uppercased())
                        .font(SepiaTheme.ui(size: max(6, fontSize - 1.5)))
                        .tracking(0.5)
                        .foregroundColor(SepiaTheme.inkSoft.opacity(0.7))
                        .lineLimit(1)
                }
                if !person.yearFrom.isEmpty {
                    Text(person.yearFrom)
                        .font(SepiaTheme.body(size: max(6.5, fontSize - 2)))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .lineLimit(1)
                }
            }
        } else if arcLen > 60 {
            // Medium: "Фамилия И.О." + year
            VStack(spacing: 1) {
                Text(personShortName(person))
                    .font(SepiaTheme.ui(size: max(7, fontSize - 0.5)))
                    .foregroundColor(SepiaTheme.ink)
                    .lineLimit(1)
                if !person.yearFrom.isEmpty {
                    Text(person.yearFrom)
                        .font(SepiaTheme.body(size: max(6, fontSize - 2.5)))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .lineLimit(1)
                }
            }
        } else {
            // Minimal: "Фам. И." + year
            VStack(spacing: 0) {
                Text(personMinimalName(person))
                    .font(SepiaTheme.ui(size: max(7, fontSize - 1)))
                    .foregroundColor(SepiaTheme.ink)
                    .lineLimit(1)
                if !person.yearFrom.isEmpty {
                    Text(person.yearFrom)
                        .font(SepiaTheme.body(size: max(5.5, fontSize - 3)))
                        .foregroundColor(SepiaTheme.inkSoft)
                        .lineLimit(1)
                }
            }
        }
    }

    private func personFullGivenName(_ person: Person) -> String {
        if AppLanguage.current == .english {
            return person.displayName(language: .english)
        }
        return [person.givenNames, person.patronymic ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func personShortName(_ person: Person) -> String {
        let surname = person.displaySurname
        let givenInitial = person.givenNames.first.map { "\($0)." } ?? ""
        let patronInitial = (person.patronymic ?? "").first.map { "\($0)." } ?? ""
        if AppLanguage.current == .english {
            return "\(givenInitial) \(surname)".trimmingCharacters(in: .whitespaces)
        }
        return "\(surname) \(givenInitial)\(patronInitial)".trimmingCharacters(in: .whitespaces)
    }

    private func personMinimalName(_ person: Person) -> String {
        let surname = person.displaySurname
        let initial = person.givenNames.first.map { "\($0)." } ?? ""
        if AppLanguage.current == .english {
            return "\(initial) \(surname)".trimmingCharacters(in: .whitespaces)
        }
        return "\(surname) \(initial)".trimmingCharacters(in: .whitespaces)
    }

    private var fillColor: Color {
        if isSelected { return SepiaTheme.fanSel }
        if isHome { return SepiaTheme.fanSel.opacity(0.6) }
        if wedge.person == nil { return SepiaTheme.fanEmpty }
        return wedge.gen % 2 == 0 ? SepiaTheme.fanA : SepiaTheme.fanB
    }

    private func textAngle(_ angle: Double) -> Angle {
        let a = angle.truncatingRemainder(dividingBy: 360)
        return a > 90 && a < 270 ? .degrees(-(angle - 180)) : .degrees(-angle)
    }
}

struct WedgePath: Shape {
    let cx: CGFloat, cy: CGFloat
    let rInner: CGFloat, rOuter: CGFloat
    let startAngle: Angle, endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = Angle(degrees: -startAngle.degrees)
        let end = Angle(degrees: -endAngle.degrees)

        path.addArc(center: CGPoint(x: cx, y: cy), radius: rOuter, startAngle: end, endAngle: start, clockwise: false)
        if rInner > 0 {
            path.addArc(center: CGPoint(x: cx, y: cy), radius: rInner, startAngle: start, endAngle: end, clockwise: true)
        } else {
            path.addLine(to: CGPoint(x: cx, y: cy))
        }
        path.closeSubpath()
        return path
    }
}

/// Helper
extension Person {
    var yearFrom: String {
        guard let d = birthDate, let range = d.range(of: #"\b\d{4}\b"#, options: .regularExpression) else { return "" }
        return String(d[range])
    }
}
