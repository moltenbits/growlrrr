import Foundation

public enum CustomAppBundle {
    /// Base directory for custom app bundles
    private static var appsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".growlrrr")
            .appendingPathComponent("apps")
    }

    /// Get the path to a custom app bundle
    public static func bundlePath(forAppName name: String) -> URL {
        appsDirectory.appendingPathComponent("\(name).app")
    }

    /// Get the bundle identifier for a custom app
    public static func bundleIdentifier(forAppName name: String) -> String {
        "com.moltenbits.growlrrr.\(name)"
    }

    /// Check if a custom app bundle exists
    public static func bundleExists(forAppName name: String) -> Bool {
        FileManager.default.fileExists(atPath: bundlePath(forAppName: name).path)
    }

    /// Check if we're currently running from a custom app bundle
    public static func isRunningFromCustomApp() -> Bool {
        let executablePath = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        return executablePath.path.contains(appsDirectory.path)
    }

    /// Get the name of the current custom app, if running from one
    public static func currentCustomAppName() -> String? {
        let executablePath = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()

        guard executablePath.path.contains(appsDirectory.path) else {
            return nil
        }

        // Path is like: ~/.growlrrr/apps/AppName.app/Contents/MacOS/growlrrr
        // Walk up to find the .app directory
        var current = executablePath.deletingLastPathComponent()
        for _ in 0..<5 {
            if current.pathExtension == "app" {
                return current.deletingPathExtension().lastPathComponent
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    /// List all custom app names (excludes the main growlrrr.app)
    public static func listCustomApps() -> [String] {
        guard FileManager.default.fileExists(atPath: appsDirectory.path) else {
            return []
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: appsDirectory,
                includingPropertiesForKeys: nil
            )
            return contents
                .filter { $0.pathExtension == "app" }
                .map { $0.deletingPathExtension().lastPathComponent }
                .filter { $0 != "growlrrr" }  // Exclude main app
                .sorted()
        } catch {
            return []
        }
    }

    /// Update the executable in all custom app bundles
    /// Returns a list of updated app names
    public static func updateAllBundles() throws -> [String] {
        guard let sourceBundlePath = findSourceBundle() else {
            throw GrowlrrrError.notificationFailed("Could not find growlrrr.app bundle")
        }

        let sourceExecutable = URL(fileURLWithPath: sourceBundlePath)
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("growlrrr")

        guard FileManager.default.fileExists(atPath: sourceExecutable.path) else {
            throw GrowlrrrError.notificationFailed("Could not find growlrrr executable in bundle")
        }

        let customApps = listCustomApps()
        var updated: [String] = []

        for appName in customApps {
            let customBundlePath = bundlePath(forAppName: appName)
            let destExecutable = executablePath(forAppName: appName)

            // Remove old executable and copy new one
            try? FileManager.default.removeItem(at: destExecutable)
            try FileManager.default.copyItem(at: sourceExecutable, to: destExecutable)

            // Make executable
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destExecutable.path
            )

            // Re-sign the bundle
            try signBundle(at: customBundlePath)

            // Re-register with Launch Services
            registerWithLaunchServices(at: customBundlePath)

            updated.append(appName)
        }

        return updated
    }

    /// Run a command from a custom app bundle and capture its output
    public static func runAndCapture(appName: String, arguments: [String]) throws -> String {
        let execPath = executablePath(forAppName: appName)

        guard FileManager.default.fileExists(atPath: execPath.path) else {
            throw GrowlrrrError.customAppNotFound(appName)
        }

        let process = Process()
        process.executableURL = execPath
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if let stderrStr = String(data: stderrData, encoding: .utf8), !stderrStr.isEmpty {
            fputs(stderrStr, stderr)
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Get the executable path for an existing bundle
    public static func executablePath(forAppName name: String) -> URL {
        bundlePath(forAppName: name)
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("growlrrr")
    }

    /// Ensure a custom app bundle exists with the specified icon
    /// If iconPath is nil, the bundle must already exist
    /// Returns the path to the executable within the bundle
    public static func ensureBundle(appName: String, iconPath: String?) throws -> URL {
        let customBundlePath = bundlePath(forAppName: appName)
        let customBundleId = bundleIdentifier(forAppName: appName)

        // Find the source bundle (main growlrrr.app)
        guard let sourceBundlePath = findSourceBundle() else {
            throw GrowlrrrError.notificationFailed("Could not find growlrrr.app bundle")
        }

        let bundleExists = FileManager.default.fileExists(atPath: customBundlePath.path)
        let iconDestination = customBundlePath
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("AppIcon.icns")

        // If bundle doesn't exist, we need an icon to create it
        if !bundleExists {
            guard let iconPath = iconPath else {
                throw GrowlrrrError.customAppNotFound(appName)
            }

            // Create apps directory if needed
            try FileManager.default.createDirectory(at: appsDirectory, withIntermediateDirectories: true)

            // Copy the source bundle
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: sourceBundlePath),
                to: customBundlePath
            )

            // Update Info.plist with new bundle identifier and name
            try updateInfoPlist(
                at: customBundlePath,
                bundleId: customBundleId,
                displayName: appName
            )

            // Set the icon
            try convertToIcns(sourcePath: iconPath, destinationPath: iconDestination.path)
        } else if let iconPath = iconPath {
            // Bundle exists and icon provided - update the icon
            try convertToIcns(sourcePath: iconPath, destinationPath: iconDestination.path)
        }

        // Always update the executable to ensure it has the latest code
        if bundleExists {
            let sourceExecutable = URL(fileURLWithPath: sourceBundlePath)
                .appendingPathComponent("Contents")
                .appendingPathComponent("MacOS")
                .appendingPathComponent("growlrrr")
            let destExecutable = customBundlePath
                .appendingPathComponent("Contents")
                .appendingPathComponent("MacOS")
                .appendingPathComponent("growlrrr")

            try? FileManager.default.removeItem(at: destExecutable)
            try FileManager.default.copyItem(at: sourceExecutable, to: destExecutable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destExecutable.path)
        }

        // Re-sign the bundle (always needed after updating executable)
        try signBundle(at: customBundlePath)
        registerWithLaunchServices(at: customBundlePath)

        // Return path to the executable
        return customBundlePath
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("growlrrr")
    }

    /// Run a notification using a custom app bundle
    public static func runNotification(appName: String, iconPath: String?, arguments: [String]) throws {
        let executablePath = try ensureBundle(appName: appName, iconPath: iconPath)

        // Filter out --appId and --appIcon from arguments
        let filteredArgs = filterCustomAppArgs(arguments)

        // Run the notification from the custom bundle
        let process = Process()
        process.executableURL = executablePath
        process.arguments = filteredArgs
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        exit(process.terminationStatus)
    }

    // MARK: - Private Helpers

    private static func findSourceBundle() -> String? {
        let executablePath = ProcessInfo.processInfo.arguments[0]
        var url = URL(fileURLWithPath: executablePath)

        // Resolve symlinks to find the actual executable inside the app bundle
        url = url.resolvingSymlinksInPath()

        // Walk up to find .app bundle
        var current = url.deletingLastPathComponent()
        for _ in 0..<5 {
            if current.pathExtension == "app" {
                return current.path
            }
            if current.path == "/" {
                break
            }
            current = current.deletingLastPathComponent()
        }

        return nil
    }

    private static func updateInfoPlist(at bundlePath: URL, bundleId: String, displayName: String) throws {
        let plistPath = bundlePath
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")

        guard var plist = NSDictionary(contentsOf: plistPath) as? [String: Any] else {
            throw GrowlrrrError.notificationFailed("Could not read Info.plist")
        }

        plist["CFBundleIdentifier"] = bundleId
        plist["CFBundleName"] = displayName
        plist["CFBundleDisplayName"] = displayName

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistPath)
    }

    private static func signBundle(at bundlePath: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", bundlePath.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    private static func registerWithLaunchServices(at bundlePath: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        process.arguments = ["-f", bundlePath.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private static func convertToIcns(sourcePath: String, destinationPath: String) throws {
        let tempIconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("growlrrr-iconset-\(UUID().uuidString).iconset")

        try FileManager.default.createDirectory(at: tempIconset, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempIconset)
        }

        let sizes: [(Int, String)] = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png"),
        ]

        for (size, name) in sizes {
            let outputPath = tempIconset.appendingPathComponent(name)
            let sips = Process()
            sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            sips.arguments = ["-z", String(size), String(size), sourcePath, "--out", outputPath.path]
            sips.standardOutput = FileHandle.nullDevice
            sips.standardError = FileHandle.nullDevice
            try sips.run()
            sips.waitUntilExit()

            if sips.terminationStatus != 0 {
                throw GrowlrrrError.notificationFailed("Failed to resize icon")
            }
        }

        // Remove existing icns if present
        try? FileManager.default.removeItem(atPath: destinationPath)

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", tempIconset.path, "-o", destinationPath]
        iconutil.standardOutput = FileHandle.nullDevice
        iconutil.standardError = FileHandle.nullDevice
        try iconutil.run()
        iconutil.waitUntilExit()

        if iconutil.terminationStatus != 0 {
            throw GrowlrrrError.notificationFailed("Failed to convert icon to ICNS format")
        }
    }

    private static func filterCustomAppArgs(_ args: [String]) -> [String] {
        var result: [String] = []
        var skipNext = false

        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }

            if arg == "--appId" || arg == "--appIcon" {
                skipNext = true
                continue
            }

            if arg.hasPrefix("--appId=") || arg.hasPrefix("--appIcon=") {
                continue
            }

            result.append(arg)
        }

        return result
    }
}
