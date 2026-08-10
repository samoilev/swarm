import SwiftUI

extension View {
    /// Shows `text` as a hover tooltip only while the view is clipped — a tooltip that
    /// repeats a fully visible label is noise.
    func truncationTooltip(_ text: String) -> some View {
        modifier(TruncationTooltip(text: text))
    }

    /// Reports whether the view is clipped, leaving the tooltip to a caller further up.
    /// A label inside a Button cannot own its tooltip: the button takes the hover, and
    /// the help attached to the label never fires.
    func truncationProbe(_ isTruncated: Binding<Bool>) -> some View {
        modifier(TruncationProbe(isTruncated: isTruncated))
    }
}

private struct TruncationTooltip: ViewModifier {
    let text: String
    @State private var isTruncated = false

    func body(content: Content) -> some View {
        content
            .truncationProbe($isTruncated)
            // An empty string clears the tooltip rather than showing a blank one.
            .help(isTruncated ? text : "")
    }
}

/// Compares the width the view was given against the width it wants; wanting more means
/// the tail is cut off.
private struct TruncationProbe: ViewModifier {
    @Binding var isTruncated: Bool
    @State private var given: CGFloat = 0
    @State private var wanted: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background { widthReader { given = $0 } }
            .overlay {
                // The probe is a second copy of the label at its natural width. It lives
                // inside a zero-sized clipped frame on purpose: measured any other way it
                // reports a size of its own, and a toolbar then budgets room for a copy
                // nobody can see and squeezes the real label instead.
                content
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .background { widthReader { wanted = $0 } }
                    .frame(width: 0, height: 0)
                    .clipped()
                    .accessibilityHidden(true)
            }
            .onChange(of: wanted - given > 0.5, initial: true) { _, clipped in
                isTruncated = clipped
            }
    }

    private func widthReader(_ report: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in
                report(width)
            }
        }
    }
}
