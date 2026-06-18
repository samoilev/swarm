import AppKit
import FamilyTreeCore
import SwiftUI

@main
struct FamilyTreeStudioApp: App {
    @State private var store = TreeStore()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(.light)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first {
                        window.makeKeyAndOrderFront(nil)
                        window.backgroundColor = NSColor(red: 0.91, green: 0.88, blue: 0.77, alpha: 1.0) // matches SepiaTheme.toolbarBg
                        window.titlebarAppearsTransparent = true
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новое дерево") {
                    NotificationCenter.default.post(name: .newTreeRequested, object: nil)
                }
                .keyboardShortcut("n")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Отменить") {
                    NotificationCenter.default.post(name: .undoRequested, object: nil)
                }
                .keyboardShortcut("z")
                Button("Повторить") {
                    NotificationCenter.default.post(name: .redoRequested, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Найти персону") {
                    NotificationCenter.default.post(name: .findPersonRequested, object: nil)
                }
                .keyboardShortcut("f")
            }
            CommandGroup(after: .toolbar) {
                Button("Увеличить масштаб") {
                    NotificationCenter.default.post(name: .zoomInRequested, object: nil)
                }
                .keyboardShortcut("+")
                Button("Уменьшить масштаб") {
                    NotificationCenter.default.post(name: .zoomOutRequested, object: nil)
                }
                .keyboardShortcut("-")
                Button("По размеру экрана") {
                    NotificationCenter.default.post(name: .zoomFitRequested, object: nil)
                }
                .keyboardShortcut("0")
            }
        }
    }
}

extension Notification.Name {
    static let newTreeRequested = Notification.Name("newTreeRequested")
    static let zoomInRequested = Notification.Name("zoomInRequested")
    static let zoomOutRequested = Notification.Name("zoomOutRequested")
    static let zoomFitRequested = Notification.Name("zoomFitRequested")
    static let undoRequested = Notification.Name("undoRequested")
    static let redoRequested = Notification.Name("redoRequested")
    static let findPersonRequested = Notification.Name("findPersonRequested")
}
