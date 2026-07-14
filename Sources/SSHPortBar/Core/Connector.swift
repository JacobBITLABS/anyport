import Foundation

enum Connector {
    static func openInTerminal(alias: String) -> Bool {
        let script = """
        tell application "Terminal"
            activate
            do script "ssh \(alias)"
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var errorInfo: NSDictionary?
        let result = appleScript?.executeAndReturnError(&errorInfo)
        if result == nil, let error = errorInfo {
            print("Terminal AppleScript error: \(error)")
            return false
        }
        return true
    }

    static func openInITerm(alias: String) -> Bool {
        let itermPaths = [
            "/Applications/iTerm.app",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/iTerm.app"
        ]
        guard itermPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return false
        }

        let script = """
        tell application "iTerm"
            activate
            if (count of windows) = 0 then
                create window with default profile
            else
                tell current window
                    create tab with default profile
                end tell
            end if
            tell current session of current tab of current window
                write text "ssh \(alias)"
            end tell
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var errorInfo: NSDictionary?
        let result = appleScript?.executeAndReturnError(&errorInfo)
        if result == nil, let error = errorInfo {
            print("iTerm AppleScript error: \(error)")
            return false
        }
        return true
    }

    static func openInVSCode(alias: String, remotePath: String) -> Bool {
        guard let codePath = findCode() else {
            return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: codePath)
        task.arguments = ["--remote", "ssh-remote+\(alias)", remotePath]
        do {
            try task.run()
        } catch {
            print("Failed to launch VS Code: \(error)")
            return false
        }
        return true
    }

    private static func findCode() -> String? {
        let candidates = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["code"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            // ignore
        }
        return nil
    }
}
