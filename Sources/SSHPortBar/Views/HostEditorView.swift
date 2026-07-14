import SwiftUI
import AppKit

struct HostEditorView: View {
    let host: SSHHost
    @ObservedObject var store: SSHConfigStore
    @ObservedObject var orderManager: HostOrderManager

    @State private var port = ""
    @State private var remotePath = "~"
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isAdaptive = false
    @State private var showAdaptivePortPrompt = false
    @State private var adaptivePortInput = ""
    @State private var pendingTarget: ConnectTarget?

    private var pathKey: String { "vscode_path_\(host.alias)" }
    private var portModeKey: String { "port_mode_\(host.alias)" }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Connection") {
                    if let hostName = host.hostName {
                        LabeledContent("HostName", value: hostName)
                    }
                    if let user = host.user {
                        LabeledContent("User", value: user)
                    }
                    if let identityFile = host.identityFile {
                        LabeledContent("Identity", value: identityFile)
                            .font(.system(.body, design: .monospaced))
                    }
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
                        Text("Saved to ~/.ssh/config when you connect.")
                    }
                }

                Section {
                    HStack {
                        Text("Remote Path")
                        Spacer()
                        TextField("~", text: $remotePath)
                            .textFieldStyle(.roundedBorder)
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
                    Text("Opens in your default text editor.")
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
                        Label("Terminal", systemImage: "terminal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if FileManager.default.fileExists(atPath: "/Applications/iTerm.app") || FileManager.default.fileExists(atPath: "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/iTerm.app") {
                        Button {
                            connect(.iterm)
                        } label: {
                            Label("iTerm", systemImage: "terminal.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    Button {
                        connect(.vscode)
                    } label: {
                        Label("VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)
            }
            .animation(.easeInOut(duration: 0.2), value: statusMessage)
        }
        .navigationTitle(host.alias)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    orderManager.togglePin(alias: host.alias)
                } label: {
                    Image(systemName: orderManager.isPinned(alias: host.alias) ? "pin.fill" : "pin")
                        .foregroundStyle(orderManager.isPinned(alias: host.alias) ? .orange : .secondary)
                }
                .help(orderManager.isPinned(alias: host.alias) ? "Unpin host" : "Pin host to top")
            }
        }
        .sheet(isPresented: $showAdaptivePortPrompt) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Image(systemName: "network")
                        .font(.system(size: 28))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse)

                    Text(host.alias)
                        .font(.system(size: 15, weight: .semibold))

                    Text("Enter Port")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 28)
                .padding(.bottom, 20)

                TextField("22", text: $adaptivePortInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 32, weight: .light, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.quaternary.opacity(0.5))
                    )
                    .padding(.horizontal, 32)

                HStack(spacing: 12) {
                    Button {
                        showAdaptivePortPrompt = false
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        showAdaptivePortPrompt = false
                        guard let target = pendingTarget, !adaptivePortInput.isEmpty else { return }
                        performConnect(target, port: adaptivePortInput)
                    } label: {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.tint)
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .disabled(adaptivePortInput.isEmpty)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .frame(width: 320)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .onAppear {
                adaptivePortInput = ""
            }
        }
        .onAppear {
            let savedMode = UserDefaults.standard.string(forKey: portModeKey) ?? "fixed"
            isAdaptive = savedMode == "adaptive"
            port = host.port ?? "22"
            remotePath = UserDefaults.standard.string(forKey: pathKey) ?? "~"
        }
        .onDisappear {
            showAdaptivePortPrompt = false
            pendingTarget = nil
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

    private func performConnect(_ target: ConnectTarget, port: String) {
        do {
            try store.updatePort(alias: host.alias, port: port)
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
