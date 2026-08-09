import AppKit
import SwiftUI

/// A sepia icon button that fires `action` once on a tap and then keeps firing
/// while held (press-and-hold auto-repeat), like a native Stepper — but keeping
/// the custom SepiaIconButtonStyle look. Used for zoom and fan-level +/-.
struct RepeatButton<Label: View>: View {
    var chrome: RepeatButtonChrome = .sepia
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: {}) { label() }
            .buttonStyle(RepeatIconButtonStyle(chrome: chrome, action: action))
    }
}

enum RepeatButtonChrome: Equatable {
    case sepia
    case toolbar
}

private struct RepeatIconButtonStyle: ButtonStyle {
    let chrome: RepeatButtonChrome
    let action: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        RepeatBody(configuration: configuration, chrome: chrome, action: action)
    }

    private struct RepeatBody: View {
        let configuration: ButtonStyleConfiguration
        let chrome: RepeatButtonChrome
        let action: () -> Void
        @State private var timer: Timer?
        @State private var delay: DispatchWorkItem?
        @State private var mouseUpMonitor: Any?

        var body: some View {
            sized
                .onChange(of: configuration.isPressed) { _, pressed in
                    if pressed { start() } else { stop() }
                }
                .onDisappear { stop() }
        }

        @ViewBuilder private var sized: some View {
            switch chrome {
            case .toolbar:
                // In the toolbar these steppers stand beside plain icon buttons, so they
                // answer the pointer the same way: one hover/press disc, no border.
                configuration.label
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SepiaTheme.ink)
                    .modifier(WorkspaceToolbarIconChrome(isPressed: configuration.isPressed))
            case .sepia:
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
                    .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
                    .sepiaMotion(SepiaMotion.press, value: configuration.isPressed)
            }
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
