import Foundation

enum ReactivateScript {
    static func generate() -> String? {
        let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"]

        switch termProgram {
        case "iTerm.app":
            return generateITermReactivateScript()
        case "Apple_Terminal":
            return generateTerminalReactivateScript()
        case "WarpTerminal":
            return "osascript -e 'tell application \"Warp\" to activate'"
        case "Alacritty":
            return "osascript -e 'tell application \"Alacritty\" to activate'"
        case "kitty":
            return "osascript -e 'tell application \"kitty\" to activate'"
        default:
            // Try to detect from parent process or fall back to generic activation
            if let bundleId = detectTerminalBundleId() {
                return "osascript -e 'tell application id \"\(bundleId)\" to activate'"
            }
            return nil
        }
    }

    private static func generateITermReactivateScript() -> String? {
        // Strategy 1: Use ITERM_SESSION_ID environment variable.
        // iTerm2 sets this directly in every session. This avoids the
        // AppleScript "current window" call which can fail when a Profile
        // uses a customized window name.
        // Format is "w{n}t{n}p{n}:{GUID}" — the AppleScript id property
        // returns just the GUID portion, so we strip the prefix.
        if let envSessionId = ProcessInfo.processInfo.environment["ITERM_SESSION_ID"],
           !envSessionId.isEmpty {
            let sessionId = envSessionId.split(separator: ":").last.map(String.init) ?? envSessionId
            return generateITermReactivateBySessionId(sessionId)
        }

        // Strategy 2: Use tty path to identify the session.
        // Completely independent of iTerm2's window/session naming.
        if isatty(STDIN_FILENO) != 0, let ttyName = ttyname(STDIN_FILENO) {
            let ttyPath = String(cString: ttyName)
            return generateITermReactivateByTty(ttyPath)
        }

        // Strategy 3: Original AppleScript approach (works when no custom window name).
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"iTerm2\" to id of current session of current window"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let sessionId = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sessionId.isEmpty else {
                return "osascript -e 'tell application \"iTerm2\" to activate'"
            }

            return generateITermReactivateBySessionId(sessionId)
        } catch {
            return "osascript -e 'tell application \"iTerm2\" to activate'"
        }
    }

    private static func generateITermReactivateBySessionId(_ sessionId: String) -> String {
        // Use heredoc to preserve newlines which AppleScript requires.
        // activate must come before select so the tab switch isn't
        // clobbered by the focus transition from Notification Center.
        return """
            osascript <<'APPLESCRIPT'
            tell application "iTerm2"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if id of s is "\(sessionId)" then
                                select w
                                select t
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            APPLESCRIPT
            """
    }

    private static func generateITermReactivateByTty(_ ttyPath: String) -> String {
        return """
            osascript <<'APPLESCRIPT'
            tell application "iTerm2"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(ttyPath)" then
                                select w
                                select t
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            APPLESCRIPT
            """
    }

    private static func generateTerminalReactivateScript() -> String? {
        // Capture the current Terminal.app window and tab
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", """
            tell application "Terminal"
                set windowId to id of front window
                set tabIndex to index of selected tab of front window
                return (windowId as text) & "," & (tabIndex as text)
            end tell
            """]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                return "osascript -e 'tell application \"Terminal\" to activate'"
            }

            let parts = output.split(separator: ",")
            guard parts.count == 2,
                  let windowId = Int(parts[0]),
                  let tabIndex = Int(parts[1]) else {
                return "osascript -e 'tell application \"Terminal\" to activate'"
            }

            // Generate AppleScript that finds and focuses this specific window/tab
            // Use heredoc to preserve newlines which AppleScript requires
            return """
                osascript <<'APPLESCRIPT'
                tell application "Terminal"
                    repeat with w in windows
                        if id of w is \(windowId) then
                            set selected tab of w to tab \(tabIndex) of w
                            set frontmost of w to true
                            activate
                            return
                        end if
                    end repeat
                end tell
                APPLESCRIPT
                """
        } catch {
            return "osascript -e 'tell application \"Terminal\" to activate'"
        }
    }

    private static func detectTerminalBundleId() -> String? {
        // Try to find the terminal by walking up the process tree
        var pid = getppid()
        while pid > 1 {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-p", String(pid), "-o", "comm="]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let comm = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    // Map common terminal process names to bundle IDs
                    switch comm {
                    case "iTerm2", "iTerm":
                        return "com.googlecode.iterm2"
                    case "Terminal":
                        return "com.apple.Terminal"
                    case "Warp":
                        return "dev.warp.Warp-Stable"
                    case "Alacritty":
                        return "org.alacritty"
                    case "kitty":
                        return "net.kovidgoyal.kitty"
                    default:
                        break
                    }
                }
            } catch {
                break
            }

            // Get parent PID
            let ppidTask = Process()
            ppidTask.executableURL = URL(fileURLWithPath: "/bin/ps")
            ppidTask.arguments = ["-p", String(pid), "-o", "ppid="]

            let ppidPipe = Pipe()
            ppidTask.standardOutput = ppidPipe
            ppidTask.standardError = FileHandle.nullDevice

            do {
                try ppidTask.run()
                ppidTask.waitUntilExit()

                let data = ppidPipe.fileHandleForReading.readDataToEndOfFile()
                if let ppidStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let newPid = Int32(ppidStr) {
                    pid = newPid
                } else {
                    break
                }
            } catch {
                break
            }
        }
        return nil
    }
}
