import SwiftUI

struct FanChartView: View {
    let tree: FamilyTree
    let zoom: CGFloat
    @Binding var selectedPerson: Person?
    
    private let maxGen = 5
    private let rootR: CGFloat = 78
    private let ringW: CGFloat = 92
    private let sweep: Double = 180
    
    var body: some View {
        GeometryReader { _ in
            let layout = computeFan()
            
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    // Wedges
                    ForEach(layout.wedges) { wedge in
                        FanWedgeShape(wedge: wedge, cx: layout.cx, cy: layout.cy, isSelected: selectedPerson?.id == wedge.personId, isHome: tree.homePersonId == wedge.personId)
                            .onTapGesture {
                                if let pid = wedge.personId, let p = tree.person(byId: pid) {
                                    withAnimation(.easeInOut(duration: 0.15)) { selectedPerson = p }
                                }
                            }
                    }
                }
                .frame(width: layout.width, height: layout.height)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: layout.width * zoom, height: layout.height * zoom)
            }
        }
    }
    
    private func computeFan() -> FanData {
        let idx = FamilyIndex(tree: tree)
        var wedges: [Wedge] = []
        
        // Upper half: home person's ancestors (180° sweep, angles 0..180)
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
        
        // Lower half: spouse's ancestors (180° sweep, angles 180..360)
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
        let totalH = hasSpouse ? 2 * outerR + 160 : outerR + 120
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
                    Text(person.givenNames).font(SepiaTheme.display(size: 12)).fontWeight(.semibold)
                    Text(person.surname).font(SepiaTheme.display(size: 12))
                    if !person.lifespan.isEmpty {
                        Text(person.lifespan).font(SepiaTheme.body(size: 9)).foregroundColor(SepiaTheme.inkSoft)
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
                    Text(person.givenNames).font(SepiaTheme.display(size: 12)).fontWeight(.semibold)
                    Text(person.surname).font(SepiaTheme.display(size: 12))
                    if !person.lifespan.isEmpty {
                        Text(person.lifespan).font(SepiaTheme.body(size: 9)).foregroundColor(SepiaTheme.inkSoft)
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
                
                Text("\(person.surname) \(person.yearFrom)")
                    .font(SepiaTheme.ui(size: max(8, 11 - CGFloat(wedge.gen))))
                    .foregroundColor(SepiaTheme.ink)
                    .rotationEffect(textAngle(midA))
                    .position(x: tx, y: ty)
                    .lineLimit(1)
            }
        }
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

// Helper
extension Person {
    var yearFrom: String {
        guard let d = birthDate, let range = d.range(of: #"\b\d{4}\b"#, options: .regularExpression) else { return "" }
        return String(d[range])
    }
}
