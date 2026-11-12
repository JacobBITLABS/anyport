import SwiftUI
import AppKit

/// Renders a connect target as the real application icon — instantly
/// decipherable at a glance — falling back to an SF Symbol when the app
/// can't be located on disk.
struct ConnectTargetIcon: View {
    let target: ConnectTarget
    var size: CGFloat = 16

    var body: some View {
        if let icon = Self.cache[target] {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: Self.fallbackSymbol(for: target))
                .font(.system(size: size * 0.75, weight: .medium))
                .frame(width: size, height: size)
        }
    }

    /// Resolved once per launch: bundle id → icon for every app that exists.
    private static let cache: [ConnectTarget: NSImage] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates: [ConnectTarget: [String]] = [
            .terminal: ["/System/Applications/Utilities/Terminal.app", "/Applications/Utilities/Terminal.app"],
            .iterm: ["/Applications/iTerm.app", "\(home)/Applications/iTerm.app"],
            .vscode: ["/Applications/Visual Studio Code.app", "\(home)/Applications/Visual Studio Code.app"]
        ]
        var icons: [ConnectTarget: NSImage] = [:]
        for (target, paths) in candidates {
            guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 64, height: 64)
            icons[target] = icon
        }
        return icons
    }()

    private static func fallbackSymbol(for target: ConnectTarget) -> String {
        switch target {
        case .terminal: return "terminal"
        case .iterm: return "terminal.fill"
        case .vscode: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Shared design tokens — restrained, ElevenLabs-style: monochrome surfaces,
/// micro-caps labels, one accent, generous radii.
enum Design {
    static let rowCorner: CGFloat = 12
    static let chipCorner: CGFloat = 16
    static let cardCorner: CGFloat = 24
    static let fieldCorner: CGFloat = 14

    static var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: rowCorner, style: .continuous)
    }

    static var chipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: chipCorner, style: .continuous)
    }

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
    }

    static var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: fieldCorner, style: .continuous)
    }

    /// Micro-caps section label, e.g. "PINNED", "ENTER PORT".
    static func microLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// Floating Liquid Glass card for entering an ad-hoc port before connecting.
/// Presented as an in-window overlay so the glass samples the list behind it.
/// The port field takes focus on appear; Return connects.
struct AdaptivePortCard: View {
    let alias: String
    @Binding var port: String
    var onCancel: () -> Void
    var onConnect: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse)

                Text(alias)
                    .font(.system(size: 15, weight: .semibold))

                Design.microLabel("Enter Port")
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            TextField("22", text: $port)
                .textFieldStyle(.plain)
                .font(.system(size: 34, weight: .light, design: .monospaced))
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .focused($fieldFocused)
                .onSubmit {
                    guard !port.isEmpty else { return }
                    onConnect()
                }
                .padding(.vertical, 12)
                .background(Design.fieldShape.fill(.quaternary.opacity(0.5)))
                .padding(.horizontal, 26)

            HStack(spacing: 10) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

                Button {
                    onConnect()
                } label: {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(port.isEmpty)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .frame(width: 300)
        .glassEffect(.regular, in: Design.cardShape)
        .onAppear {
            // Focus once the card has its first layout pass; otherwise the
            // focus request lands before the field exists in the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                fieldFocused = true
            }
        }
    }
}
