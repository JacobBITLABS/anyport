import Foundation

struct SSHHost: Identifiable, Hashable {
    let id: String
    let alias: String
    var hostName: String?
    var user: String?
    var port: String?
    var identityFile: String?
    var startLine: Int

    var displaySubtitle: String {
        var parts: [String] = []
        if let hostName {
            parts.append(hostName)
        }
        if let port, !port.isEmpty {
            parts.append(":\(port)")
        }
        return parts.isEmpty ? alias : parts.joined()
    }

    static func == (lhs: SSHHost, rhs: SSHHost) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
