import AppKit
import SwarmCore
import SwiftUI

@main
struct SwarmApp: App {
    static let aboutWindowID = "about"

    @State private var store: TreeStore
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue

    init() {
        AppLanguage.migrateLegacyPreferenceIfNeeded()
        let arguments = ProcessInfo.processInfo.arguments
        let storageFolder: URL? = arguments.firstIndex(of: "--storage-folder").flatMap { index in
            guard arguments.indices.contains(index + 1) else { return nil }
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        let initialStore = TreeStore(storageFolder: storageFolder)
        AppLanguage.prepareInitialChoice(hasExistingLibrary: !initialStore.trees.isEmpty)
        _store = State(initialValue: initialStore)
        NSApplication.shared.setActivationPolicy(.regular)
        // A packaged .app carries the icon in Contents/Resources, which is not where
        // SwiftPM's Bundle.module looks; reading Bundle.module there is fatal, so it
        // stays the fallback for `swift run`. See SwarmCore's ResourceBundle.
        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        if let iconURL, let icon = NSImage(contentsOf: iconURL) {
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
                    let window = NSApp.keyWindow ?? NSApp.windows.first
                    window?.makeKeyAndOrderFront(nil)
                    // Full screen exposes the window's own background in the strip the menu
                    // bar slides into. Left at the system default that strip is white, which
                    // reads as a torn sheet of paper above the sepia toolbar.
                    window?.backgroundColor = NSColor(SepiaTheme.toolbarBg)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                // No File▸New Tree and no ⌘N. Creating a record is a rare, deliberate act
                // that now takes over the whole window — and a shortcut that could fire it
                // over an open tree would throw the reader out of one without asking. The
                // library's own button is the only door in.
                //
                // Someone who opens the same tree every morning shouldn't have to walk
                // the library grid to get to it.
                Menu(L10n.tr("Открыть недавнее")) {
                    let recent = store.trees.sorted { $0.updatedAt > $1.updatedAt }.prefix(5)
                    if recent.isEmpty {
                        Button(L10n.tr("Пока пусто")) {}.disabled(true)
                    } else {
                        ForEach(Array(recent), id: \.id) { tree in
                            Button(tree.name) {
                                NotificationCenter.default.post(name: .openTreeRequested, object: tree.id)
                            }
                        }
                    }
                }
            }
            AboutCommands()
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
            CommandGroup(replacing: .help) {
                Button(L10n.tr("Справка Swarm")) {
                    NotificationCenter.default.post(name: .helpRequested, object: nil)
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
        }

        Settings {
            MapPrivacySettingsView()
                .environment(\.locale, language.locale)
                .preferredColorScheme(.light)
        }

        Window(Text(verbatim: "About Swarm"), id: Self.aboutWindowID) {
            AboutView()
                .preferredColorScheme(.light)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .default
    }
}

private struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button {
                openWindow(id: SwarmApp.aboutWindowID)
            } label: {
                Text(verbatim: "About Swarm")
            }
        }
    }
}

extension Notification.Name {
    /// Object is the `FamilyTree.id` to open.
    static let openTreeRequested = Notification.Name("openTreeRequested")
    static let zoomInRequested = Notification.Name("zoomInRequested")
    static let zoomOutRequested = Notification.Name("zoomOutRequested")
    static let zoomFitRequested = Notification.Name("zoomFitRequested")
    static let undoRequested = Notification.Name("undoRequested")
    static let redoRequested = Notification.Name("redoRequested")
    static let findPersonRequested = Notification.Name("findPersonRequested")
    static let helpRequested = Notification.Name("helpRequested")
}
