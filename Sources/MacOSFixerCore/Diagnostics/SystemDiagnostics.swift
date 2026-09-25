import Foundation
import SystemPackage

public final class SystemDiagnostics: Sendable {
    private let executor = CommandExecutor.shared
    private let fileUtils = FileSystemUtils.self

    public init() {}

    public func runFullDiagnostics(detailed: Bool = false) async throws -> DiagnosticReport {
        let startTime = Date()
        var categories: [CategoryDiagnostic] = []

        // Run all diagnostic categories in parallel
        async let hardware = runHardwareDiagnostics(detailed: detailed)
        async let disk = runDiskDiagnostics(detailed: detailed)
        async let memory = runMemoryDiagnostics(detailed: detailed)
        async let network = runNetworkDiagnostics(detailed: detailed)
        async let software = runSoftwareDiagnostics(detailed: detailed)
        async let security = runSecurityDiagnostics(detailed: detailed)
        async let performance = runPerformanceDiagnostics(detailed: detailed)
        async let logs = runLogDiagnostics(detailed: detailed)
        async let launch = runLaunchDiagnostics(detailed: detailed)
        async let tcc = runTCCDiagnostics(detailed: detailed)

        categories.append(try await hardware)
        categories.append(try await disk)
        categories.append(try await memory)
        categories.append(try await network)
        categories.append(try await software)
        categories.append(try await security)
        categories.append(try await performance)
        categories.append(try await logs)
        categories.append(try await launch)
        categories.append(try await tcc)

        let duration = Date().timeIntervalSince(startTime)

        let allIssues = categories.flatMap { $0.issues }
        let criticalCount = allIssues.filter { $0.severity == .critical }.count
        let warningCount = allIssues.filter { $0.severity == .warning }.count
        let infoCount = allIssues.filter { $0.severity == .info }.count
        let passedCategories = categories.filter { $0.status == "PASS" }.count

        let summary = DiagnosticSummary(
            totalCategories: categories.count,
            passedCategories: passedCategories,
            failedCategories: categories.count - passedCategories,
            totalIssues: allIssues.count,
            criticalIssues: criticalCount,
            warningIssues: warningCount,
            infoIssues: infoCount
        )

        return DiagnosticReport(
            timestamp: Date(),
            duration: duration,
            categories: categories,
            summary: summary
        )
    }

    // MARK: - Hardware Diagnostics

    private func runHardwareDiagnostics(detailed: Bool) async throws -> CategoryDiagnostic {
        var issues: [DiagnosticIssue] = []
        var metrics: [String: Double] = [:]
        let startTime = Date()

        // CPU Info
        do {
            let cpuResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "machdep.cpu.brand_string"])
            if cpuResult.success {
                metrics["cpu_brand"] = 0 // placeholder
            }
        } catch {
            issues.append(DiagnosticIssue(
                category: "Hardware",
                severity: .warning,
                title: "CPU Info Unavailable",
                description: "Could not retrieve CPU brand string",
                suggestion: "Check sysctl permissions"
            ))
        }

        // Core count
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        metrics["core_count"] = Double(coreCount)

        // Memory
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        metrics["total_memory_gb"] = Double(totalMemory) / (1024 * 1024 * 1024)

        // Thermal state
        let thermalResult = try await executor.run("/usr/sbin/pmset", arguments: ["-g", "therm"])
        if thermalResult.success, thermalResult.stdout.contains("Throttling") {
            issues.append(DiagnosticIssue(
                category: "Hardware",
                severity: .warning,
                title: "Thermal Throttling Detected",
                description: "System is experiencing thermal throttling",
                suggestion: "Check cooling, clean dust, verify fan operation"
            ))
        }

        // Battery (if laptop)
        let batteryResult = try await executor.run("/usr/bin/pmset", arguments: ["-g", "batt"])
        if batteryResult.success {
            if batteryResult.stdout.contains("Condition: Poor") || batteryResult.stdout.contains("Replace") {
                issues.append(DiagnosticIssue(
                    category: "Hardware",
                    severity: .warning,
                    title: "Battery Health Degraded",
                    description: "Battery condition indicates replacement needed",
                    suggestion: "Run 'pmset -g batt' for details, consider battery replacement"
                ))
            }
        }

        if detailed {
            // SMART status for all disks
            let diskUtilResult = try await executor.run("/usr/sbin/diskutil", arguments: ["list"])
            if diskUtilResult.success {
                let disks = parseDiskList(diskUtilResult.stdout)
                for disk in disks {
                    let smartResult = try await executor.run("/usr/sbin/smartctl", arguments: ["-H", disk])
                    if smartResult.success {
                        if smartResult.stdout.contains("PASSED") {
                            metrics["smart_\(disk.replacingOccurrences(of: "/", with: "_"))"] = 1
                        } else if smartResult.stdout.contains("FAILED") {
                            issues.append(DiagnosticIssue(
                                category: "Hardware",
                                severity: .critical,
                                title: "SMART Failure: \(disk)",
                                description: "Disk SMART health check failed",
                                path: disk,
                                suggestion: "Backup immediately and replace drive"
                            ))
                        }
                    }
                }
            }
        }

        let status = issues.filter { $0.severity == .critical }.isEmpty ? "PASS" : "FAIL"

        return CategoryDiagnostic(
            name: "Hardware",
            status: status,
            issues: issues,
            metrics: metrics,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    private func parseDiskList(_ output: String) -> [String] {
        let lines = output.components(separatedBy: .newlines)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("/dev/disk") && !trimmed.contains("synthesized") {
                let parts = trimmed.split(separator: " ")
                return String(parts[0])
            }
            return nil
        }
    }

    // MARK: - Disk Diagnostics

    private func runDiskDiagnostics(detailed: Bool) async throws -> CategoryDiagnostic {
        var issues: [DiagnosticIssue] = []
        var metrics: [String: Double] = [:]
        let startTime = Date()

        // APFS Container check
        let apfsResult = try await executor.run("/usr/sbin/diskutil", arguments: ["apfs", "list"])
        if apfsResult.success {
            let containers = parseAPFSContainers(apfsResult.stdout)
            for container in containers {
                metrics["apfs_container_\(container.identifier)_free_gb"] = container.freeSpaceGB
                metrics["apfs_container_\(container.identifier)_used_gb"] = container.usedSpaceGB

                let usagePercent = (container.usedSpaceGB / container.totalSpaceGB) * 100
                if usagePercent > 90 {
                    issues.append(DiagnosticIssue(
                        category: "Disk",
                        severity: .critical,
                        title: "Disk Critical: \(container.mountPoint) at \(Int(usagePercent))%",
                        description: "APFS container \(container.identifier) is critically full",
                        path: container.mountPoint,
                        suggestion: "Free up space immediately",
                        autoFixable: true
                    ))
                } else if usagePercent > 80 {
                    issues.append(DiagnosticIssue(
                        category: "Disk",
                        severity: .warning,
                        title: "Disk Warning: \(container.mountPoint) at \(Int(usagePercent))%",
                        description: "APFS container \(container.identifier) is running low on space",
                        path: container.mountPoint,
                        suggestion: "Clean caches, remove old files",
                        autoFixable: true
                    ))
                }
            }
        }

        // Check for filesystem errors
        let fsckResult = try await executor.run("/usr/sbin/diskutil", arguments: ["verifyVolume", "/"])
        if !fsckResult.success || fsckResult.stdout.contains("error") {
            issues.append(DiagnosticIssue(
                category: "Disk",
                severity: .critical,
                title: "Root Filesystem Errors",
                description: "Filesystem verification found errors on root volume",
                suggestion: "Run 'diskutil repairVolume /' in Recovery Mode",
                autoFixable: false
            ))
        }

        // Trim support
        let trimResult = try await executor.run("/usr/sbin/diskutil", arguments: ["info", "/"])
        if trimResult.success {
            let trimEnabled = trimResult.stdout.contains("TRIM Support: Yes") || trimResult.stdout.contains("Solid State: Yes")
            metrics["trim_enabled"] = trimEnabled ? 1 : 0
            if !trimEnabled {
                issues.append(DiagnosticIssue(
                    category: "Disk",
                    severity: .info,
                    title: "TRIM Not Enabled",
                    description: "TRIM support not detected on boot volume",
                    suggestion: "Enable with 'sudo trimforce enable' (requires reboot)"
                ))
            }
        }

        // Snapshot count
        let snapshotsResult = try await executor.run("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"])
        if snapshotsResult.success {
            let snapshotCount = snapshotsResult.stdout.components(separatedBy: .newlines).filter { $0.contains("com.apple.TimeMachine") }.count
            metrics["local_snapshots"] = Double(snapshotCount)
            if snapshotCount > 20 {
                issues.append(DiagnosticIssue(
                    category: "Disk",
                    severity: .warning,
                    title: "Many Local Snapshots",
                    description: "\(snapshotCount) local TimeMachine snapshots consuming space",
                    suggestion: "Run 'tmutil thinlocalsnapshots / 10000000000 4' to thin"
                ))
            }
        }

        let status = issues.filter { $0.severity == .critical }.isEmpty ? "PASS" : "FAIL"

        return CategoryDiagnostic(
            name: "Disk",
            status: status,
            issues: issues,
            metrics: metrics,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    private struct APFSContainer {
        let identifier: String
        let mountPoint: String
        let totalSpaceGB: Double
        let usedSpaceGB: Double
        let freeSpaceGB: Double
    }

    private func parseAPFSContainers(_ output: String) -> [APFSContainer] {
        var containers: [APFSContainer] = []
        let lines = output.components(separatedBy: .newlines)
        var currentContainer: APFSContainer?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("APFS Container") {
                if let c = currentContainer { containers.append(c) }
                let parts = trimmed.split(separator: " ")
                currentContainer = APFSContainer(
                    identifier: String(parts.last ?? ""),
                    mountPoint: "",
                    totalSpaceGB: 0,
                    usedSpaceGB: 0,
                    freeSpaceGB: 0
                )
            } else if trimmed.hasPrefix("Size (Total):") && currentContainer != nil {
                let gb = parseSizeGB(trimmed)
                currentContainer = APFSContainer(
                    identifier: currentContainer!.identifier,
                    mountPoint: currentContainer!.mountPoint,
                    totalSpaceGB: gb,
                    usedSpaceGB: currentContainer!.usedSpaceGB,
                    freeSpaceGB: currentContainer!.freeSpaceGB
                )
            } else if trimmed.hasPrefix("Size (Used):") && currentContainer != nil {
                let gb = parseSizeGB(trimmed)
                currentContainer = APFSContainer(
                    identifier: currentContainer!.identifier,
                    mountPoint: currentContainer!.mountPoint,
                    totalSpaceGB: currentContainer!.totalSpaceGB,
                    usedSpaceGB: gb,
                    freeSpaceGB: currentContainer!.freeSpaceGB
                )
            } else if trimmed.hasPrefix("Mount Point:") && currentContainer != nil {
                let parts = trimmed.split(separator: ":")
                if parts.count > 1 {
                    let mp = parts[1].trimmingCharacters(in: .whitespaces)
                    currentContainer = APFSContainer(
                        identifier: currentContainer!.identifier,
                        mountPoint: mp,
                        totalSpaceGB: currentContainer!.totalSpaceGB,
                        usedSpaceGB: currentContainer!.usedSpaceGB,
                        freeSpaceGB: currentContainer!.freeSpaceGB
                    )
                }
            }
        }
        if let c = currentContainer { containers.append(c) }
        return containers
    }

    private func parseSizeGB(_ line: String) -> Double {
        let pattern = #"\((\d+) Bytes\)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: line.utf16.count)
        if let match = regex?.firstMatch(in: line, options: [], range: range),
           let range = Range(match.range(at: 1), in: line),
           let bytes = Int64(line[range]) {
            return Double(bytes) / (1024 * 1024 * 1024)
        }
        return 0
    }

    // MARK: - Memory Diagnostics

    private func runMemoryDiagnostics(detailed: Bool) async throws -> CategoryDiagnostic {
        var issues: [DiagnosticIssue] = []
        var metrics: [String: Double] = [:]
        let startTime = Date()

        let vmStatResult = try await executor.run("/usr/bin/vm_stat")
        if vmStatResult.success {
            let mem = await parseVMStat(vmStatResult.stdout)
            metrics["pages_free"] = Double(mem.free)
            metrics["pages_active"] = Double(mem.active)
            metrics["pages_inactive"] = Double(mem.inactive)
            metrics["pages_wired"] = Double(mem.wired)
            metrics["pages_compressed"] = Double(mem.compressed)
            metrics["swap_used_mb"] = Double(mem.swapUsed) / (1024 * 1024)

            let totalPages = mem.free + mem.active + mem.inactive + mem.wired + mem.compressed
            let usedPercent = Double(totalPages - mem.free) / Double(totalPages) * 100
            metrics["memory_usage_percent"] = usedPercent

            if usedPercent > 90 {
                issues.append(DiagnosticIssue(
                    category: "Memory",
                    severity: .critical,
                    title: "Memory Pressure Critical",
                    description: "Memory usage at \(Int(usedPercent))%",
                    suggestion: "Close applications, check for memory leaks"
                ))
            } else if usedPercent > 80 {
                issues.append(DiagnosticIssue(
                    category: "Memory",
                    severity: .warning,
                    title: "Memory Pressure High",
                    description: "Memory usage at \(Int(usedPercent))%",
                    suggestion: "Consider closing unused applications"
                ))
            }

            if mem.swapUsed > 1024 * 1024 * 1024 { // > 1GB swap
                issues.append(DiagnosticIssue(
                    category: "Memory",
                    severity: .warning,
                    title: "High Swap Usage",
                    description: "Swap usage: \(ByteCountFormatter.string(fromByteCount: mem.swapUsed, countStyle: .file))",
                    suggestion: "System is swapping heavily, consider more RAM"
                ))
            }
        }

        // Memory pressure
        let pressureResult = try await executor.run("/usr/bin/memory_pressure")
        if pressureResult.success {
            let pressure = parseMemoryPressure(pressureResult.stdout)
            metrics["memory_pressure_level"] = pressure.level
            if pressure.level >= 3 {
                issues.append(DiagnosticIssue(
                    category: "Memory",
                    severity: .critical,
                    title: "Memory Pressure: \(pressure.description)",
                    description: "System memory pressure is critical",
                    suggestion: "Immediate action required - close apps or restart"
                ))
            }
        }

        let status = issues.filter { $0.severity == .critical }.isEmpty ? "PASS" : "FAIL"

        return CategoryDiagnostic(
            name: "Memory",
            status: status,
            issues: issues,
            metrics: metrics,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    private struct VMStat {
        let free: Int
        let active: Int
        let inactive: Int
        let wired: Int
        let compressed: Int
        let swapUsed: Int64
    }

    private func parseVMStat(_ output: String) async -> VMStat {
        var free = 0, active = 0, inactive = 0, wired = 0, compressed = 0
        var swapUsed: Int64 = 0

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("Pages free:") {
                free = extractNumber(from: line) ?? 0
            } else if line.contains("Pages active:") {
                active = extractNumber(from: line) ?? 0
            } else if line.contains("Pages inactive:") {
                inactive = extractNumber(from: line) ?? 0
            } else if line.contains("Pages wired down:") {
                wired = extractNumber(from: line) ?? 0
            } else if line.contains("Pages occupied by compressor:") {
                compressed = extractNumber(from: line) ?? 0
            }
        }

        // Get swap usage from sysctl
        do {
            let swapResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "vm.swapusage"])
            if swapResult.success {
                swapUsed = parseSwapUsage(swapResult.stdout)
            }
        } catch {
            // Ignore error
        }

        return VMStat(free: free, active: active, inactive: inactive, wired: wired, compressed: compressed, swapUsed: swapUsed)
    }

    private func extractNumber(from line: String) -> Int? {
        let parts = line.split(separator: " ")
        for part in parts {
            if let num = Int(part.replacingOccurrences(of: ".", with: "")) {
                return num
            }
        }
        return nil
    }

    private func parseSwapUsage(_ output: String) -> Int64 {
        // "total = 2048.00M  used = 128.00M  free = 1920.00M"
        let pattern = #"used = ([\d.]+)([KMGT]?)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: output.utf16.count)
        if let match = regex?.firstMatch(in: output, options: [], range: range),
           let valueRange = Range(match.range(at: 1), in: output),
           let unitRange = Range(match.range(at: 2), in: output) {
            let value = Double(output[valueRange]) ?? 0
            let unit = String(output[unitRange])
            let multiplier: Double
            switch unit {
            case "K": multiplier = 1024
            case "M": multiplier = 1024 * 1024
            case "G": multiplier = 1024 * 1024 * 1024
            case "T": multiplier = 1024 * 1024 * 1024 * 1024
            default: multiplier = 1
            }
            return Int64(value * multiplier)
        }
        return 0
    }

    private struct MemoryPressure {
        let level: Double
        let description: String
    }

    private func parseMemoryPressure(_ output: String) -> MemoryPressure {
        var level: Double = 0
        var desc = "Normal"

        if output.contains("The system has no memory pressure") {
            level = 0
            desc = "Normal"
        } else if output.contains("The system is under moderate memory pressure") {
            level = 1
            desc = "Moderate"
        } else if output.contains("The system is under severe memory pressure") {
            level = 2
            desc = "Severe"
        } else if output.contains("The system is under critical memory pressure") {
            level = 3
            desc = "Critical"
        }

        return MemoryPressure(level: level, description: desc)
    }

    // MARK: - Network Diagnostics

    private func runNetworkDiagnostics(detailed: Bool) async throws -> CategoryDiagnostic {
        var issues: [DiagnosticIssue] = []
        var metrics: [String: Double] = [:]
        let startTime = Date()

        // Interface status
        let ifconfigResult = try await executor.run("/sbin/ifconfig")
        if ifconfigResult.success {
            let interfaces = parseInterfaces(ifconfigResult.stdout)
            metrics["active_interfaces"] = Double(interfaces.filter { $0.status == "active" }.count)
            metrics["total_interfaces"] = Double(interfaces.count)
        }

        // DNS resolution
        let dnsResult = try await executor.run("/usr/bin/dig", arguments: ["+short", "apple.com", "@8.8.8.8"])
        if !dnsResult.success || dnsResult.stdout.isEmpty {
            issues.append(DiagnosticIssue(
                category: "Network",
                severity: .warning,
                title: "DNS Resolution Issues",
                description: "Could not resolve apple.com via 8.8.8.8",
                suggestion: "Check DNS settings, try different DNS servers"
            ))
        }

        // Ping test
        let pingResult = try await executor.run("/sbin/ping", arguments: ["-c", "3", "-W", "2000", "8.8.8.8"])
        if !pingResult.success {
            issues.append(DiagnosticIssue(
                category: "Network",
                severity: .warning,
                title: "Internet Connectivity Issues",
                description: "Cannot reach 8.8.8.8",
                suggestion: "Check network connection, firewall, router"
            ))
        } else {
            let latency = parsePingLatency(pingResult.stdout)
            metrics["ping_latency_ms"] = latency
            if latency > 100 {
                issues.append(DiagnosticIssue(
                    category: "Network",
                    severity: .info,
                    title: "High Latency",
                    description: "Ping latency to 8.8.8.8: \(Int(latency))ms",
                    suggestion: "Check network quality, consider different DNS"
                ))
            }
        }

        // Firewall status
        let fwResult = try await executor.run("/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--getglobalstate"])
        if fwResult.success {
            let enabled = fwResult.stdout.contains("enabled")
            metrics["firewall_enabled"] = enabled ? 1 : 0
            if !enabled {
                issues.append(DiagnosticIssue(
                    category: "Network",
                    severity: .info,
                    title: "Firewall Disabled",
                    description: "macOS Application Firewall is not enabled",
                    suggestion: "Enable in System Settings > Network > Firewall"
                ))
            }
        }

        let status = issues.filter { $0.severity == .critical }.isEmpty ? "PASS" : "FAIL"

        return CategoryDiagnostic(
            name: "Network",
            status: status,
            issues: issues,
            metrics: metrics,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    private struct NetworkInterface {
        let name: String
        let status: String
        let ipv4: [String]
        let ipv6: [String]
    }

    private func parseInterfaces(_ output: String) -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        let sections = output.split(separator: "\n\n")

        for section in sections {
            let lines = section.split(separator: "\n")
            guard let firstLine = lines.first else { continue }

            let name = firstLine.split(separator: ":")[0].trimmingCharacters(in: .whitespaces)
            var status = "inactive"
            var ipv4: [String] = []
            var ipv6: [String] = []

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("status:") {
                    status = trimmed.replacingOccurrences(of: "status:", with: "").trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("inet ") {
                    let parts = trimmed.split(separator: " ")
                    if parts.count > 1 {
                        ipv4.append(String(parts[1]))
                    }
                } else if trimmed.hasPrefix("inet6 ") {
                    let parts = trimmed.split(separator: " ")
                    if parts.count > 1 {
                        ipv6.append(String(parts[1]))
                    }
                }
            }

            interfaces.append(NetworkInterface(name: name, status: status, ipv4: ipv4, ipv6: ipv6))
        }

        return interfaces
    }

    private func parsePingLatency(_ output: String) -> Double {
        // "round-trip min/avg/max/stddev = 12.345/15.678/18.901/2.345 ms"
        let pattern = #"round-trip min/avg/max/stddev = [\d.]+/([\d.]+)/"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: output.utf16.count)
        if let match = regex?.firstMatch(in: output, options: [], range: range),
           let valueRange = Range(match.range(at: 1), in: output) {
            return Double(output[valueRange]) ?? 0
        }
        return 0
    }

    // MARK: - Software Diagnostics

    private func runSoftwareDiagnostics(detailed: Bool) async throws -> CategoryDiagnostic {
        var issues: [DiagnosticIssue] = []
        var metrics: [String: Double] = [:]
        let startTime = Date()

        // OS Version
        let osResult = try await executor.run("/usr/bin/sw_vers")
        if osResult.success {
            let lines = osResult.stdout.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("ProductVersion:") {
                    let version = line.replacingOccurrences(of: "ProductVersion:", with: "").trimmingCharacters(in: .whitespaces)
                    metrics["os_version"] = Double(version.replacingOccurrences(of: ".", with: "")) ?? 0
                }
            }
        }

        // Check for updates
        let updateResult = try await executor.run("/usr/sbin/softwareupdate", arguments: ["-l", "--no-scan"])
        if updateResult.success {
            if updateResult.stdout.contains("No new software available") {
                metrics["updates_available"] = 0
            } else {
                let updateCount = updateResult.stdout.components(separatedBy: "\n").filter { $0.contains("*") }.count
                metrics["updates_available"] = Double(updateCount)
                if updateCount > 0 {
                    issues.append(DiagnosticIssue(
                        category: "Software",
                        severity: .info,
                        title: "Software Updates Available",
                        description: "\(updateCount) system update(s) available",
                        suggestion: "Run 'softwareupdate -ia' to install"
                    ))
                }
            }
        }

        // Homebrew
        if await executor.isAvailable("brew") {
            let brewResult = try await executor.run("/opt/homebrew/bin/brew", arguments: ["doctor"])
            if !brewResult.success {
                issues.append(DiagnosticIssue(
                    category: "Software",
                    severity: .warning,
                    title: "Homebrew Issues Detected",
                    description: "brew doctor reported problems",
                    suggestion: "Run 'brew doctor' for details"
                ))
            }
            metrics["homebrew_installed"] = 1
        } else {
            metrics["homebrew_installed"] = 0
        }

        // Xcode
        let xcodeResult = try await executor.run("/usr/bin/xcodebuild", arguments: ["-version"])
        if xcodeResult.success {
            let version = xcodeResult.stdout.components(separatedBy: .newlines).first ?? ""
            metrics["xcode_installed"] = 1
        } else {
            metrics["xcode_installed"] = 0
        }

        // Login items
        let loginResult = try await executor.run("/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to get the name of every login item"])
        if loginResult.success {
            let items = loginResult.stdout.components(separatedBy: ", ").filter { !$0.isEmpty }
            metrics["login_items"] = Double(items.count)
            if items.count > 20 {
                issues.append(DiagnosticIssue(
                    category: "Software",
                    severity: .info,
                    title: "Many Login Items",
                    description: "\(items.count) login items may slow boot",
                    suggestion: "Review in System Settings > General > Login Items"
                ))
            }
        }

        let status = issues.filter { $0.severity == .critical }.isEmpty ? "PASS" : "FAIL"

        return CategoryDiagnostic(
            name: "Software",
            status: status,
            issues: issues,
            metrics: metrics,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Security Diagnostics

    private func runSecurityDiagnostics(detailed: Bool) async throws -> CategoryDiagnostic {
        var issues: [DiagnosticIssue] = []
        var metrics: [String: Double] = [:]
        let startTime = Date()

        // SIP Status
        let sipResult = try await executor.run("/usr/bin/csrutil", arguments: ["status"])
        if sipResult.success {
            let enabled = sipResult.stdout.contains("enabled")
            metrics["sip_enabled"] = enabled ? 1 : 0
            if !enabled {
                issues.append(DiagnosticIssue(
                    category: "Security",
                    severity: .critical,
                    title: "System Integrity Protection Disabled",
                    description: "SIP is disabled - system is vulnerable",
                    suggestion: "Enable SIP by booting to Recovery Mode and running 'csrutil enable'"
                ))
            }
        }

        // Gatekeeper
        let gkResult = try await executor.run("/usr/sbin/spctl", arguments: ["--status"])
        if gkResult.success {
            let enabled = gkResult.stdout.contains("enabled")
            metrics["gatekeeper_enabled"] = enabled ? 1 : 0
            if !enabled {
                issues.append(DiagnosticIssue(
                    category: "Security",
                    severity: .warning,
                    title: "Gatekeeper Disabled",
                    description: "Gatekeeper is disabled - unsigned apps can run",
                    suggestion: "Enable with 'sudo spctl --master-enable'"
                ))
            }
        }

        // AMFI
        let amfiResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "kern.amfi.trustcache.enabled"])
        if amfiResult.success {
            let enabled = amfiResult.stdout.trimmingCharacters(in: .whitespaces) == "1"
            metrics["amfi_enabled"] = enabled ? 1 : 0
        }

        // FileVault
        let fvResult = try await executor.run("/usr/bin/fdesetup", arguments: ["status"])
        if fvResult.success {
            let enabled = fvResult.stdout.contains("On")
            metrics["filevault_enabled"] = enabled ? 1 : 0
            if !enabled {
                issues.append(DiagnosticIssue(
                    category: "Security",
                    severity: .warning,
                    title: "FileVault Disabled",
                    description: "Disk encryption is not enabled",
                    suggestion: "Enable in System Settings > Privacy & Security > FileVault"
                ))
            }
        }

        // Firewall
        let fwResult = try await executor.run("/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--getglobalstate"])
        if fwResult.success {
            let enabled = fwResult.stdout.contains("enabled")
            metrics["firewall_enabled"] = enabled ? 1 : 0
        }

        // Secure Boot
        let sbResult = try await executor.run("/usr/sbin/nvram", arguments: ["-p"])
        if sbResult.success {
            let secureBoot = sbResult.stdout.contains("SecureBootModel") ? "Full" : "Unknown"
            metrics["secure_boot"] = secureBoot == "Full" ? 1 : 0
        }

        // Expired certificates
        let certResult = try await executor.run("/usr/bin/security", arguments: ["find-certificate", "-a", "-c", "", "/System/Library/Keychains/SystemRootCertificates.keychain"])
        if certResult.success {
            let expiredCount = certResult.stdout.components(separatedBy: "-----END CERTIFICATE-----").count - 1
            metrics["system_certificates"] = Double(expiredCount)
        }

        let status = issues.filter { $0.severity == .critical }.isEmpty ? "PASS" : "FAIL"

        return CategoryDiagnostic(
            name: "Security",
            status: status,
            issues: issues,
            metrics: metrics,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Performance Diagnostics

    private func runPerformanceDiagnostics(detailed: Bool) async throws -> CategoryDiagnostic {
        var issues: [DiagnosticIssue] = []
        var metrics: [String: Double] = [:]
        let startTime = Date()

        // Load average
        let loadResult = try await executor.run("/usr/bin/uptime")
        if loadResult.success {
            let loads = parseLoadAverage(loadResult.stdout)
            metrics["load_1m"] = loads.0
            metrics["load_5m"] = loads.1
            metrics["load_15m"] = loads.2

            let coreCount = Double(ProcessInfo.processInfo.activeProcessorCount)
            if loads.0 > coreCount * 2 {
                issues.append(DiagnosticIssue(
                    category: "Performance",
                    severity: .warning,
                    title: "High Load Average",
                    description: "1-minute load average: \(loads.0) (cores: \(Int(coreCount)))",
                    suggestion: "Check for runaway processes with 'top'"
                ))
            }
        }

        // Top CPU processes
        let topResult = try await executor.run("/usr/bin/ps", arguments: ["-eo", "pcpu,pid,comm", "-r"])
        if topResult.success {
            let lines = topResult.stdout.components(separatedBy: .newlines).dropFirst()
            for line in lines.prefix(5) {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
                if parts.count >= 3, let cpu = Double(parts[0]) {
                    if cpu > 100 {
                        issues.append(DiagnosticIssue(
                            category: "Performance",
                            severity: .warning,
                            title: "High CPU Process",
                            description: "\(parts[2]) (PID: \(parts[1])) using \(cpu)% CPU",
                            suggestion: "Investigate process \(parts[1])"
                        ))
                    }
                }
            }
        }

        let status = issues.filter { $0.severity == .critical }.isEmpty ? "PASS" : "FAIL"

        return CategoryDiagnostic(
            name: "Performance",
            status: status,
            issues: issues,
            metrics: metrics,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    private func parseLoadAverage(_ output: String) -> (Double, Double, Double) {
        let pattern = #"load averages?: ([\d.]+) ([\d.]+) ([\d.]+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: output.utf16.count)
        if let match = regex?.firstMatch(in: output, options: [], range: range),
           let r1 = Range(match.range(at: 1), in: output),
           let r2 = Range(match.range(at: 2), in: output),
           let r3 = Range(match.range(at: 3), in: output) {
            return (
                Double(output[r1]) ?? 0,
                Double(output[r2]) ?? 0,
                Double(output[r3]) ?? 0
            )
        }
        return (0, 0, 0)
    }

    // MARK: - Log Diagnostics

    private func runLogDiagnostics(detailed: Bool) async throws -> CategoryDiagnostic {
        var issues: [DiagnosticIssue] = []
        var metrics: [String: Double] = [:]
        let startTime = Date()

        // Check log size
        let logDirs = ["/var/log", "/Library/Logs", "~/Library/Logs".expandingTildeInPath]
        var totalLogSize: Int64 = 0

        for dir in logDirs {
            let size = await fileUtils.calculateDirectorySize(dir)
            totalLogSize += size
        }

        metrics["total_log_size_mb"] = Double(totalLogSize) / (1024 * 1024)

        if totalLogSize > 5 * 1024 * 1024 * 1024 { // > 5GB
            issues.append(DiagnosticIssue(
                category: "Logs",
                severity: .warning,
                title: "Large Log Files",
                description: "System logs consuming \(ByteCountFormatter.string(fromByteCount: totalLogSize, countStyle: .file))",
                suggestion: "Run log cleanup or check for runaway logging"
            ))
        }

        // Check for kernel panics
        let panicDir = "/Library/Logs/DiagnosticReports"
        let panicFiles = (try? FileManager.default.contentsOfDirectory(atPath: panicDir).filter { $0.hasPrefix("kernel_") }) ?? []
        if !panicFiles.isEmpty {
            issues.append(DiagnosticIssue(
                category: "Logs",
                severity: .critical,
                title: "Kernel Panics Detected",
                description: "\(panicFiles.count) kernel panic report(s) found",
                path: panicDir,
                suggestion: "Review panic logs, check hardware/drivers"
            ))
        }

        // Check for frequent crashes
        let crashFiles = (try? FileManager.default.contentsOfDirectory(atPath: panicDir).filter { !$0.hasPrefix("kernel_") }) ?? []
        if crashFiles.count > 50 {
            issues.append(DiagnosticIssue(
                category: "Logs",
                severity: .warning,
                title: "Many Crash Reports",
                description: "\(crashFiles.count) application crash reports",
                suggestion: "Check for problematic applications"
            ))
        }

        metrics["kernel_panics"] = Double(panicFiles.count)
        metrics["crash_reports"] = Double(crashFiles.count)

        let status = issues.filter { $0.severity == .critical }.isEmpty ? "PASS" : "FAIL"

        return CategoryDiagnostic(
            name: "Logs",
            status: status,
            issues: issues,
            metrics: metrics,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Launch Diagnostics

    private func runLaunchDiagnostics(detailed: Bool) async throws -> CategoryDiagnostic {
        var issues: [DiagnosticIssue] = []
        var metrics: [String: Double] = [:]
        let startTime = Date()

        let launchDirs = [
            "/Library/LaunchDaemons",
            "/Library/LaunchAgents",
            "~/Library/LaunchAgents".expandingTildeInPath
        ]

        var totalItems = 0
        var disabledItems = 0

        for dir in launchDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            let plists = contents.filter { $0.hasSuffix(".plist") }
            totalItems += plists.count

            for plist in plists {
                let path = (dir as NSString).appendingPathComponent(plist)
                if let data = FileManager.default.contents(atPath: path),
                   let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    if dict["Disabled"] as? Bool == true {
                        disabledItems += 1
                    }
                    if dict["RunAtLoad"] as? Bool == true && dict["KeepAlive"] as? Bool == true {
                        // Potentially resource-heavy
                    }
                }
            }
        }

        metrics["launch_items_total"] = Double(totalItems)
        metrics["launch_items_disabled"] = Double(disabledItems)

        if totalItems > 50 {
            issues.append(DiagnosticIssue(
                category: "Launch",
                severity: .info,
                title: "Many Launch Items",
                description: "\(totalItems) launch agents/daemons configured",
                suggestion: "Review for unnecessary items"
            ))
        }

        let status = issues.filter { $0.severity == .critical }.isEmpty ? "PASS" : "FAIL"

        return CategoryDiagnostic(
            name: "Launch Services",
            status: status,
            issues: issues,
            metrics: metrics,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - TCC Diagnostics

    private func runTCCDiagnostics(detailed: Bool) async throws -> CategoryDiagnostic {
        var issues: [DiagnosticIssue] = []
        var metrics: [String: Double] = [:]
        let startTime = Date()

        // Check TCC database integrity
        let tccPaths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "~/Library/Application Support/com.apple.TCC/TCC.db".expandingTildeInPath
        ]

        for path in tccPaths {
            if FileManager.default.fileExists(atPath: path) {
                let integrityResult = try await executor.run("/usr/bin/sqlite3", arguments: [path, "PRAGMA integrity_check;"])
                if integrityResult.success, !integrityResult.stdout.contains("ok") {
                    issues.append(DiagnosticIssue(
                        category: "TCC",
                        severity: .critical,
                        title: "TCC Database Corruption",
                        description: "Privacy database integrity check failed",
                        path: path,
                        suggestion: "Reset TCC database (requires reboot to Recovery Mode)"
                    ))
                }
            }
        }

        // Count TCC entries
        let tccResult = try await executor.run("/usr/bin/sqlite3", arguments: [tccPaths[0], "SELECT service, COUNT(*) FROM access GROUP BY service;"])
        if tccResult.success {
            let lines = tccResult.stdout.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.split(separator: "|")
                if parts.count == 2 {
                    metrics["tcc_\(parts[0])"] = Double(parts[1]) ?? 0
                }
            }
        }

        let status = issues.filter { $0.severity == .critical }.isEmpty ? "PASS" : "FAIL"

        return CategoryDiagnostic(
            name: "Privacy (TCC)",
            status: status,
            issues: issues,
            metrics: metrics,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

// MARK: - String Extension

extension String {
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}