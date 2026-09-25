import Testing
import Foundation
@testable import MacOSFixerCore

@Suite("MacOSFixerCore Tests")
struct MacOSFixerTests {

    @Test("RepairCategory has correct display names")
    func repairCategoryDisplayNames() {
        #expect(RepairCategory.permissions.displayName == "File Permissions & ACLs")
        #expect(RepairCategory.disk.displayName == "Disk & Filesystem")
        #expect(RepairCategory.caches.displayName == "System & User Caches")
        #expect(RepairCategory.spotlight.displayName == "Spotlight Index")
    }

    @Test("CleanupCategory has correct display names")
    func cleanupCategoryDisplayNames() {
        #expect(CleanupCategory.user.displayName == "User Caches & Temp")
        #expect(CleanupCategory.docker.displayName == "Docker Images/Containers")
        #expect(CleanupCategory.xcode.displayName == "Xcode DerivedData/Archives")
    }

    @Test("VerificationType has correct display names")
    func verificationTypeDisplayNames() {
        #expect(VerificationType.filesystem.displayName == "Filesystem Integrity (fsck)")
        #expect(VerificationType.sip.displayName == "System Integrity Protection")
        #expect(VerificationType.codesign.displayName == "Code Signing")
    }

    @Test("IssueSeverity ordering")
    func issueSeverityOrdering() {
        #expect(IssueSeverity.info < IssueSeverity.warning)
        #expect(IssueSeverity.warning < IssueSeverity.critical)
        #expect(IssueSeverity.info < IssueSeverity.critical)
    }

    @Test("DiagnosticIssue creation")
    func diagnosticIssueCreation() {
        let issue = DiagnosticIssue(
            category: "Test",
            severity: .warning,
            title: "Test Issue",
            description: "Test description",
            path: "/test/path",
            suggestion: "Fix it",
            autoFixable: true
        )

        #expect(issue.category == "Test")
        #expect(issue.severity == .warning)
        #expect(issue.title == "Test Issue")
        #expect(issue.path == "/test/path")
        #expect(issue.autoFixable == true)
        #expect(issue.fixed == false)
    }

    @Test("DiagnosticIssue default values")
    func diagnosticIssueDefaults() {
        let issue = DiagnosticIssue(
            category: "Test",
            severity: .info,
            title: "Test",
            description: "Desc"
        )

        #expect(issue.path == nil)
        #expect(issue.suggestion == nil)
        #expect(issue.autoFixable == false)
        #expect(issue.fixed == false)
    }

    @Test("CommandExecutor runs simple command")
    func commandExecutorSimple() async throws {
        let executor = CommandExecutor.shared
        let result = try await executor.run("/bin/echo", arguments: ["hello"])

        #expect(result.success == true)
        #expect(result.stdout == "hello")
        #expect(result.exitCode == 0)
    }

    @Test("CommandExecutor handles failure")
    func commandExecutorFailure() async throws {
        let executor = CommandExecutor.shared
        let result = try await executor.run("/bin/false")

        #expect(result.success == false)
        #expect(result.exitCode != 0)
    }

    @Test("FileSystemUtils calculates directory size")
    func fileSystemUtilsDirectorySize() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create test files
        let file1 = tempDir.appendingPathComponent("file1.txt")
        let file2 = tempDir.appendingPathComponent("file2.txt")
        try "Hello World".write(to: file1, atomically: true, encoding: .utf8)
        try "Test Data".write(to: file2, atomically: true, encoding: .utf8)

        let size = await FileSystemUtils.calculateDirectorySize(tempDir.path)
        #expect(size > 0)
        #expect(size >= 21) // "Hello World" + "Test Data" = 21 bytes

        try FileManager.default.removeItem(at: tempDir)
    }

    @Test("FileSystemUtils file age")
    func fileSystemUtilsFileAge() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_age_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let file = tempDir.appendingPathComponent("test.txt")
        try "test".write(to: file, atomically: true, encoding: .utf8)

        let age = FileSystemUtils.getFileAge(at: file.path)
        #expect(age != nil)
        #expect(age! < 10) // Should be very recent

        try FileManager.default.removeItem(at: tempDir)
    }

    @Test("FileSystemUtils isOlderThan")
    func fileSystemUtilsIsOlderThan() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_old_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let file = tempDir.appendingPathComponent("test.txt")
        try "test".write(to: file, atomically: true, encoding: .utf8)

        // File just created, should not be older than 1 day
        #expect(FileSystemUtils.isOlderThan(at: file.path, days: 1) == false)

        try FileManager.default.removeItem(at: tempDir)
    }

    @Test("Table rendering")
    func tableRendering() {
        let headers = ["Name", "Value", "Status"]
        let rows = [
            ["CPU", "45%", "OK"],
            ["Memory", "78%", "WARN"],
            ["Disk", "92%", "CRITICAL"]
        ]

        let table = renderTable(headers: headers, rows: rows)

        #expect(table.contains("Name"))
        #expect(table.contains("CPU"))
        #expect(table.contains("CRITICAL"))
        #expect(table.contains("│"))
        #expect(table.contains("─"))
    }

    @Test("Table rendering with alignment")
    func tableRenderingAlignment() {
        let headers = ["Left", "Right", "Center"]
        let rows = [["A", "1", "X"], ["Longer Text", "100", "Y"]]
        let alignments: [Alignment] = [.left, .right, .center]

        let table = renderTable(headers: headers, rows: rows, alignments: alignments)

        #expect(table.contains("Left"))
        #expect(table.contains("Right"))
        #expect(table.contains("Center"))
    }

    @Test("JSON encoding")
    func jsonEncoding() throws {
        let issue = DiagnosticIssue(
            category: "Test",
            severity: .critical,
            title: "Test Issue",
            description: "Description"
        )

        let json = try issue.toJSON()
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DiagnosticIssue.self, from: data)

        #expect(decoded.category == "Test")
        #expect(decoded.severity == .critical)
        #expect(decoded.title == "Test Issue")
    }

    @Test("PerformanceBottleneck types")
    func performanceBottleneckTypes() {
        let bottleneck = PerformanceBottleneck(
            type: .cpu,
            severity: .warning,
            description: "High CPU",
            recommendation: "Check processes",
            metrics: ["load": 15.0]
        )

        #expect(bottleneck.type == .cpu)
        #expect(bottleneck.severity == .warning)
        #expect(bottleneck.metrics["load"] == 15.0)
    }

    @Test("All RepairCategory cases")
    func allRepairCategories() {
        let allCases = RepairCategory.allCases
        #expect(allCases.count == 14) // permissions, disk, caches, logs, prefs, launchd, spotlight, docker, homebrew, keychain, tcc, fonts, metadata
    }

    @Test("All CleanupCategory cases")
    func allCleanupCategories() {
        let allCases = CleanupCategory.allCases
        #expect(allCases.count == 13) // user, system, apps, docker, xcode, node, python, rust, go, java, browsers, mail, trash
    }

    @Test("All VerificationType cases")
    func allVerificationTypes() {
        let allCases = VerificationType.allCases
        #expect(allCases.count == 12) // filesystem, packages, binaries, prefs, keychain, tcc, codesign, sip, amfi, launchd, cron, login-items
    }
}

@Suite("SystemDiagnostics Tests")
struct SystemDiagnosticsTests {

    @Test("SystemDiagnostics initialization")
    func systemDiagnosticsInit() {
        let diagnostics = SystemDiagnostics()
        #expect(diagnostics != nil)
    }
}

@Suite("PerformanceMonitor Tests")
struct PerformanceMonitorTests {

    @Test("PerformanceMonitor initialization")
    func performanceMonitorInit() {
        let monitor = PerformanceMonitor()
        #expect(monitor != nil)
    }
}

@Suite("MachineOverview Tests")
struct MachineOverviewTests {

    @Test("MachineOverview initialization")
    func machineOverviewInit() {
        let overview = MachineOverview()
        #expect(overview != nil)
    }
}

@Suite("SystemRepair Tests")
struct SystemRepairTests {

    @Test("SystemRepair initialization")
    func systemRepairInit() {
        let repair = SystemRepair()
        #expect(repair != nil)
    }
}

@Suite("SystemCleanup Tests")
struct SystemCleanupTests {

    @Test("SystemCleanup initialization")
    func systemCleanupInit() {
        let cleanup = SystemCleanup()
        #expect(cleanup != nil)
    }
}

@Suite("SystemVerification Tests")
struct SystemVerificationTests {

    @Test("SystemVerification initialization")
    func systemVerificationInit() {
        let verification = SystemVerification()
        #expect(verification != nil)
    }
}