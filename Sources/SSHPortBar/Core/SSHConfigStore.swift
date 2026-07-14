import Foundation

@MainActor
final class SSHConfigStore: ObservableObject {
    @Published var hosts: [SSHHost] = []
    @Published var error: String?

    private let configURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh/config")

    func loadHosts() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            error = "~/.ssh/config not found"
            hosts = []
            return
        }

        do {
            let content = try String(contentsOf: configURL, encoding: .utf8)
            hosts = parseConfig(content)
            error = nil
        } catch {
            self.error = "Failed to read config: \(error.localizedDescription)"
        }
    }

    private func parseConfig(_ content: String) -> [SSHHost] {
        var lines = content.components(separatedBy: "\n")
        for i in lines.indices where lines[i].hasSuffix("\r") {
            lines[i].removeLast()
        }

        var result: [SSHHost] = []
        var current: SSHHost?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if lower.hasPrefix("host ") {
                if let host = current {
                    result.append(host)
                }

                let alias = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                let firstAlias = alias.split(separator: " ").first.map(String.init) ?? alias

                if firstAlias.contains("*") || firstAlias.contains("?") {
                    current = nil
                    continue
                }

                current = SSHHost(
                    id: firstAlias,
                    alias: firstAlias,
                    hostName: nil,
                    user: nil,
                    port: nil,
                    identityFile: nil,
                    startLine: index
                )
            } else if current != nil {
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count >= 2 else { continue }
                let key = String(parts[0]).lowercased()
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

                switch key {
                case "hostname": current?.hostName = value
                case "user": current?.user = value
                case "port": current?.port = value
                case "identityfile": current?.identityFile = value
                default: break
                }
            }
        }

        if let host = current {
            result.append(host)
        }

        var seen = Set<String>()
        return result.filter { seen.insert($0.alias).inserted }
    }

    func updatePort(alias: String, port: String) throws {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw SSHConfigError.configNotFound
        }

        let content = try String(contentsOf: configURL, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")
        for i in lines.indices where lines[i].hasSuffix("\r") {
            lines[i].removeLast()
        }

        var hostStartLine = -1
        var hostEndLine = lines.count

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if lower.hasPrefix("host ") {
                let hostAlias = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                let firstAlias = hostAlias.split(separator: " ").first.map(String.init) ?? hostAlias

                if firstAlias == alias {
                    hostStartLine = index
                } else if hostStartLine != -1 {
                    hostEndLine = index
                    break
                }
            }
        }

        guard hostStartLine != -1 else {
            throw SSHConfigError.hostNotFound(alias)
        }

        let backupURL = configURL.deletingLastPathComponent().appendingPathComponent("config.bak")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.copyItem(at: configURL, to: backupURL)

        let indent = detectIndent(lines: lines, startLine: hostStartLine, endLine: hostEndLine)

        var portLineIndex = -1
        for i in hostStartLine..<hostEndLine {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("port ") || lower == "port" {
                portLineIndex = i
                break
            }
        }

        if portLineIndex != -1 {
            lines[portLineIndex] = "\(indent)Port \(port)"
        } else {
            lines.insert("\(indent)Port \(port)", at: hostStartLine + 1)
        }

        let newContent = lines.joined(separator: "\n")
        guard let data = newContent.data(using: .utf8) else {
            throw SSHConfigError.writeFailed("Encoding failed")
        }
        try data.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

        loadHosts()
    }

    private func detectIndent(lines: [String], startLine: Int, endLine: Int) -> String {
        for i in (startLine + 1)..<endLine {
            let line = lines[i]
            if let firstNonSpace = line.firstIndex(where: { !$0.isWhitespace }),
               firstNonSpace > line.startIndex {
                return String(line[line.startIndex..<firstNonSpace])
            }
        }
        return "    "
    }
}

enum SSHConfigError: LocalizedError {
    case configNotFound
    case hostNotFound(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "~/.ssh/config not found"
        case .hostNotFound(let alias):
            return "Host \(alias) not found in config"
        case .writeFailed(let message):
            return "Failed to write config: \(message)"
        }
    }
}
