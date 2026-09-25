import ArgumentParser
import MacOSFixerCore
import Foundation
import AppKit

@main
struct MacOSFixer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macosfixer",
        abstract: "Comprehensive macOS diagnostic, repair, and performance analysis tool",
        version: "1.0.0",
        subcommands: [
            Diagnose.self,
            Repair.self,
            Performance.self,
            Overview.self,
            Cleanup.self,
            Verify.self,
            Dashboard.self,
        ],
        defaultSubcommand: Overview.self
    )
}

struct Diagnose: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose",
        abstract: "Run comprehensive system diagnostics"
    )

    @Option(name: .shortAndLong, help: "Output format (json, yaml, table)")
    var format: String = "table"

    @Flag(name: .shortAndLong, help: "Include detailed hardware information")
    var detailed: Bool = false

    @Flag(name: .long, help: "Save results to file")
    var save: Bool = false

    func run() async throws {
        let diagnostics = SystemDiagnostics()
        let report = try await diagnostics.runFullDiagnostics(detailed: detailed)

        switch format.lowercased() {
        case "json":
            print(try report.toJSON())
        case "yaml":
            print(try report.toYAML())
        default:
            print(try report.toJSON())
        }

        if save {
            let url = URL(fileURLWithPath: "diagnostics-\(Date().timeIntervalSince1970).json")
            try report.toJSON().write(to: url, atomically: true, encoding: .utf8)
            print("\nResults saved to: \(url.path)")
        }
    }
}

struct Repair: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repair",
        abstract: "Fix common macOS issues, errors, and corrupt files"
    )

    @Option(name: .shortAndLong, help: "Repair category (all, permissions, disk, caches, logs, prefs, launchd, spotlight, docker, homebrew)")
    var category: String = "all"

    @Flag(name: .shortAndLong, help: "Run in dry-run mode (show what would be fixed)")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Force repair without confirmation")
    var force: Bool = false

    @Flag(name: .long, help: "Create backup before repairs")
    var backup: Bool = true

    func run() async throws {
        let repair = SystemRepair()
        let categories = category.lowercased() == "all" ? RepairCategory.allCases : [RepairCategory(rawValue: category.lowercased())].compactMap { $0 }

        print("🔧 Starting macOS Repair Tool")
        print("Categories: \(categories.map { $0.rawValue }.joined(separator: ", "))")
        print("Dry run: \(dryRun)")
        print("Backup: \(backup)")
        print("")

        let results = try await repair.runRepairs(
            categories: categories,
            dryRun: dryRun,
            force: force,
            createBackup: backup
        )

        print("\n✅ Repair Summary:")
        print(results.summary)

                if !results.results.isEmpty {
            print("\n❌ Errors:")
            for result in results.results {
                for error in result.errors {
                    print("  - \(error)")
                }
            }
        }
    }
}

struct Performance: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "performance",
        abstract: "Analyze system performance and bottlenecks"
    )

    @Option(name: .shortAndLong, help: "Monitoring duration in seconds")
    var duration: Int = 30

    @Option(name: .shortAndLong, help: "Output format (json, table, csv)")
    var format: String = "table"

    @Flag(name: .long, help: "Include thermal throttling analysis")
    var thermal: Bool = false

    @Flag(name: .long, help: "Include power/energy analysis")
    var power: Bool = false

    func run() async throws {
        let monitor = PerformanceMonitor()
        let report = try await monitor.analyzePerformance(
            duration: duration,
            includeThermal: thermal,
            includePower: power
        )

        switch format.lowercased() {
        case "json":
            print(try report.toJSON())
        case "csv":
            print(try report.toJSON())
        default:
            print(try report.toJSON())
        }
    }
}

struct Overview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overview",
        abstract: "Display complete machine overview matrix"
    )

    @Option(name: .shortAndLong, help: "Output format (json, yaml, table, html)")
    var format: String = "table"

    @Flag(name: .long, help: "Include security posture")
    var security: Bool = false

    @Flag(name: .long, help: "Include network topology")
    var network: Bool = false

    @Flag(name: .long, help: "Save as HTML report")
    var html: Bool = false

    func run() async throws {
        let overview = MachineOverviewCollector()
        let matrix = try await overview.generateMatrix(
            includeSecurity: security,
            includeNetwork: network
        )

        switch format.lowercased() {
        case "json":
            print(try matrix.toJSON())
        case "yaml":
            print(try matrix.toYAML())
        case "html":
            let html = try matrix.toHTML(title: "MacOSFixer Machine Overview")
            let url = URL(fileURLWithPath: "machine-overview-\(Date().timeIntervalSince1970).html")
            try html.write(to: url, atomically: true, encoding: .utf8)
            print("HTML report saved to: \(url.path)")

            // Open in browser
            NSWorkspace.shared.open(url)
        default:
            print(try matrix.toJSON())
        }
    }
}

struct Cleanup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup",
        abstract: "Clean system caches, logs, and temporary files"
    )

    @Option(name: .shortAndLong, help: "Cleanup category (all, user, system, apps, docker, xcode, node, python)")
    var category: String = "all"

    @Flag(name: .shortAndLong, help: "Show what would be cleaned without doing it")
    var dryRun: Bool = false

    @Option(name: .long, help: "Minimum age of files to clean (days)")
    var minAge: Int = 7

    @Flag(name: .long, help: "Show size before/after")
    var verbose: Bool = false

    func run() async throws {
        let cleanup = SystemCleanup()
        let categories = category.lowercased() == "all" ? CleanupCategory.allCases : [CleanupCategory(rawValue: category.lowercased())].compactMap { $0 }

        let results = try await cleanup.runCleanup(
            categories: categories,
            dryRun: dryRun,
            minAgeDays: minAge,
            verbose: verbose
        )

        print("\n🧹 Cleanup Summary:")
        print("Freed: \(ByteCountFormatter.string(fromByteCount: results.bytesFreed, countStyle: .file))")
        print("Items cleaned: \(results.itemsCleaned)")

        if verbose {
            for result in results.results {
                for detail in result.details {
                    print("  \(result.category.displayName): \(ByteCountFormatter.string(fromByteCount: detail.bytesFreed, countStyle: .file)) (\(detail.itemsCount) items) - \(detail.path)")
                }
            }
        }
    }
}

struct Verify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify system integrity and detect corruption"
    )

    @Option(name: .shortAndLong, help: "Verification type (all, filesystem, packages, binaries, prefs, keychain, tcc)")
    var type: String = "all"

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Auto-fix detected issues")
    var autoFix: Bool = false

    func run() async throws {
        let verify = SystemVerification()
        let types = type.lowercased() == "all" ? VerificationType.allCases : [VerificationType(rawValue: type.lowercased())].compactMap { $0 }

        let results = try await verify.runVerification(
            types: types,
            verbose: verbose,
            autoFix: autoFix
        )

        print("\n🔍 Verification Results:")
        print("Status: \(results.overallStatus ? "✅ PASS" : "❌ FAIL")")
        print("Checks: \(results.passed)/\(results.total) passed")

        if verbose || !results.issues.isEmpty {
            print("\nDetails:")
            for issue in results.issues {
                let status = issue.fixed ? "🔧 FIXED" : (issue.severity == .critical ? "🔴 CRITICAL" : issue.severity == .warning ? "🟡 WARNING" : "🟢 INFO")
                print("  \(status) [\(issue.category)] \(issue.description)")
                if verbose, let path = issue.path {
                    print("      Path: \(path)")
                }
            }
        }
    }
}

struct Dashboard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "Launch interactive web dashboard"
    )

    @Option(name: .shortAndLong, help: "Port to run dashboard on")
    var port: Int = 8080

    @Flag(name: .long, help: "Open browser automatically")
    var open: Bool = true

    func run() async throws {
        let dashboard = WebDashboard(port: port)
        try await dashboard.start(openBrowser: open)
    }
}