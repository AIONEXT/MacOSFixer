import Foundation

public final class SystemVerification: Sendable {
    private let executor = CommandExecutor.shared

    public init() {}

    public func runVerification(
        types: [VerificationType],
        verbose: Bool = false,
        autoFix: Bool = false
    ) async throws -> VerificationSummary {
        var results: [VerificationResult] = []

        for type in types {
            let result = try await runTypeVerification(type, verbose: verbose, autoFix: autoFix)
            results.append(result)
        }

        return VerificationSummary(results: results)
    }

    private func runTypeVerification(_ type: VerificationType, verbose: Bool, autoFix: Bool) async throws -> VerificationResult {
        let startTime = Date()
        var issues: [VerificationIssue] = []

        switch type {
        case .filesystem:
            issues = try await verifyFilesystem(autoFix: autoFix)
        case .packages:
            issues = try await verifyPackages(autoFix: autoFix)
        case .binaries:
            issues = try await verifyBinaries(autoFix: autoFix)
        case .preferences:
            issues = try await verifyPreferences(autoFix: autoFix)
        case .keychain:
            issues = try await verifyKeychain(autoFix: autoFix)
        case .tcc:
            issues = try await verifyTCC(autoFix: autoFix)
        case .codesign:
            issues = try await verifyCodeSign(autoFix: autoFix)
        case .sip:
            issues = try await verifySIP(autoFix: autoFix)
        case .amfi:
            issues = try await verifyAMFI(autoFix: autoFix)
        case .launchd:
            issues = try await verifyLaunchd(autoFix: autoFix)
        case .cron:
            issues = try await verifyCron(autoFix: autoFix)
        case .loginItems:
            issues = try await verifyLoginItems(autoFix: autoFix)
        }

        let passed = issues.filter { $0.severity == .critical }.isEmpty
        let duration = Date().timeIntervalSince(startTime)

        return VerificationResult(
            type: type,
            passed: passed,
            issues: issues,
            duration: duration
        )
    }

    // MARK: - Individual Verifications

    private func verifyFilesystem(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        // Verify root volume
        let verifyResult = try await executor.run("/usr/sbin/diskutil", arguments: ["verifyVolume", "/"])
        if !verifyResult.success || verifyResult.stdout.lowercased().contains("error") {
            issues.append(VerificationIssue(
                category: .filesystem,
                severity: .critical,
                description: "Root filesystem verification failed",
                path: "/",
                fixed: false,
                autoFixable: false // Requires Recovery Mode
            ))
        } else {
            issues.append(VerificationIssue(
                category: .filesystem,
                severity: .info,
                description: "Root filesystem OK",
                path: "/",
                fixed: true,
                autoFixable: false
            ))
        }

        // Check all APFS volumes
        let apfsResult = try await executor.run("/usr/sbin/diskutil", arguments: ["apfs", "list"])
        if apfsResult.success {
            let volumes = parseAPFSVolumes(apfsResult.stdout)
            for volume in volumes {
                let volVerify = try await executor.run("/usr/sbin/diskutil", arguments: ["verifyVolume", volume])
                if !volVerify.success || volVerify.stdout.lowercased().contains("error") {
                    issues.append(VerificationIssue(
                        category: .filesystem,
                        severity: .warning,
                        description: "APFS volume verification failed: \(volume)",
                        path: volume,
                        fixed: false,
                        autoFixable: false
                    ))
                }
            }
        }

        // Check for orphaned snapshots
        let snapResult = try await executor.run("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"])
        if snapResult.success {
            let snapshots = snapResult.stdout.components(separatedBy: .newlines)
                .filter { $0.contains("com.apple.TimeMachine") }
            if snapshots.count > 20 {
                issues.append(VerificationIssue(
                    category: .filesystem,
                    severity: .warning,
                    description: "\(snapshots.count) local snapshots may consume excessive space",
                    path: "/",
                    fixed: false,
                    autoFixable: true
                ))
            }
        }

        return issues
    }

    private func parseAPFSVolumes(_ output: String) -> [String] {
        let lines = output.components(separatedBy: .newlines)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Mount Point:") {
                let parts = trimmed.split(separator: ":")
                if parts.count > 1 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }
    }

    private func verifyPackages(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        // Check package receipts
        let pkgResult = try await executor.run("/usr/sbin/pkgutil", arguments: ["--verify", "--verbose"])
        if pkgResult.success {
            for line in pkgResult.stdout.components(separatedBy: .newlines) {
                if line.contains("WARNING") || line.contains("ERROR") {
                    issues.append(VerificationIssue(
                        category: .packages,
                        severity: line.contains("ERROR") ? .critical : .warning,
                        description: line.trimmingCharacters(in: .whitespaces),
                        path: nil,
                        fixed: false,
                        autoFixable: false
                    ))
                }
            }
        }

        // Check for broken packages
        let brokenResult = try await executor.run("/usr/sbin/pkgutil", arguments: ["--check-signature"])
        if !brokenResult.success {
            issues.append(VerificationIssue(
                category: .packages,
                severity: .warning,
                description: "Some package signatures could not be verified",
                path: nil,
                fixed: false,
                autoFixable: false
            ))
        }

        return issues
    }

    private func verifyBinaries(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        // Check system binaries codesign
        let systemBinaries = [
            "/bin/bash", "/bin/zsh", "/usr/bin/sudo", "/usr/bin/ssh",
            "/System/Library/CoreServices/Finder.app", "/System/Library/CoreServices/Dock.app"
        ]

        for binary in systemBinaries {
            if FileManager.default.fileExists(atPath: binary) {
                let codesignResult = try await executor.run("/usr/bin/codesign", arguments: ["-vvv", binary])
                if !codesignResult.success {
                    issues.append(VerificationIssue(
                        category: .binaries,
                        severity: .critical,
                        description: "Code signature verification failed: \(binary)",
                        path: binary,
                        fixed: false,
                        autoFixable: false
                    ))
                }
            }
        }

        return issues
    }

    private func verifyPreferences(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        let prefsDirs = [
            "~/Library/Preferences".expandingTildeInPath,
            "/Library/Preferences"
        ]

        for dir in prefsDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            let plists = contents.filter { $0.hasSuffix(".plist") }

            for plist in plists {
                let path = (dir as NSString).appendingPathComponent(plist)
                if let data = FileManager.default.contents(atPath: path) {
                    do {
                        _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                    } catch {
                        issues.append(VerificationIssue(
                            category: .preferences,
                            severity: .warning,
                            description: "Corrupt preference file: \(plist)",
                            path: path,
                            fixed: false,
                            autoFixable: true
                        ))
                    }
                }
            }
        }

        return issues
    }

    private func verifyKeychain(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        // Verify login keychain
        let loginKeychain = "~/Library/Keychains/login.keychain-db".expandingTildeInPath
        if FileManager.default.fileExists(atPath: loginKeychain) {
            let verifyResult = try await executor.run("/usr/bin/security", arguments: ["verify-keychain", loginKeychain])
            if !verifyResult.success {
                issues.append(VerificationIssue(
                    category: .keychain,
                    severity: .warning,
                    description: "Login keychain verification failed",
                    path: loginKeychain,
                    fixed: false,
                    autoFixable: true
                ))
            }
        }

        // Verify system keychain
        let systemKeychain = "/Library/Keychains/System.keychain"
        let sysVerifyResult = try await executor.run("/usr/bin/security", arguments: ["verify-keychain", systemKeychain])
        if !sysVerifyResult.success {
            issues.append(VerificationIssue(
                category: .keychain,
                severity: .critical,
                description: "System keychain verification failed",
                path: systemKeychain,
                fixed: false,
                autoFixable: true
            ))
        }

        return issues
    }

    private func verifyTCC(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        let tccPaths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "~/Library/Application Support/com.apple.TCC/TCC.db".expandingTildeInPath
        ]

        for path in tccPaths where FileManager.default.fileExists(atPath: path) {
            let integrityResult = try await executor.run("/usr/bin/sqlite3", arguments: [path, "PRAGMA integrity_check;"])
            if integrityResult.success, !integrityResult.stdout.contains("ok") {
                issues.append(VerificationIssue(
                    category: .tcc,
                    severity: .critical,
                    description: "TCC database corruption detected",
                    path: path,
                    fixed: false,
                    autoFixable: false // Requires Recovery Mode
                ))
            }

            // Check for duplicate entries
            let dupResult = try await executor.run("/usr/bin/sqlite3", arguments: [path, "SELECT service, client, COUNT(*) FROM access GROUP BY service, client HAVING COUNT(*) > 1;"])
            if dupResult.success, !dupResult.stdout.isEmpty {
                issues.append(VerificationIssue(
                    category: .tcc,
                    severity: .warning,
                    description: "Duplicate TCC entries found",
                    path: path,
                    fixed: false,
                    autoFixable: true
                ))
            }
        }

        return issues
    }

    private func verifyCodeSign(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        // Check system integrity
        let csrResult = try await executor.run("/usr/bin/csrutil", arguments: ["status"])
        if csrResult.success, !csrResult.stdout.contains("enabled") {
            issues.append(VerificationIssue(
                category: .codesign,
                severity: .critical,
                description: "System Integrity Protection is disabled",
                path: nil,
                fixed: false,
                autoFixable: false
            ))
        }

        // Check AMFI
        let amfiResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "kern.amfi.trustcache.enabled"])
        if amfiResult.success, amfiResult.stdout.trimmingCharacters(in: .whitespaces) != "1" {
            issues.append(VerificationIssue(
                category: .codesign,
                severity: .warning,
                description: "AMFI trust cache is disabled",
                path: nil,
                fixed: false,
                autoFixable: false
            ))
        }

        return issues
    }

    private func verifySIP(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        let sipResult = try await executor.run("/usr/bin/csrutil", arguments: ["status"])
        if sipResult.success {
            if sipResult.stdout.contains("enabled") {
                issues.append(VerificationIssue(
                    category: .sip,
                    severity: .info,
                    description: "System Integrity Protection is enabled",
                    path: nil,
                    fixed: true,
                    autoFixable: false
                ))
            } else {
                issues.append(VerificationIssue(
                    category: .sip,
                    severity: .critical,
                    description: "System Integrity Protection is DISABLED",
                    path: nil,
                    fixed: false,
                    autoFixable: false
                ))
            }
        }

        return issues
    }

    private func verifyAMFI(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        let amfiResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "kern.amfi.trustcache.enabled"])
        if amfiResult.success {
            let enabled = amfiResult.stdout.trimmingCharacters(in: .whitespaces) == "1"
            if enabled {
                issues.append(VerificationIssue(
                    category: .amfi,
                    severity: .info,
                    description: "AMFI trust cache is enabled",
                    path: nil,
                    fixed: true,
                    autoFixable: false
                ))
            } else {
                issues.append(VerificationIssue(
                    category: .amfi,
                    severity: .warning,
                    description: "AMFI trust cache is disabled",
                    path: nil,
                    fixed: false,
                    autoFixable: false
                ))
            }
        }

        return issues
    }

    private func verifyLaunchd(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        let launchDirs = [
            "/Library/LaunchDaemons",
            "/Library/LaunchAgents",
            "~/Library/LaunchAgents".expandingTildeInPath
        ]

        for dir in launchDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            let plists = contents.filter { $0.hasSuffix(".plist") }

            for plist in plists {
                let path = (dir as NSString).appendingPathComponent(plist)
                if let data = FileManager.default.contents(atPath: path),
                   let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {

                    // Check for missing program
                    if dict["Program"] == nil && (dict["ProgramArguments"] as? [String])?.first == nil {
                        issues.append(VerificationIssue(
                            category: .launchd,
                            severity: .warning,
                            description: "Launch item missing Program/ProgramArguments: \(plist)",
                            path: path,
                            fixed: false,
                            autoFixable: true
                        ))
                    }

                    // Check for non-existent program
                    if let program = dict["Program"] as? String {
                        if !FileManager.default.fileExists(atPath: program) {
                            issues.append(VerificationIssue(
                                category: .launchd,
                                severity: .warning,
                                description: "Launch item references non-existent program: \(plist) -> \(program)",
                                path: path,
                                fixed: false,
                                autoFixable: true
                            ))
                        }
                    }
                }
            }
        }

        return issues
    }

    private func verifyCron(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        // Check system crontab
        let cronResult = try await executor.run("/usr/bin/crontab", arguments: ["-l"])
        if cronResult.success, !cronResult.stdout.isEmpty, !cronResult.stdout.contains("no crontab") {
            issues.append(VerificationIssue(
                category: .cron,
                severity: .info,
                description: "User crontab exists",
                path: nil,
                fixed: true,
                autoFixable: false
            ))
        }

        // Check /etc/crontab
        if FileManager.default.fileExists(atPath: "/etc/crontab") {
            let etcResult = try await executor.run("/bin/cat", arguments: ["/etc/crontab"])
            if etcResult.success, !etcResult.stdout.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(VerificationIssue(
                    category: .cron,
                    severity: .info,
                    description: "System crontab (/etc/crontab) has entries",
                    path: "/etc/crontab",
                    fixed: true,
                    autoFixable: false
                ))
            }
        }

        // Check periodic scripts
        let periodicDirs = ["/etc/periodic/daily", "/etc/periodic/weekly", "/etc/periodic/monthly"]
        for dir in periodicDirs {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir), !contents.isEmpty {
                issues.append(VerificationIssue(
                    category: .cron,
                    severity: .info,
                    description: "Periodic scripts found in \(dir): \(contents.count) items",
                    path: dir,
                    fixed: true,
                    autoFixable: false
                ))
            }
        }

        return issues
    }

    private func verifyLoginItems(autoFix: Bool) async throws -> [VerificationIssue] {
        var issues: [VerificationIssue] = []

        let script = """
        tell application "System Events"
            get the name, path, hidden of every login item
        end tell
        """

        let result = try await executor.run("/usr/bin/osascript", arguments: ["-e", script])
        if result.success {
            // Parse output - simplified
            let lines = result.stdout.components(separatedBy: ", ")
            if lines.count > 15 {
                issues.append(VerificationIssue(
                    category: .loginItems,
                    severity: .warning,
                    description: "Many login items (\(lines.count)) may slow boot",
                    path: nil,
                    fixed: false,
                    autoFixable: true
                ))
            }
        }

        return issues
    }
}