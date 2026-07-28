import AppKit
import SwiftUI

/// A sepia icon button that fires `action` once on a tap and then keeps firing
/// while held (press-and-hold auto-repeat), like a native Stepper — but keeping
/// the custom SepiaIconButtonStyle look. Used for zoom and fan-level +/-.
struct RepeatButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: {}) { label() }
            .buttonStyle(RepeatIconButtonStyle(action: action))
    }
}

private struct RepeatIconButtonStyle: ButtonStyle {
    let action: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        RepeatBody(configuration: configuration, action: action)
    }

    private struct RepeatBody: View {
        let configuration: ButtonStyleConfiguration
        let action: () -> Void
        @State private var timer: Timer?
        @State private var delay: DispatchWorkItem?
        @State private var mouseUpMonitor: Any?

        var body: some View {
            configuration.label
                .frame(width: 30, height: 30)
                .foregroundColor(SepiaTheme.ink)
                .background(SepiaTheme.btnBg)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .opacity(configuration.isPressed ? 0.8 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
                .sepiaMotion(SepiaMotion.press, value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in
                    if pressed { start() } else { stop() }
                }
                .onDisappear { stop() }
        }

        private func start() {
            guard timer == nil, delay == nil else { return }
            action() // immediate single step (covers a plain tap)
            // Safety net: if the button gets disabled mid-press (e.g. a value hits
            // its clamp) the `isPressed` falling edge may not fire — a global
            // mouse-up monitor guarantees we always stop.
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
                stop()
                return event
            }
            let task = DispatchWorkItem {
                let t = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in action() }
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
            delay = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
        }

        private func stop() {
            delay?.cancel(); delay = nil
            timer?.invalidate(); timer = nil
            if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
        }
    }
}
