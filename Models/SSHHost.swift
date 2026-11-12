import Foundation

struct SSHHost: Identifiable, Hashable {
    let id: String
    let alias: String
    var hostName: String?
    var user: String?
    var port: String?
    var identityFile: String?
    var startLine: Int

    /// Secondary line under the alias. Only shown when it says something the
    /// alias doesn't already: a different hostname, or a non-default port.
    var displaySubtitle: String? {
        var parts: [String] = []
        if let hostName, !hostName.isEmpty, hostName != alias {
            parts.append(hostName)
        }
        if let port, !port.isEmpty, port != "22" {
            parts.append(":\(port)")
        }
        return parts.isEmpty ? nil : parts.joined()
    }

    static func == (lhs: SSHHost, rhs: SSHHost) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
