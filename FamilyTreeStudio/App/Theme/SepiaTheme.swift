import SwiftUI

struct SepiaTheme {
    /// Portrait photo aspect ratio (width ÷ height), used consistently for the photo
    /// in tree nodes, the inspector, the editor, and the upload crop selector.
    static let portraitAspect: CGFloat = 3.0 / 4.0

    // Core colors
    static let paper = Color(hex: "ece1c9")
    static let ink = Color(hex: "3a2c1a")
    static let inkSoft = Color(hex: "917c59")
    static let line = Color(hex: "b39c70")
    static let cardBg = Color(hex: "f8f1df")
    static let cardBgMale = Color(hex: "eaf2f0")
    static let cardBgFemale = Color(hex: "f5ece4")
    static let cardLine = Color(hex: "c7b389")
    static let cardLineMale = Color(hex: "8fb0a8")
    static let cardLineFemale = Color(hex: "c49a82")
    static let cardRule = Color(hex: "d9c9a4")
    static let accent = Color(hex: "9c4a2f")
    static let accent2 = Color(hex: "8a6d2f")
    static let photoA = Color(hex: "e7dcc2")
    static let photoB = Color(hex: "dccdab")
    static let toolbarBg = Color(hex: "e8ddc4")
    static let toolbarLine = Color(hex: "cdb98f")
    static let panelBg = Color(hex: "f1e8d4")
    static let btnBg = Color(hex: "f4edda")
    static let fieldLine = Color(hex: "d2c09a")
    static let fanA = Color(hex: "f4edd9")
    static let fanB = Color(hex: "ebdfc2")
    static let fanEmpty = Color(hex: "e4d8bf")
    static let fanSel = Color(hex: "edcfa8")
    static let fanLine = Color(hex: "c7b389")
    static let posterBg = Color(hex: "f4ecd6")
    
    // Map view colors
    static let mapSea = Color(hex: "dde8e4")
    static let mapLand = Color(hex: "f2ead7")
    static let mapBorder = Color(hex: "b8a880")
    static let mapGrid = Color(hex: "c8bea0").opacity(0.4)
    static let mapLine = Color(hex: "8a6d2f").opacity(0.7)
    static let pinBirth = Color(hex: "4a8c6e")
    static let pinDeath = Color(hex: "9c4a2f")
    
    static func display(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    
    static func body(size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }
    
    static func ui(size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct SepiaButtonStyle: ButtonStyle {
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SepiaTheme.ui(size: 12))
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundColor(isActive ? .white : SepiaTheme.ink)
            .background(isActive ? SepiaTheme.accent : SepiaTheme.btnBg)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isActive ? SepiaTheme.accent : SepiaTheme.cardLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SepiaIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 30)
            .foregroundColor(SepiaTheme.ink)
            .background(SepiaTheme.btnBg)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(SepiaTheme.cardLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
