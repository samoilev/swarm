import AppKit
import FamilyTreeCore
import SwiftUI

@main
struct FamilyTreeStudioApp: App {
    @State private var store: TreeStore
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let storageFolder: URL? = arguments.firstIndex(of: "--storage-folder").flatMap { index in
            guard arguments.indices.contains(index + 1) else { return nil }
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        _store = State(initialValue: TreeStore(storageFolder: storageFolder))
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
                .environment(\.locale, language.locale)
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
                Button(L10n.tr("Новое дерево")) {
                    NotificationCenter.default.post(name: .newTreeRequested, object: nil)
                }
                .keyboardShortcut("n")
            }
            CommandGroup(replacing: .undoRedo) {
                Button(L10n.tr("Отменить")) {
                    NotificationCenter.default.post(name: .undoRequested, object: nil)
                }
                .keyboardShortcut("z")
                Button(L10n.tr("Повторить")) {
                    NotificationCenter.default.post(name: .redoRequested, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button(L10n.tr("Найти персону")) {
                    NotificationCenter.default.post(name: .findPersonRequested, object: nil)
                }
                .keyboardShortcut("f")
            }
            CommandGroup(after: .toolbar) {
                Button(L10n.tr("Увеличить масштаб")) {
                    NotificationCenter.default.post(name: .zoomInRequested, object: nil)
                }
                .keyboardShortcut("+")
                Button(L10n.tr("Уменьшить масштаб")) {
                    NotificationCenter.default.post(name: .zoomOutRequested, object: nil)
                }
                .keyboardShortcut("-")
                Button(L10n.tr("По размеру экрана")) {
                    NotificationCenter.default.post(name: .zoomFitRequested, object: nil)
                }
                .keyboardShortcut("0")
            }
        }

        Settings {
            MapPrivacySettingsView()
                .environment(\.locale, language.locale)
                .preferredColorScheme(.light)
        }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .default
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
