import Foundation

public final class SystemCleanup: Sendable {
    private let executor = CommandExecutor.shared
    private let fileUtils = FileSystemUtils.self

    public init() {}

    public func runCleanup(
        categories: [CleanupCategory],
        dryRun: Bool = false,
        minAgeDays: Int = 7,
        verbose: Bool = false
    ) async throws -> CleanupSummary {
        let startTime = Date()
        var results: [CleanupResult] = []

        for category in categories {
            let result = try await runCategoryCleanup(category, dryRun: dryRun, minAgeDays: minAgeDays, verbose: verbose)
            results.append(result)
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let totalBytesFreed = results.reduce(0) { $0 + $1.bytesFreed }
        let totalItemsCleaned = results.reduce(0) { $0 + $1.itemsCount }

        return CleanupSummary(
            results: results,
            totalBytesFreed: totalBytesFreed,
            totalItemsCleaned: totalItemsCleaned,
            totalDuration: totalDuration
        )
    }

    private func runCategoryCleanup(
        _ category: CleanupCategory,
        dryRun: Bool,
        minAgeDays: Int,
        verbose: Bool
    ) async throws -> CleanupResult {
        let startTime = Date()
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        switch category {
        case .user:
            (bytesFreed, itemsCount, errors, details) = try await cleanupUserCaches(dryRun: dryRun, minAgeDays: minAgeDays)
        case .system:
            (bytesFreed, itemsCount, errors, details) = try await cleanupSystemCaches(dryRun: dryRun, minAgeDays: minAgeDays)
        case .apps:
            (bytesFreed, itemsCount, errors, details) = try await cleanupAppCaches(dryRun: dryRun, minAgeDays: minAgeDays)
        case .docker:
            (bytesFreed, itemsCount, errors, details) = try await cleanupDocker(dryRun: dryRun)
        case .xcode:
            (bytesFreed, itemsCount, errors, details) = try await cleanupXcode(dryRun: dryRun)
        case .node:
            (bytesFreed, itemsCount, errors, details) = try await cleanupNode(dryRun: dryRun)
        case .python:
            (bytesFreed, itemsCount, errors, details) = try await cleanupPython(dryRun: dryRun)
        case .rust:
            (bytesFreed, itemsCount, errors, details) = try await cleanupRust(dryRun: dryRun)
        case .go:
            (bytesFreed, itemsCount, errors, details) = try await cleanupGo(dryRun: dryRun)
        case .java:
            (bytesFreed, itemsCount, errors, details) = try await cleanupJava(dryRun: dryRun)
        case .browsers:
            (bytesFreed, itemsCount, errors, details) = try await cleanupBrowsers(dryRun: dryRun)
        case .mail:
            (bytesFreed, itemsCount, errors, details) = try await cleanupMail(dryRun: dryRun)
        case .trash:
            (bytesFreed, itemsCount, errors, details) = try await cleanupTrash(dryRun: dryRun)
        }

        let duration = Date().timeIntervalSince(startTime)
        return CleanupResult(
            category: category,
            bytesFreed: bytesFreed,
            itemsCount: itemsCount,
            errors: errors,
            details: details,
            duration: duration
        )
    }

    // MARK: - Cleanup Implementations

    private func cleanupUserCaches(dryRun: Bool, minAgeDays: Int) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        let cacheDirs = [
            "~/Library/Caches".expandingTildeInPath,
            "~/Library/Logs".expandingTildeInPath,
            "~/Library/Containers".expandingTildeInPath,
            "~/Library/Application Support/CrashReporter".expandingTildeInPath,
            "~/Library/Saved Application State".expandingTildeInPath
        ]

        for dir in cacheDirs {
            let (freed, count, errs, dets) = try cleanDirectory(dir, dryRun: dryRun, minAgeDays: minAgeDays, exclude: ["com.apple.", "CloudDocs"])
            bytesFreed += freed
            itemsCount += count
            errors.append(contentsOf: errs)
            details.append(contentsOf: dets)
        }

        // Clean user temp
        let tempDir = NSTemporaryDirectory()
        let (tFreed, tCount, tErrs, tDets) = try cleanDirectory(tempDir, dryRun: dryRun, minAgeDays: minAgeDays)
        bytesFreed += tFreed
        itemsCount += tCount
        errors.append(contentsOf: tErrs)
        details.append(contentsOf: tDets)

        return (bytesFreed, itemsCount, errors, details)
    }

    private func cleanupSystemCaches(dryRun: Bool, minAgeDays: Int) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        let cacheDirs = [
            "/Library/Caches",
            "/System/Library/Caches",
            "/var/log",
            "/Library/Logs",
            "/private/var/folders"
        ]

        for dir in cacheDirs {
            let (freed, count, errs, dets) = try cleanDirectory(dir, dryRun: dryRun, minAgeDays: minAgeDays, exclude: [], asRoot: true)
            bytesFreed += freed
            itemsCount += count
            errors.append(contentsOf: errs)
            details.append(contentsOf: dets)
        }

        // Rotate system logs
        if !dryRun {
            let aslResult = try await executor.run("/usr/bin/sudo", arguments: ["/usr/sbin/aslmanager", "-c"])
            if aslResult.success {
                details.append(CleanupDetail(path: "ASL logs", bytesFreed: 0, itemsCount: 1))
            }
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func cleanupAppCaches(dryRun: Bool, minAgeDays: Int) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        // Common app cache locations
        let appCacheDirs = [
            "~/Library/Application Support".expandingTildeInPath,
            "/Library/Application Support"
        ]

        for dir in appCacheDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents {
                let itemPath = (dir as NSString).appendingPathComponent(item)
                let cachePath = (itemPath as NSString).appendingPathComponent("Caches")
                if FileManager.default.fileExists(atPath: cachePath) {
                    let (freed, count, errs, dets) = try cleanDirectory(cachePath, dryRun: dryRun, minAgeDays: minAgeDays)
                    bytesFreed += freed
                    itemsCount += count
                    errors.append(contentsOf: errs)
                    details.append(contentsOf: dets)
                }
            }
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func cleanupDocker(dryRun: Bool) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        guard await executor.isAvailable("docker") else {
            return (0, 0, ["Docker not installed"], [])
        }

        if !dryRun {
            // Prune everything
            let pruneResult = try await executor.run("docker", arguments: ["system", "prune", "-a", "--volumes", "-f"])
            if pruneResult.success {
                itemsCount += 1
                details.append(CleanupDetail(path: "Docker system prune", bytesFreed: 0, itemsCount: 1))
            } else {
                errors.append("Docker prune failed: \(pruneResult.stderr)")
            }

            // Also clean builder cache
            let builderResult = try await executor.run("docker", arguments: ["builder", "prune", "-a", "-f"])
            if builderResult.success {
                details.append(CleanupDetail(path: "Docker builder cache", bytesFreed: 0, itemsCount: 1))
            }
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func cleanupXcode(dryRun: Bool) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        let xcodeDirs = [
            "~/Library/Developer/Xcode/DerivedData".expandingTildeInPath,
            "~/Library/Developer/Xcode/Archives".expandingTildeInPath,
            "~/Library/Developer/Xcode/iOS DeviceSupport".expandingTildeInPath,
            "~/Library/Developer/CoreSimulator/Caches".expandingTildeInPath,
            "~/Library/Developer/CoreSimulator/Devices".expandingTildeInPath
        ]

        for dir in xcodeDirs {
            if FileManager.default.fileExists(atPath: dir) {
                let (freed, count, errs, dets) = try cleanDirectory(dir, dryRun: dryRun, minAgeDays: 30)
                bytesFreed += freed
                itemsCount += count
                errors.append(contentsOf: errs)
                details.append(contentsOf: dets)
            }
        }

        // Clean simulator devices that are unavailable
        if !dryRun {
            let simResult = try await executor.run("xcrun", arguments: ["simctl", "delete", "unavailable"])
            if simResult.success {
                itemsCount += 1
                details.append(CleanupDetail(path: "Unavailable simulators", bytesFreed: 0, itemsCount: 1))
            }
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func cleanupNode(dryRun: Bool) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        // npm cache
        let hasNpm = await executor.isAvailable("npm")
        if hasNpm {
            if !dryRun {
                let npmResult = try await executor.run("npm", arguments: ["cache", "clean", "--force"])
                if npmResult.success {
                    itemsCount += 1
                    details.append(CleanupDetail(path: "npm cache", bytesFreed: 0, itemsCount: 1))
                }
            }
        }

        // yarn cache
        let hasYarn = await executor.isAvailable("yarn")
        if hasYarn {
            if !dryRun {
                let yarnResult = try await executor.run("yarn", arguments: ["cache", "clean"])
                if yarnResult.success {
                    itemsCount += 1
                    details.append(CleanupDetail(path: "yarn cache", bytesFreed: 0, itemsCount: 1))
                }
            }
        }

        // pnpm cache
        let hasPnpm = await executor.isAvailable("pnpm")
        if hasPnpm {
            if !dryRun {
                let pnpmResult = try await executor.run("pnpm", arguments: ["store", "prune"])
                if pnpmResult.success {
                    itemsCount += 1
                    details.append(CleanupDetail(path: "pnpm store", bytesFreed: 0, itemsCount: 1))
                }
            }
        }

        // node_modules cleanup (optional - can be large)
        let homeDir = NSHomeDirectory()
        let nodeModulesDirs = [
            "\(homeDir)/node_modules",
            "\(homeDir)/.npm",
            "\(homeDir)/.yarn",
            "\(homeDir)/.pnpm-store"
        ]

        for dir in nodeModulesDirs {
            if FileManager.default.fileExists(atPath: dir) {
                let (freed, count, errs, dets) = try cleanDirectory(dir, dryRun: dryRun, minAgeDays: 30)
                bytesFreed += freed
                itemsCount += count
                errors.append(contentsOf: errs)
                details.append(contentsOf: dets)
            }
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func cleanupPython(dryRun: Bool) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        // pip cache
        let hasPip = await executor.isAvailable("pip")
        let hasPip3 = await executor.isAvailable("pip3")
        if hasPip || hasPip3 {
            let pipCmd = await executor.which("pip3") ?? "pip"
            if !dryRun {
                let pipResult = try await executor.run(pipCmd, arguments: ["cache", "purge"])
                if pipResult.success {
                    itemsCount += 1
                    details.append(CleanupDetail(path: "pip cache", bytesFreed: 0, itemsCount: 1))
                }
            }
        }

        // pipx cache
        let hasPipx = await executor.isAvailable("pipx")
        if hasPipx {
            if !dryRun {
                let pipxResult = try await executor.run("pipx", arguments: ["cache", "purge"])
                if pipxResult.success {
                    itemsCount += 1
                    details.append(CleanupDetail(path: "pipx cache", bytesFreed: 0, itemsCount: 1))
                }
            }
        }

        // conda cache
        let hasConda = await executor.isAvailable("conda")
        if hasConda {
            if !dryRun {
                let condaResult = try await executor.run("conda", arguments: ["clean", "--all", "-y"])
                if condaResult.success {
                    itemsCount += 1
                    details.append(CleanupDetail(path: "conda cache", bytesFreed: 0, itemsCount: 1))
                }
            }
        }

        // Poetry cache
        let hasPoetry = await executor.isAvailable("poetry")
        if hasPoetry {
            if !dryRun {
                let poetryResult = try await executor.run("poetry", arguments: ["cache", "clear", "--all", "pypi"])
                if poetryResult.success {
                    itemsCount += 1
                    details.append(CleanupDetail(path: "poetry cache", bytesFreed: 0, itemsCount: 1))
                }
            }
        }

        // __pycache__ directories
        let homeDir = NSHomeDirectory()
        let pycacheDirs = findPycacheDirs(homeDir)
        for dir in pycacheDirs {
            let (freed, count, errs, dets) = try cleanDirectory(dir, dryRun: dryRun, minAgeDays: 7)
            bytesFreed += freed
            itemsCount += count
            errors.append(contentsOf: errs)
            details.append(contentsOf: dets)
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func findPycacheDirs(_ root: String) -> [String] {
        var dirs: [String] = []
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return dirs }

        for case let file as String in enumerator {
            if file.hasSuffix("__pycache__") {
                dirs.append((root as NSString).appendingPathComponent(file))
            }
        }
        return dirs
    }

    private func cleanupRust(dryRun: Bool) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        let hasCargo = await executor.isAvailable("cargo")
        if hasCargo {
            if !dryRun {
                let cargoResult = try await executor.run("cargo", arguments: ["clean"])
                if cargoResult.success {
                    itemsCount += 1
                    details.append(CleanupDetail(path: "cargo clean", bytesFreed: 0, itemsCount: 1))
                }

                // Also clean registry cache
                let registryResult = try await executor.run("cargo", arguments: ["clean", "--registry"])
                if registryResult.success {
                    details.append(CleanupDetail(path: "cargo registry", bytesFreed: 0, itemsCount: 1))
                }
            }
        }

        // ~/.cargo directory
        let cargoDir = "~/.cargo".expandingTildeInPath
        if FileManager.default.fileExists(atPath: cargoDir) {
let (freed, count, errs, dets) = try cleanDirectory(
            (cargoDir as NSString).appendingPathComponent("registry/cache"),
            dryRun: dryRun,
                minAgeDays: 30
            )
            bytesFreed += freed
            itemsCount += count
            errors.append(contentsOf: errs)
            details.append(contentsOf: dets)
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func cleanupGo(dryRun: Bool) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        let bytesFreed: Int64 = 0
        var itemsCount = 0
        let errors: [String] = []
        var details: [CleanupDetail] = []

        let hasGo = await executor.isAvailable("go")
        if hasGo {
            if !dryRun {
                // Clean module cache
                let modResult = try await executor.run("go", arguments: ["clean", "-modcache"])
                if modResult.success {
                    itemsCount += 1
                    details.append(CleanupDetail(path: "Go module cache", bytesFreed: 0, itemsCount: 1))
                }

                // Clean build cache
                let buildResult = try await executor.run("go", arguments: ["clean", "-cache"])
                if buildResult.success {
                    itemsCount += 1
                    details.append(CleanupDetail(path: "Go build cache", bytesFreed: 0, itemsCount: 1))
                }
            }
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func cleanupJava(dryRun: Bool) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        // Maven cache
        let mavenDir = "~/.m2/repository".expandingTildeInPath
        if FileManager.default.fileExists(atPath: mavenDir) {
            let (freed, count, errs, dets) = try cleanDirectory(mavenDir, dryRun: dryRun, minAgeDays: 60)
            bytesFreed += freed
            itemsCount += count
            errors.append(contentsOf: errs)
            details.append(contentsOf: dets)
        }

        // Gradle cache
        let gradleDir = "~/.gradle/caches".expandingTildeInPath
        if FileManager.default.fileExists(atPath: gradleDir) {
            let (freed, count, errs, dets) = try cleanDirectory(gradleDir, dryRun: dryRun, minAgeDays: 30)
            bytesFreed += freed
            itemsCount += count
            errors.append(contentsOf: errs)
            details.append(contentsOf: dets)
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func cleanupBrowsers(dryRun: Bool) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        let browserCaches = [
            "~/Library/Caches/com.apple.Safari".expandingTildeInPath,
            "~/Library/Caches/Google/Chrome".expandingTildeInPath,
            "~/Library/Caches/Firefox".expandingTildeInPath,
            "~/Library/Caches/com.microsoft.edgemac".expandingTildeInPath,
            "~/Library/Caches/com.brave.Browser".expandingTildeInPath,
            "~/Library/Application Support/Google/Chrome/Default/Cache".expandingTildeInPath,
            "~/Library/Application Support/Firefox/Profiles".expandingTildeInPath
        ]

        for dir in browserCaches {
            if FileManager.default.fileExists(atPath: dir) {
let (freed, count, errs, dets) = try cleanDirectory(dir, dryRun: dryRun, minAgeDays: 7)
                bytesFreed += freed
                itemsCount += count
                errors.append(contentsOf: errs)
                details.append(contentsOf: dets)
            }
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func cleanupMail(dryRun: Bool) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        let mailDirs = [
            "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads".expandingTildeInPath,
            "~/Library/Mail/V*/MailData/Envelope Index".expandingTildeInPath
        ]

        for dir in mailDirs {
            // Handle glob patterns
            let expanded = expandGlob(dir)
            for expandedDir in expanded {
                if FileManager.default.fileExists(atPath: expandedDir) {
                    let (freed, count, errs, dets) = try cleanDirectory(expandedDir, dryRun: dryRun, minAgeDays: 30)
                    bytesFreed += freed
                    itemsCount += count
                    errors.append(contentsOf: errs)
                    details.append(contentsOf: dets)
                }
            }
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    private func expandGlob(_ pattern: String) -> [String] {
        // Simple glob expansion for * in path
        if !pattern.contains("*") {
            return [pattern]
        }

        var results: [String] = []
        let parts = pattern.split(separator: "/", omittingEmptySubsequences: false)
        var currentPath = "/"

        for part in parts {
            if part.contains("*") {
                let parent = currentPath
                let patternStr = String(part)
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: parent) {
                    let regex = patternStr.replacingOccurrences(of: "*", with: ".*")
                    let compiled = try? NSRegularExpression(pattern: "^\(regex)$")
                    for item in contents {
                        if compiled?.firstMatch(in: item, options: [], range: NSRange(location: 0, length: item.utf16.count)) != nil {
                            results.append((parent as NSString).appendingPathComponent(item))
                        }
                    }
                }
                currentPath = results.first ?? currentPath
            } else {
                currentPath = (currentPath as NSString).appendingPathComponent(String(part))
            }
        }

        return results.isEmpty ? [pattern] : results
    }

    private func cleanupTrash(dryRun: Bool) async throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        let trashDir = "~/.Trash".expandingTildeInPath
        if FileManager.default.fileExists(atPath: trashDir) {
            let (freed, count, errs, dets) = try cleanDirectory(trashDir, dryRun: dryRun, minAgeDays: 30)
            bytesFreed += freed
            itemsCount += count
            errors.append(contentsOf: errs)
            details.append(contentsOf: dets)
        }

        // Also clean .Trash on other volumes
        let volumesDir = "/Volumes"
        if let volumes = try? FileManager.default.contentsOfDirectory(atPath: volumesDir) {
            for volume in volumes {
                let volumeTrash = "/Volumes/\(volume)/.Trash"
                if FileManager.default.fileExists(atPath: volumeTrash) {
                    let (freed, count, errs, dets) = try cleanDirectory(volumeTrash, dryRun: dryRun, minAgeDays: 30, asRoot: true)
                    bytesFreed += freed
                    itemsCount += count
                    errors.append(contentsOf: errs)
                    details.append(contentsOf: dets)
                }
            }
        }

        return (bytesFreed, itemsCount, errors, details)
    }

    // MARK: - Helper Functions

    private func cleanDirectory(
        _ path: String,
        dryRun: Bool,
        minAgeDays: Int,
        exclude: [String] = [],
        asRoot: Bool = false
    ) throws -> (Int64, Int, [String], [CleanupDetail]) {
        var bytesFreed: Int64 = 0
        var itemsCount = 0
        var errors: [String] = []
        var details: [CleanupDetail] = []

        guard FileManager.default.fileExists(atPath: path) else {
            return (0, 0, [], [])
        }

        let minAge = TimeInterval(minAgeDays * 24 * 60 * 60)

        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return (0, 0, [], [])
        }

        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                let isDir = values.isDirectory ?? false
                let fileSize = values.fileSize ?? 0
                let modDate = values.contentModificationDate ?? Date.distantPast

                // Skip directories for size calculation
                if isDir { continue }

                // Check exclude patterns
                let relativePath = fileURL.path.replacingOccurrences(of: path + "/", with: "")
                let excluded = exclude.contains { relativePath.hasPrefix($0) }
                if excluded { continue }

                // Check age
                let age = Date().timeIntervalSince(modDate)
                if age < minAge { continue }

                if !dryRun {
                    if fileUtils.safeRemoveItem(at: fileURL.path) {
                        bytesFreed += Int64(fileSize)
                        itemsCount += 1
                    }
                } else {
                    bytesFreed += Int64(fileSize)
                    itemsCount += 1
                }

            } catch {
                errors.append("Error processing \(fileURL.path): \(error)")
            }
        }

        if itemsCount > 0 || bytesFreed > 0 {
            details.append(CleanupDetail(
                path: path,
                bytesFreed: bytesFreed,
                itemsCount: itemsCount
            ))
        }

        return (bytesFreed, itemsCount, errors, details)
    }
}