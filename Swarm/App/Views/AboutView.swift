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
                    .accessibilityLabel(Text(verbatim: "Swarm app icon"))

                Text(verbatim: "Swarm")
                    .font(SepiaTheme.display(size: 30))
                    .foregroundStyle(SepiaTheme.ink)
                    .padding(.top, 14)

                Text(versionText)
                    .font(SepiaTheme.ui(size: 11))
                    .foregroundStyle(SepiaTheme.inkSoft)
                    .padding(.top, 7)

                Rectangle()
                    .fill(SepiaTheme.fieldLine)
                    .frame(width: 56, height: 1)
                    .padding(.vertical, 20)

                Text(verbatim: "Create, explore, and preserve your family’s story.")
                    .font(SepiaTheme.body(size: 13))
                    .foregroundStyle(SepiaTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 300)

                Link(destination: URL(string: "https://github.com/samoilev/swarm")!) {
                    Label {
                        Text(verbatim: "View source on GitHub")
                    } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                    .font(SepiaTheme.ui(size: 12))
                }
                .foregroundStyle(SepiaTheme.accent)
                .padding(.top, 14)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            showHelp()
                        } label: {
                            Label {
                                Text(verbatim: "Swarm Help")
                            } icon: {
                                Image(systemName: "questionmark.circle")
                            }
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)

                        Button {
                            dismissWindow(id: SwarmApp.aboutWindowID)
                        } label: {
                            Text(verbatim: "Close")
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
            return "Development version"
        }

        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty, build != version {
            return "Version \(version) (\(build))"
        }
        return "Version \(version)"
    }

    private func showHelp() {
        dismissWindow(id: SwarmApp.aboutWindowID)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .helpRequested, object: nil)
        }
    }
}
