import SwiftUI
import AppKit

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
                    NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
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
        }
    }
}

extension Notification.Name {
    static let newTreeRequested = Notification.Name("newTreeRequested")
}
