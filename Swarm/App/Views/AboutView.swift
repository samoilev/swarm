import AppKit
import SwarmCore
import SwiftUI

struct AboutView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            ZStack {
                Rectangle().fill(.regularMaterial)
                SepiaTheme.paper.opacity(0.9)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 116, height: 116)
                    .shadow(color: SepiaTheme.ink.opacity(0.18), radius: 10, x: 0, y: 5)
                    .accessibilityLabel(L10n.tr("Значок приложения Swarm"))

                Text(verbatim: "Swarm")
                    .font(SepiaTheme.display(size: 30))
                    .foregroundStyle(SepiaTheme.ink)
                    .padding(.top, 14)

                Text(versionText)
                    .font(SepiaType.label)
                    .foregroundStyle(SepiaTheme.inkSoft)
                    .padding(.top, 7)

                Rectangle()
                    .fill(SepiaTheme.fieldLine)
                    .frame(width: 56, height: 1)
                    .padding(.vertical, 20)

                Text(L10n.tr("Создавайте, исследуйте и сохраняйте историю своей семьи."))
                    .font(SepiaType.body)
                    .foregroundStyle(SepiaTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 300)

                Link(destination: URL(string: "https://github.com/samoilev/swarm")!) {
                    Label {
                        Text(L10n.tr("Исходный код на GitHub"))
                    } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                    .font(SepiaType.control)
                }
                .foregroundStyle(SepiaTheme.accent)
                .padding(.top, 14)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            showHelp()
                        } label: {
                            Label {
                                Text(L10n.tr("Справка Swarm"))
                            } icon: {
                                Image(systemName: "questionmark.circle")
                            }
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)

                        Button {
                            dismissWindow(id: SwarmApp.aboutWindowID)
                        } label: {
                            Text(L10n.tr("Закрыть"))
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .tint(SepiaTheme.accent)
                        .keyboardShortcut(.cancelAction)
                    }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 42)
            .padding(.top, 34)
            .padding(.bottom, 30)
        }
        .frame(width: 420)
    }

    private var versionText: String {
        let bundle = Bundle.main
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else {
            return L10n.tr("Версия для разработки")
        }

        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty, build != version {
            return L10n.tr("Версия \(version) (\(build))")
        }
        return L10n.tr("Версия \(version)")
    }

    private func showHelp() {
        dismissWindow(id: SwarmApp.aboutWindowID)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .helpRequested, object: nil)
        }
    }
}
