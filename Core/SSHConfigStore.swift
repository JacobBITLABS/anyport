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
            // Debug: `-DebugFewHosts` keeps only the first 4 hosts so the whole list fits on screen (visual QA).
            if ProcessInfo.processInfo.arguments.contains("-DebugFewHosts") {
                hosts = Array(hosts.prefix(4))
            }
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
                case "hostname": current?.hostName = unquote(value)
                case "user": current?.user = unquote(value)
                case "port": current?.port = unquote(value)
                case "identityfile": current?.identityFile = unquote(value)
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
        try updateHost(alias: alias, port: port)
    }

    /// Writes fields for a host block in ~/.ssh/config (with a config.bak backup).
    ///
    /// Field semantics: passing `nil` leaves the field untouched, an empty string
    /// removes its line from the block, and a value sets (or replaces) it. Values
    /// containing spaces are written quoted; quotes are stripped when parsing.
    func updateHost(alias: String,
                    hostName: String? = nil,
                    user: String? = nil,
                    port: String? = nil,
                    identityFile: String? = nil) throws {
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

        // Fields we can write, in canonical order. nil value = leave untouched.
        let desired: [(keyword: String, value: String?, quoteIfNeeded: Bool)] = [
            ("HostName", hostName.map(trimmed), true),
            ("User", user.map(trimmed), false),
            ("Port", port.map(trimmed), false),
            ("IdentityFile", identityFile.map(trimmed), true),
        ]

        // Drop existing lines only for the keys this call manages.
        let replacedKeywords = Set(desired.compactMap { $0.value != nil ? $0.keyword.lowercased() : nil })
        var block = Array(lines[hostStartLine..<hostEndLine]).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let keyword = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                .first.map(String.init)?.lowercased() ?? ""
            return keyword.isEmpty || !replacedKeywords.contains(keyword)
        }

        var newLines: [String] = []
        for field in desired {
            guard let value = field.value, !value.isEmpty else { continue }
            let rendered = field.quoteIfNeeded && value.contains(" ") ? "\"\(value)\"" : value
            newLines.append("\(indent)\(field.keyword) \(rendered)")
        }
        block.insert(contentsOf: newLines, at: min(1, block.count))

        lines.replaceSubrange(hostStartLine..<hostEndLine, with: block)

        let newContent = lines.joined(separator: "\n")
        guard let data = newContent.data(using: .utf8) else {
            throw SSHConfigError.writeFailed("Encoding failed")
        }
        try data.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

        loadHosts()
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
    }

    private func unquote(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespaces)
        if result.count >= 2, result.hasPrefix("\""), result.hasSuffix("\"") {
            result = String(result.dropFirst().dropLast())
        }
        return result
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
