import Foundation

enum ReadmdPathMode: String, Codable, CaseIterable, Hashable {
    case automatic
    case custom
}

enum ReadmdAvailability: String, Codable, Hashable {
    case ready
    case missing
    case invalid
}

struct ReadmdSettings: Codable, Equatable, Hashable {
    var pathMode: ReadmdPathMode = .automatic
    var customPath: String = ""
    var detectedPath: String = ""
    var status: ReadmdAvailability = .missing
    var version: String = ""
    var message: String = "readmd not checked"

    var resolvedPath: String? {
        switch pathMode {
        case .automatic: return detectedPath.isEmpty ? nil : detectedPath
        case .custom: return customPath.isEmpty ? nil : customPath
        }
    }
}

enum ReadmdLocator {
    static let homebrewInstallCommand = "brew update && brew tap peeomid/tap && brew install peeomid/tap/readmd"
    static let githubCargoInstallCommand = "cargo install --git https://github.com/peeomid/readmd.git --force"

    static func resolve(settings: ReadmdSettings) async -> ReadmdSettings {
        await Task.detached(priority: .utility) {
            switch settings.pathMode {
            case .automatic:
                return resolveAutomatic(settings: settings)
            case .custom:
                var updated = settings
                let check = validate(path: settings.customPath)
                updated.status = check.status
                updated.version = check.version
                updated.message = check.message
                return updated
            }
        }.value
    }

    static func candidatePaths() -> [String] {
        var paths = [
            "/opt/homebrew/bin/readmd",
            "/usr/local/bin/readmd",
            NSString(string: "~/.local/bin/readmd").expandingTildeInPath,
            NSString(string: "~/bin/readmd").expandingTildeInPath
        ]
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        paths += pathValue.split(separator: ":").map { String($0) + "/readmd" }
        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }

    private static func resolveAutomatic(settings: ReadmdSettings) -> ReadmdSettings {
        var updated = settings
        for path in candidatePaths() {
            let check = validate(path: path)
            if check.status == .ready {
                updated.detectedPath = path
                updated.status = .ready
                updated.version = check.version
                updated.message = check.message
                return updated
            }
        }
        updated.detectedPath = ""
        updated.status = .missing
        updated.version = ""
        updated.message = "readmd was not found. Install with Homebrew, then run Auto-detect."
        return updated
    }

    static func validate(path: String) -> (status: ReadmdAvailability, version: String, message: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (.missing, "", "No readmd path set") }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return (.missing, "", "readmd not found at this path") }
        guard FileManager.default.isExecutableFile(atPath: expanded) else { return (.invalid, "", "File exists but is not executable") }

        do {
            let versionCheck = try run(path: expanded, arguments: ["--version"])
            let version = versionCheck.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard versionCheck.status == 0 else {
                return (.invalid, "", versionCheck.error.isEmpty ? "readmd --version failed" : versionCheck.error)
            }

            let configCheck = try run(path: expanded, arguments: ["config", "print-default"])
            guard configCheck.status == 0,
                  configCheck.output.contains("default_theme"),
                  configCheck.output.contains("default_style") else {
                return (.invalid, version, "This readmd is not the Osimify renderer. Install with Homebrew or GitHub Cargo.")
            }

            return (.ready, version, version.isEmpty ? "readmd is ready" : "readmd is ready: \(version)")
        } catch {
            return (.invalid, "", error.localizedDescription)
        }
    }

    private static func run(path: String, arguments: [String]) throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, outputText, errorText)
    }
}
