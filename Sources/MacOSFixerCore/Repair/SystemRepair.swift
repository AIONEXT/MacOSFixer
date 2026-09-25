import Foundation

public final class SystemRepair: Sendable {
    private let executor = CommandExecutor.shared
    private let fileUtils = FileSystemUtils.self

    public init() {}

    public func runRepairs(
        categories: [RepairCategory],
        dryRun: Bool = false,
        force: Bool = false,
        createBackup: Bool = true
    ) async throws -> RepairSummary {
        let startTime = Date()
        var results: [RepairResult] = []
        var backupPath: String?

        if createBackup && !dryRun {
            backupPath = try await createSystemBackup()
        }

        for category in categories {
            let result = try await runCategoryRepair(category, dryRun: dryRun, force: force)
            results.append(result)
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let totalIssuesFound = results.reduce(0) { $0 + $1.issuesFound }
        let totalIssuesFixed = results.reduce(0) { $0 + $1.issuesFixed }
        let totalErrors = results.reduce(0) { $0 + $1.errors.count }

        return RepairSummary(
            results: results,
            totalIssuesFound: totalIssuesFound,
            totalIssuesFixed: totalIssuesFixed,
            totalErrors: totalErrors,
            totalDuration: totalDuration,
            backupPath: backupPath
        )
    }

    private func createSystemBackup() async throws -> String {
        let backupDir = "/tmp/macosfixer-backup-\(Date().timeIntervalSince1970)"
        try FileManager.default.createDirectory(atPath: backupDir, withIntermediateDirectories: true)

        // Backup key directories
        let backupTargets = [
            "/Library/Preferences",
            "~/Library/Preferences".expandingTildeInPath,
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "~/Library/LaunchAgents".expandingTildeInPath
        ]

        for target in backupTargets {
            let destName = target.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "~", with: "home")
            let dest = "\(backupDir)/\(destName)"
            try await executor.run("/bin/cp", arguments: ["-R", target, dest])
        }

        return backupDir
    }

    private func runCategoryRepair(_ category: RepairCategory, dryRun: Bool, force: Bool) async throws -> RepairResult {
        let startTime = Date()
        var issuesFound = 0
        var issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        switch category {
        case .permissions:
            (issuesFound, issuesFixed, errors, details) = try await repairPermissions(dryRun: dryRun, force: force)
        case .disk:
            (issuesFound, issuesFixed, errors, details) = try await repairDisk(dryRun: dryRun, force: force)
        case .caches:
            (issuesFound, issuesFixed, errors, details) = try await repairCaches(dryRun: dryRun, force: force)
        case .logs:
            (issuesFound, issuesFixed, errors, details) = try await repairLogs(dryRun: dryRun, force: force)
        case .preferences:
            (issuesFound, issuesFixed, errors, details) = try await repairPreferences(dryRun: dryRun, force: force)
        case .launchd:
            (issuesFound, issuesFixed, errors, details) = try await repairLaunchd(dryRun: dryRun, force: force)
        case .spotlight:
            (issuesFound, issuesFixed, errors, details) = try await repairSpotlight(dryRun: dryRun, force: force)
        case .docker:
            (issuesFound, issuesFixed, errors, details) = try await repairDocker(dryRun: dryRun, force: force)
        case .homebrew:
            (issuesFound, issuesFixed, errors, details) = try await repairHomebrew(dryRun: dryRun, force: force)
        case .keychain:
            (issuesFound, issuesFixed, errors, details) = try await repairKeychain(dryRun: dryRun, force: force)
        case .tcc:
            (issuesFound, issuesFixed, errors, details) = try await repairTCC(dryRun: dryRun, force: force)
        case .fonts:
            (issuesFound, issuesFixed, errors, details) = try await repairFonts(dryRun: dryRun, force: force)
        case .metadata:
            (issuesFound, issuesFixed, errors, details) = try await repairMetadata(dryRun: dryRun, force: force)
        }

        let success = errors.isEmpty
        let duration = Date().timeIntervalSince(startTime)

        return RepairResult(
            category: category,
            success: success,
            issuesFound: issuesFound,
            issuesFixed: issuesFixed,
            errors: errors,
            details: details,
            duration: duration
        )
    }

    // MARK: - Individual Repair Functions

    private func repairPermissions(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        // Repair home directory permissions
        let homeDir = NSHomeDirectory()
        let userResult = try await executor.run("/usr/bin/id", arguments: ["-u"])
        let user = userResult.stdout.trimmingCharacters(in: .whitespaces)

        if !dryRun {
            // Reset home directory ownership
            let chownResult = try await executor.run("/usr/sbin/chown", arguments: ["-R", "\(user):staff", homeDir], asRoot: true)
            if chownResult.success {
                issuesFixed += 1
                details.append("Fixed home directory ownership")
            } else {
                errors.append("Failed to fix home directory ownership: \(chownResult.stderr)")
            }

            // Repair disk permissions (for non-System volumes)
            let diskResult = try await executor.run("/usr/sbin/diskutil", arguments: ["resetUserPermissions", "/", "\(user)"])
            if diskResult.success {
                issuesFixed += 1
                details.append("Reset user permissions on boot volume")
            } else {
                details.append("User permissions reset not needed or failed")
            }
        }

        issuesFound += 2
        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairDisk(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        // Verify and repair APFS snapshots
        let snapshotsResult = try await executor.run("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"])
        if snapshotsResult.success {
            let snapshots = snapshotsResult.stdout.components(separatedBy: .newlines)
                .filter { $0.contains("com.apple.TimeMachine") }
                .compactMap { line -> String? in
                    let parts = line.split(separator: ".")
                    return parts.last.map(String.init)
                }

            if snapshots.count > 10 {
                issuesFound += 1
                if !dryRun {
                    // Thin snapshots
                    let thinResult = try await executor.run("/usr/bin/tmutil", arguments: ["thinlocalsnapshots", "/", "10000000000", "4"])
                    if thinResult.success {
                        issuesFixed += 1
                        details.append("Thinned \(snapshots.count) local snapshots")
                    } else {
                        errors.append("Failed to thin snapshots: \(thinResult.stderr)")
                    }
                }
            }
        }

        // Verify volume
        let verifyResult = try await executor.run("/usr/sbin/diskutil", arguments: ["verifyVolume", "/"])
        if !verifyResult.success {
            issuesFound += 1
            if !dryRun && force {
                // Note: repairVolume requires Recovery Mode
                details.append("Volume errors detected - repair requires Recovery Mode")
            }
        }

        // Enable TRIM if not enabled
        let trimResult = try await executor.run("/usr/sbin/diskutil", arguments: ["info", "/"])
        if trimResult.success, !trimResult.stdout.contains("TRIM Support: Yes") {
            issuesFound += 1
            if !dryRun && force {
                let enableTrim = try await executor.run("/usr/sbin/trimforce", arguments: ["enable"], asRoot: true)
                if enableTrim.success {
                    issuesFixed += 1
                    details.append("TRIM enabled (requires reboot)")
                } else {
                    errors.append("Failed to enable TRIM")
                }
            }
        }

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairCaches(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        let cacheDirs = [
            "/Library/Caches",
            "~/Library/Caches".expandingTildeInPath,
            "/System/Library/Caches",
            "/private/var/folders"
        ]

        for dir in cacheDirs {
            if FileManager.default.fileExists(atPath: dir) {
                issuesFound += 1
                if !dryRun {
                    do {
                        let contents = try FileManager.default.contentsOfDirectory(atPath: dir)
                        for item in contents {
                            let itemPath = (dir as NSString).appendingPathComponent(item)
                            let age = fileUtils.getFileAge(at: itemPath) ?? 0
                            if age > 7 * 24 * 60 * 60 { // older than 7 days
                                if fileUtils.safeRemoveItem(at: itemPath) {
                                    issuesFixed += 1
                                }
                            }
                        }
                        details.append("Cleaned caches in \(dir)")
                    } catch {
                        errors.append("Failed to clean \(dir): \(error)")
                    }
                }
            }
        }

        // Font caches
        let fontCacheDirs = [
            "~/Library/Caches/com.apple.FontRegistry".expandingTildeInPath,
            "/Library/Caches/com.apple.FontRegistry",
            "~/Library/Caches/com.apple.ATS".expandingTildeInPath
        ]

        for dir in fontCacheDirs {
            if FileManager.default.fileExists(atPath: dir) {
                issuesFound += 1
                if !dryRun {
                    if fileUtils.safeRemoveItem(at: dir) {
                        issuesFixed += 1
                        details.append("Cleared font cache: \(dir)")
                    }
                }
            }
        }

        // DNS cache
        if !dryRun {
            let dnsResult = try await executor.run("/usr/bin/sudo", arguments: ["dscacheutil", "-flushcache"])
            if dnsResult.success {
                issuesFixed += 1
                details.append("Flushed DNS cache")
            }
        }
        issuesFound += 1

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairLogs(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        let logDirs = [
            "/var/log",
            "/Library/Logs",
            "~/Library/Logs".expandingTildeInPath,
            "/Library/Logs/DiagnosticReports"
        ]

        for dir in logDirs {
            if FileManager.default.fileExists(atPath: dir) {
                issuesFound += 1
                if !dryRun {
                    do {
                        let contents = try FileManager.default.contentsOfDirectory(atPath: dir)
                        for item in contents {
                            let itemPath = (dir as NSString).appendingPathComponent(item)
                            let age = fileUtils.getFileAge(at: itemPath) ?? 0
                            if age > 30 * 24 * 60 * 60 { // older than 30 days
                                if fileUtils.safeRemoveItem(at: itemPath) {
                                    issuesFixed += 1
                                }
                            }
                        }
                        details.append("Cleaned old logs in \(dir)")
                    } catch {
                        errors.append("Failed to clean \(dir): \(error)")
                    }
                }
            }
        }

        // Rotate system logs
        if !dryRun {
            let aslResult = try await executor.run("/usr/bin/sudo", arguments: ["/usr/sbin/aslmanager", "-c"])
            if aslResult.success {
                issuesFixed += 1
                details.append("Rotated ASL logs")
            }
        }
        issuesFound += 1

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairPreferences(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        // Find corrupt plist files
        let prefsDirs = [
            "~/Library/Preferences".expandingTildeInPath,
            "/Library/Preferences",
            "~/Library/Containers".expandingTildeInPath
        ]

        for dir in prefsDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            let plists = contents.filter { $0.hasSuffix(".plist") }

            for plist in plists {
                let path = (dir as NSString).appendingPathComponent(plist)
                issuesFound += 1

                // Validate plist
                if let data = FileManager.default.contents(atPath: path) {
                    do {
                        _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                    } catch {
                        // Corrupt plist found
                        if !dryRun {
                            let backupPath = "\(path).bak.\(Date().timeIntervalSince1970)"
                            try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
                            if fileUtils.safeRemoveItem(at: path) {
                                issuesFixed += 1
                                details.append("Removed corrupt plist: \(plist) (backed up to \(backupPath))")
                            }
                        } else {
                            details.append("Found corrupt plist: \(plist)")
                        }
                    }
                }
            }
        }

        // Reset cfprefsd
        if !dryRun {
            let cfprefsdResult = try await executor.run("/usr/bin/killall", arguments: ["cfprefsd"])
            if cfprefsdResult.success {
                issuesFixed += 1
                details.append("Restarted cfprefsd")
            }
        }
        issuesFound += 1

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairLaunchd(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

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
                issuesFound += 1

                // Validate plist
                if let data = FileManager.default.contents(atPath: path) {
                    do {
                        let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
                        if dict == nil {
                            throw NSError(domain: "Invalid plist", code: 0)
                        }

                        // Check for common issues
                        if let program = dict?["Program"] as? String {
                            if !FileManager.default.fileExists(atPath: program) {
                                if !dryRun && force {
                                    // Disable the broken launch item
                                    let disableResult = try await executor.run("/bin/launchctl", arguments: ["unload", "-w", path], asRoot: dir.hasPrefix("/Library"))
                                    if disableResult.success {
                                        issuesFixed += 1
                                        details.append("Disabled broken launch item: \(plist)")
                                    }
                                }
                            }
                        }
                    } catch {
                        if !dryRun {
                            let backupPath = "\(path).bak.\(Date().timeIntervalSince1970)"
                            try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
                            if fileUtils.safeRemoveItem(at: path) {
                                issuesFixed += 1
                                details.append("Removed corrupt launch item: \(plist)")
                            }
                        }
                    }
                }
            }
        }

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairSpotlight(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        issuesFound += 1
        if !dryRun {
            // Rebuild Spotlight index
            let mdutilResult = try await executor.run("/usr/bin/sudo", arguments: ["/usr/bin/mdutil", "-E", "/"])
            if mdutilResult.success {
                issuesFixed += 1
                details.append("Spotlight index rebuild initiated")
            } else {
                errors.append("Failed to rebuild Spotlight index: \(mdutilResult.stderr)")
            }
        }

        // Reset metadata stores
        issuesFound += 1
        if !dryRun {
            let mdResult = try await executor.run("/usr/bin/sudo", arguments: ["/usr/bin/mdutil", "-i", "on", "/"])
            if mdResult.success {
                issuesFixed += 1
                details.append("Spotlight indexing enabled")
            }
        }

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairDocker(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        guard await executor.isAvailable("docker") else {
            return (0, 0, [], ["Docker not installed"])
        }

        issuesFound += 1
        if !dryRun {
            // Remove stopped containers
            let containersResult = try await executor.run("docker", arguments: ["container", "prune", "-f"])
            if containersResult.success {
                issuesFixed += 1
                details.append("Removed stopped containers")
            }

            // Remove unused images
            let imagesResult = try await executor.run("docker", arguments: ["image", "prune", "-a", "-f"])
            if imagesResult.success {
                issuesFixed += 1
                details.append("Removed unused images")
            }

            // Remove unused volumes
            let volumesResult = try await executor.run("docker", arguments: ["volume", "prune", "-f"])
            if volumesResult.success {
                issuesFixed += 1
                details.append("Removed unused volumes")
            }

            // Remove build cache
            let builderResult = try await executor.run("docker", arguments: ["builder", "prune", "-a", "-f"])
            if builderResult.success {
                issuesFixed += 1
                details.append("Removed build cache")
            }
        }

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairHomebrew(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        guard await executor.isAvailable("brew") else {
            return (0, 0, [], ["Homebrew not installed"])
        }

        let brewPath = await executor.which("brew") ?? "/opt/homebrew/bin/brew"

        issuesFound += 1
        if !dryRun {
            // Update and upgrade
            let updateResult = try await executor.run(brewPath, arguments: ["update"])
            if updateResult.success {
                issuesFixed += 1
                details.append("Homebrew updated")
            }

            let upgradeResult = try await executor.run(brewPath, arguments: ["upgrade"])
            if upgradeResult.success {
                issuesFixed += 1
                details.append("Homebrew packages upgraded")
            }

            // Cleanup
            let cleanupResult = try await executor.run(brewPath, arguments: ["cleanup", "--prune=all"])
            if cleanupResult.success {
                issuesFixed += 1
                details.append("Homebrew cache cleaned")
            }

            // Doctor
            let doctorResult = try await executor.run(brewPath, arguments: ["doctor"])
            if doctorResult.success {
                issuesFixed += 1
                details.append("Homebrew health check passed")
            }
        }

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairKeychain(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        // Reset login keychain
        let keychainPath = "~/Library/Keychains/login.keychain-db".expandingTildeInPath
        if FileManager.default.fileExists(atPath: keychainPath) {
            issuesFound += 1
            if !dryRun && force {
                let resetResult = try await executor.run("/usr/bin/security", arguments: ["delete-keychain", "login.keychain-db"])
                if resetResult.success {
                    issuesFixed += 1
                    details.append("Login keychain reset (will recreate on next login)")
                }
            }
        }

        // Verify system keychain
        issuesFound += 1
        let verifyResult = try await executor.run("/usr/bin/security", arguments: ["verify-keychain", "/Library/Keychains/System.keychain"])
        if !verifyResult.success {
            if !dryRun && force {
                let repairResult = try await executor.run("/usr/bin/security", arguments: ["repair-keychain", "/Library/Keychains/System.keychain"], asRoot: true)
                if repairResult.success {
                    issuesFixed += 1
                    details.append("System keychain repaired")
                } else {
                    errors.append("Failed to repair system keychain")
                }
            }
        } else {
            issuesFixed += 1
            details.append("System keychain verified OK")
        }

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairTCC(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        // TCC database can only be reset in Recovery Mode
        issuesFound += 1
        if !dryRun && force {
            details.append("TCC reset requires Recovery Mode: 'rm /Library/Application\\ Support/com.apple.TCC/TCC.db'")
        } else {
            details.append("TCC database check - manual reset may be needed in Recovery Mode")
        }

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairFonts(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        issuesFound += 1
        if !dryRun {
            // Clear font caches
            let atsResult = try await executor.run("/usr/bin/atsutil", arguments: ["databases", "-remove"])
            if atsResult.success {
                issuesFixed += 1
                details.append("ATS font databases cleared")
            }

            let serverResult = try await executor.run("/usr/bin/atsutil", arguments: ["server", "-shutdown"])
            if serverResult.success {
                issuesFixed += 1
                details.append("Font server restarted")
            }

            let serverStartResult = try await executor.run("/usr/bin/atsutil", arguments: ["server", "-start"])
            if serverStartResult.success {
                issuesFixed += 1
                details.append("Font server started")
            }
        }

        return (issuesFound, issuesFixed, errors, details)
    }

    private func repairMetadata(dryRun: Bool, force: Bool) async throws -> (Int, Int, [String], [String]) {
        var issuesFound = 0, issuesFixed = 0
        var errors: [String] = []
        var details: [String] = []

        // Clear extended attributes on home directory
        let homeDir = NSHomeDirectory()
        issuesFound += 1
        if !dryRun && force {
            let xattrResult = try await executor.run("/usr/bin/xattr", arguments: ["-cr", homeDir])
            if xattrResult.success {
                issuesFixed += 1
                details.append("Cleared extended attributes on home directory")
            }
        }

        // Rebuild Launch Services database
        issuesFound += 1
        if !dryRun {
            let lsResult = try await executor.run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", arguments: ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])
            if lsResult.success {
                issuesFixed += 1
                details.append("Launch Services database rebuilt")
            }
        }

        return (issuesFound, issuesFixed, errors, details)
    }
}