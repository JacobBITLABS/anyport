import SwiftUI
import AppKit
import CoreSpotlight

struct SpotlightConnectView: View {
    let host: SSHHost
    let store: SSHConfigStore
    let orderManager: HostOrderManager
    var onDismiss: (() -> Void)?

    @State private var portInput = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @FocusState private var portFieldFocused: Bool

    private var portModeKey: String { "port_mode_\(host.alias)" }
    private var pathKey: String { "vscode_path_\(host.alias)" }

    private var isAdaptive: Bool {
        UserDefaults.standard.string(forKey: portModeKey) == "adaptive"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse)

                Text(host.alias)
                    .font(.system(size: 15, weight: .semibold))

                Design.microLabel(isAdaptive ? "Enter Port" : "Connecting")
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            if isAdaptive {
                TextField("22", text: $portInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 34, weight: .light, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .focused($portFieldFocused)
                    .onSubmit {
                        guard !portInput.isEmpty else { return }
                        connect()
                    }
                    .padding(.vertical, 12)
                    .background(Design.fieldShape.fill(.quaternary.opacity(0.5)))
                    .padding(.horizontal, 26)

                HStack(spacing: 10) {
                    Button {
                        onDismiss?()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        connect()
                    } label: {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(portInput.isEmpty)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 22)
            } else {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.green)
                        .padding(.bottom, 24)
                }
            }
        }
        .frame(width: 320)
        .glassEffect(.regular, in: Design.cardShape)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if isAdaptive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    portFieldFocused = true
                }
            } else {
                let port = host.port ?? "22"
                performConnect(port: port)
            }
        }
    }

    private func connect() {
        guard !portInput.isEmpty else { return }
        performConnect(port: portInput)
    }

    private func performConnect(port: String) {
        do {
            try store.updatePort(alias: host.alias, port: port)
            orderManager.recordVisit(alias: host.alias)

            let defaultTerminal = UserDefaults.standard.string(forKey: "default_terminal") ?? "terminal"
            var success = false
            switch defaultTerminal {
            case "iterm":
                success = Connector.openInITerm(alias: host.alias)
            case "vscode":
                let remotePath = UserDefaults.standard.string(forKey: pathKey) ?? "~"
                success = Connector.openInVSCode(alias: host.alias, remotePath: remotePath)
            default:
                success = Connector.openInTerminal(alias: host.alias)
            }

            statusIsError = !success
            statusMessage = success ? "Connected" : "Failed to launch terminal"

            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    onDismiss?()
                }
            }
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }
}
