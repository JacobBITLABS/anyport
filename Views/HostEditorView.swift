import SwiftUI
import AppKit
import CoreSpotlight

struct HostEditorView: View {
    let host: SSHHost
    @ObservedObject var store: SSHConfigStore
    @ObservedObject var orderManager: HostOrderManager

    @State private var hostName = ""
    @State private var user = ""
    @State private var port = ""
    @State private var identityFile = ""
    @State private var remotePath = "~"
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isAdaptive = false
    @State private var showAdaptivePortPrompt = false
    @State private var adaptivePortInput = ""
    @State private var pendingTarget: ConnectTarget?

    @Environment(\.dismiss) private var dismiss

    private var pathKey: String { "vscode_path_\(host.alias)" }
    private var portModeKey: String { "port_mode_\(host.alias)" }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            Form {
                Section {
                    LabeledContent("Alias") {
                        Text(host.alias)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("HostName")
                        Spacer()
                        TextField("e.g. 10.0.0.5", text: $hostName)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 200)
                    }
                    HStack {
                        Text("User")
                        Spacer()
                        TextField("root", text: $user)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 140)
                    }
                    HStack {
                        Text("Identity File")
                        Spacer()
                        TextField("~/.ssh/id_ed25519", text: $identityFile)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 200)
                            .font(.system(.body, design: .monospaced))
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Leave a field empty to remove its line from the config. Saved to ~/.ssh/config when you press Save or Connect.")
                }

                Section {
                    Picker("Port Mode", selection: $isAdaptive) {
                        Text("Fixed").tag(false)
                        Text("Adaptive").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isAdaptive) { _, newValue in
                        UserDefaults.standard.set(newValue ? "adaptive" : "fixed", forKey: portModeKey)
                    }

                    if !isAdaptive {
                        HStack {
                            Text("Port")
                            Spacer()
                            TextField("22", text: $port)
                                .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                                .frame(width: 100)
                                .monospacedDigit()
                                .onChange(of: port) { _, newValue in
                                    port = String(newValue.filter { "0123456789".contains($0) })
                                }
                        }
                    } else {
                        HStack {
                            Text("Port")
                            Spacer()
                            Text("Prompt on connect")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 13))
                        }
                    }
                } header: {
                    Text("Port")
                } footer: {
                    if isAdaptive {
                        Text("You'll be prompted for a port number each time you connect.")
                    } else {
                        Text("Saved to ~/.ssh/config when you connect or save.")
                    }
                }

                Section {
                    HStack {
                        Text("Remote Path")
                        Spacer()
                        TextField("~", text: $remotePath)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 150)
                    }
                } header: {
                    Text("VS Code Remote Path")
                } footer: {
                    Text("Initial folder opened in VS Code Remote-SSH.")
                }

                Section {
                    HStack {
                        Text("~/.ssh/config")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open in Editor") {
                            let url = FileManager.default
                                .homeDirectoryForCurrentUser
                                .appendingPathComponent(".ssh/config")
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } header: {
                    Text("Config File")
                } footer: {
                    Text("Opens in your default text editor. A config.bak backup is kept next to it.")
                }
            }
            .formStyle(.grouped)

            Divider()

            VStack(spacing: 10) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .red : .green)
                        .transition(.opacity)
                }

                HStack(spacing: 10) {
                    Button {
                        connect(.terminal)
                    } label: {
                        HStack(spacing: 7) {
                            ConnectTargetIcon(target: .terminal, size: 14)
                            Text("Terminal")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                    if FileManager.default.fileExists(atPath: "/Applications/iTerm.app") || FileManager.default.fileExists(atPath: "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/iTerm.app") {
                        Button {
                            connect(.iterm)
                        } label: {
                            HStack(spacing: 7) {
                                ConnectTargetIcon(target: .iterm, size: 14)
                                Text("iTerm")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }

                    Button {
                        connect(.vscode)
                    } label: {
                        HStack(spacing: 7) {
                            ConnectTargetIcon(target: .vscode, size: 14)
                            Text("VS Code")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)
            }
            .animation(.easeInOut(duration: 0.2), value: statusMessage)
        }
        .overlay {
            adaptiveCardOverlay
        }
        .animation(.spring(duration: 0.35), value: showAdaptivePortPrompt)
        .onAppear {
            let savedMode = UserDefaults.standard.string(forKey: portModeKey) ?? "fixed"
            isAdaptive = savedMode == "adaptive"
            hostName = host.hostName ?? ""
            user = host.user ?? ""
            port = host.port ?? "22"
            identityFile = host.identityFile ?? ""
            remotePath = UserDefaults.standard.string(forKey: pathKey) ?? "~"
        }
        .onDisappear {
            showAdaptivePortPrompt = false
            pendingTarget = nil
        }
    }

    /// Custom minimal header: back, title, pin, save.
    private var editorHeader: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back")

            Text(host.alias)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Button {
                orderManager.togglePin(alias: host.alias)
            } label: {
                Image(systemName: orderManager.isPinned(alias: host.alias) ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        orderManager.isPinned(alias: host.alias) ? Color.accentColor : Color.secondary
                    )
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .help(orderManager.isPinned(alias: host.alias) ? "Unpin host" : "Pin host to top")

            Button {
                saveChanges()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save changes to ~/.ssh/config (⌘S)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    /// Floating Liquid Glass card shown over the editor when connecting in adaptive mode.
    @ViewBuilder
    private var adaptiveCardOverlay: some View {
        if showAdaptivePortPrompt {
            AdaptivePortCard(
                alias: host.alias,
                port: $adaptivePortInput,
                onCancel: { showAdaptivePortPrompt = false },
                onConnect: {
                    guard let target = pendingTarget, !adaptivePortInput.isEmpty else { return }
                    showAdaptivePortPrompt = false
                    performConnect(target, port: adaptivePortInput)
                }
            )
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    /// Writes all connection fields back to ~/.ssh/config.
    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try store.updateHost(
                alias: host.alias,
                hostName: hostName,
                user: user,
                port: isAdaptive ? nil : port,
                identityFile: identityFile
            )
            SpotlightIndexer.reindexHosts(store.hosts)
            statusIsError = false
            statusMessage = "Saved to ~/.ssh/config"
            return true
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func connect(_ target: ConnectTarget) {
        if isAdaptive {
            pendingTarget = target
            adaptivePortInput = ""
            showAdaptivePortPrompt = true
            return
        }

        guard !port.isEmpty else {
            statusIsError = true
            statusMessage = "Port cannot be empty"
            return
        }

        performConnect(target, port: port)
    }

    /// Saves all fields (port comes from the editor, or the ad-hoc prompt in adaptive mode), then opens the connection.
    private func performConnect(_ target: ConnectTarget, port: String?) {
        do {
            try store.updateHost(
                alias: host.alias,
                hostName: hostName,
                user: user,
                port: port,
                identityFile: identityFile
            )
            SpotlightIndexer.reindexHosts(store.hosts)
            UserDefaults.standard.set(remotePath, forKey: pathKey)
            orderManager.recordVisit(alias: host.alias)
            switch target {
            case .terminal:
                if Connector.openInTerminal(alias: host.alias) {
                    statusIsError = false
                    statusMessage = "Opened in Terminal"
                } else {
                    statusIsError = true
                    statusMessage = "Terminal could not be launched."
                }
            case .iterm:
                if Connector.openInITerm(alias: host.alias) {
                    statusIsError = false
                    statusMessage = "Opened in iTerm"
                } else {
                    statusIsError = true
                    statusMessage = "iTerm not found. Install from iterm2.com"
                }
            case .vscode:
                if Connector.openInVSCode(alias: host.alias, remotePath: remotePath) {
                    statusIsError = false
                    statusMessage = "Opened in VS Code"
                } else {
                    statusIsError = true
                    statusMessage = "VS Code CLI not found. Run 'code' from terminal first."
                }
            }
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }
}
