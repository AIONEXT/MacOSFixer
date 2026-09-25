import Foundation

// MARK: - Core Types

public enum RepairCategory: String, CaseIterable, Sendable, Codable {
    case permissions = "permissions"
    case disk = "disk"
    case caches = "caches"
    case logs = "logs"
    case preferences = "prefs"
    case launchd = "launchd"
    case spotlight = "spotlight"
    case docker = "docker"
    case homebrew = "homebrew"
    case keychain = "keychain"
    case tcc = "tcc"
    case fonts = "fonts"
    case metadata = "metadata"

    public var displayName: String {
        switch self {
        case .permissions: return "File Permissions & ACLs"
        case .disk: return "Disk & Filesystem"
        case .caches: return "System & User Caches"
        case .logs: return "System & Application Logs"
        case .preferences: return "Preference Files (.plist)"
        case .launchd: return "Launch Agents/Daemons"
        case .spotlight: return "Spotlight Index"
        case .docker: return "Docker Resources"
        case .homebrew: return "Homebrew Installation"
        case .keychain: return "Keychain & Certificates"
        case .tcc: return "Privacy (TCC) Database"
        case .fonts: return "Font Caches"
        case .metadata: return "Extended Attributes & Metadata"
        }
    }
}

public enum CleanupCategory: String, CaseIterable, Sendable, Codable {
    case user = "user"
    case system = "system"
    case apps = "apps"
    case docker = "docker"
    case xcode = "xcode"
    case node = "node"
    case python = "python"
    case rust = "rust"
    case go = "go"
    case java = "java"
    case browsers = "browsers"
    case mail = "mail"
    case trash = "trash"

    public var displayName: String {
        switch self {
        case .user: return "User Caches & Temp"
        case .system: return "System Caches & Logs"
        case .apps: return "Application Caches"
        case .docker: return "Docker Images/Containers"
        case .xcode: return "Xcode DerivedData/Archives"
        case .node: return "Node.js (npm/yarn/pnpm)"
        case .python: return "Python (pip/conda/pipx)"
        case .rust: return "Rust (cargo)"
        case .go: return "Go (module cache)"
        case .java: return "Java (Maven/Gradle)"
        case .browsers: return "Browser Caches"
        case .mail: return "Mail Downloads/Attachments"
        case .trash: return "Trash"
        }
    }
}

public enum VerificationType: String, CaseIterable, Sendable, Codable {
    case filesystem = "filesystem"
    case packages = "packages"
    case binaries = "binaries"
    case preferences = "prefs"
    case keychain = "keychain"
    case tcc = "tcc"
    case codesign = "codesign"
    case sip = "sip"
    case amfi = "amfi"
    case launchd = "launchd"
    case cron = "cron"
    case loginItems = "login-items"

    public var displayName: String {
        switch self {
        case .filesystem: return "Filesystem Integrity (fsck)"
        case .packages: return "Package Receipts (pkgutil)"
        case .binaries: return "Binary Codesignatures"
        case .preferences: return "Preference Files"
        case .keychain: return "Keychain Integrity"
        case .tcc: return "TCC Database"
        case .codesign: return "Code Signing"
        case .sip: return "System Integrity Protection"
        case .amfi: return "AMFI Trust Cache"
        case .launchd: return "Launch Services"
        case .cron: return "Cron Jobs"
        case .loginItems: return "Login Items"
        }
    }
}

public enum IssueSeverity: String, Sendable, Comparable, Codable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"

    public static func < (lhs: IssueSeverity, rhs: IssueSeverity) -> Bool {
        let order: [IssueSeverity] = [.info, .warning, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public struct DiagnosticIssue: Sendable, Codable {
    public let category: String
    public let severity: IssueSeverity
    public let title: String
    public let description: String
    public let path: String?
    public let suggestion: String?
    public let autoFixable: Bool
    public let fixed: Bool

    public init(
        category: String,
        severity: IssueSeverity,
        title: String,
        description: String,
        path: String? = nil,
        suggestion: String? = nil,
        autoFixable: Bool = false,
        fixed: Bool = false
    ) {
        self.category = category
        self.severity = severity
        self.title = title
        self.description = description
        self.path = path
        self.suggestion = suggestion
        self.autoFixable = autoFixable
        self.fixed = fixed
    }
}

public struct RepairResult: Sendable, Codable {
    public let category: RepairCategory
    public let success: Bool
    public let issuesFound: Int
    public let issuesFixed: Int
    public let errors: [String]
    public let details: [String]
    public let duration: TimeInterval

    public var summary: String {
        var lines: [String] = []
        lines.append("\(category.displayName): \(success ? "✅" : "❌")")
        lines.append("  Found: \(issuesFound), Fixed: \(issuesFixed)")
        if !errors.isEmpty {
            lines.append("  Errors: \(errors.count)")
        }
        lines.append("  Duration: \(String(format: "%.2f", duration))s")
        return lines.joined(separator: "\n")
    }
}

public struct RepairSummary: Sendable, Codable {
    public let results: [RepairResult]
    public let totalIssuesFound: Int
    public let totalIssuesFixed: Int
    public let totalErrors: Int
    public let totalDuration: TimeInterval
    public let backupPath: String?

    public var summary: String {
        var lines: [String] = []
        lines.append("═══════════════════════════════════════")
        lines.append("         REPAIR SUMMARY")
        lines.append("═══════════════════════════════════════")
        lines.append("Total Issues Found: \(totalIssuesFound)")
        lines.append("Total Issues Fixed: \(totalIssuesFixed)")
        lines.append("Total Errors: \(totalErrors)")
        lines.append("Total Duration: \(String(format: "%.2f", totalDuration))s")
        if let backup = backupPath {
            lines.append("Backup: \(backup)")
        }
        lines.append("")
        for result in results {
            lines.append(result.summary)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

public struct CleanupResult: Sendable, Codable {
    public let category: CleanupCategory
    public let bytesFreed: Int64
    public let itemsCount: Int
    public let errors: [String]
    public let details: [CleanupDetail]
    public let duration: TimeInterval
}

public struct CleanupDetail: Sendable, Codable {
    public let path: String
    public let bytesFreed: Int64
    public let itemsCount: Int
}

public struct CleanupSummary: Sendable, Codable {
    public let results: [CleanupResult]
    public let totalBytesFreed: Int64
    public let totalItemsCleaned: Int
    public let totalDuration: TimeInterval

    public var bytesFreed: Int64 { totalBytesFreed }
    public var itemsCleaned: Int { totalItemsCleaned }
    public var details: [CleanupDetail] {
        results.flatMap { $0.details }
    }
}

public struct VerificationIssue: Sendable, Codable {
    public let category: VerificationType
    public let severity: IssueSeverity
    public let description: String
    public let path: String?
    public let fixed: Bool
    public let autoFixable: Bool
}

public struct VerificationResult: Sendable, Codable {
    public let type: VerificationType
    public let passed: Bool
    public let issues: [VerificationIssue]
    public let duration: TimeInterval
}

public struct VerificationSummary: Sendable, Codable {
    public let results: [VerificationResult]
    public let overallStatus: Bool
    public let passed: Int
    public let total: Int
    public let issues: [VerificationIssue]

    public init(results: [VerificationResult]) {
        self.results = results
        self.passed = results.filter { $0.passed }.count
        self.total = results.count
        self.overallStatus = results.allSatisfy { $0.passed }
        self.issues = results.flatMap { $0.issues }
    }
}

// MARK: - Codable Tuple Replacements

public struct LoadAverage: Sendable, Codable, Equatable {
    public let oneMinute: Double
    public let fiveMinute: Double
    public let fifteenMinute: Double

    public init(_ oneMinute: Double, _ fiveMinute: Double, _ fifteenMinute: Double) {
        self.oneMinute = oneMinute
        self.fiveMinute = fiveMinute
        self.fifteenMinute = fifteenMinute
    }
}

// MARK: - Performance Types

public struct CPUMetrics: Sendable, Codable {
    public let user: Double
    public let system: Double
    public let idle: Double
    public let nice: Double
    public let cores: Int
    public let loadAverage: LoadAverage
    public let frequencyMHz: Int
    public let temperatureCelsius: Double?
}

public struct MemoryMetrics: Sendable, Codable {
    public let total: Int64
    public let used: Int64
    public let free: Int64
    public let active: Int64
    public let inactive: Int64
    public let wired: Int64
    public let compressed: Int64
    public let swapUsed: Int64
    public let swapTotal: Int64
    public let pressureLevel: String
}

public struct DiskMetrics: Sendable, Codable {
    public let device: String
    public let mountPoint: String
    public let totalSpace: Int64
    public let freeSpace: Int64
    public let usedSpace: Int64
    public let readBytesPerSec: Int64
    public let writeBytesPerSec: Int64
    public let readOpsPerSec: Int64
    public let writeOpsPerSec: Int64
    public let iops: Int64
    public let latencyMs: Double
    public let isSSD: Bool
    public let smartStatus: String?
}

public struct NetworkMetrics: Sendable, Codable {
    public let interface: String
    public let bytesInPerSec: Int64
    public let bytesOutPerSec: Int64
    public let packetsInPerSec: Int64
    public let packetsOutPerSec: Int64
    public let errorsIn: Int64
    public let errorsOut: Int64
    public let collisions: Int64
    public let speedMbps: Int64?
}

public struct GPUMetrics: Sendable, Codable {
    public let name: String
    public let utilization: Double
    public let memoryUsed: Int64
    public let memoryTotal: Int64
    public let temperatureCelsius: Double?
    public let powerWatts: Double?
    public let metalSupported: Bool
}

public struct ThermalMetrics: Sendable, Codable {
    public let cpuTemperature: Double?
    public let gpuTemperature: Double?
    public let fanSpeedRPM: Int?
    public let thermalPressure: String
    public let throttling: Bool
}

public struct PowerMetrics: Sendable, Codable {
    public let batteryLevel: Double?
    public let batteryHealth: Double?
    public let cycleCount: Int?
    public let isCharging: Bool
    public let powerSource: String
    public let watts: Double?
    public let timeRemaining: Int?
}

public struct ProcessMetrics: Sendable, Codable {
    public let pid: Int
    public let name: String
    public let cpuPercent: Double
    public let memoryMB: Int64
    public let threads: Int
    public let user: String
    public let command: String
}

public struct PerformanceReport: Sendable, Codable {
    public let timestamp: Date
    public let duration: TimeInterval
    public let cpu: CPUMetrics
    public let memory: MemoryMetrics
    public let disks: [DiskMetrics]
    public let network: [NetworkMetrics]
    public let gpus: [GPUMetrics]
    public let thermal: ThermalMetrics?
    public let power: PowerMetrics?
    public let topProcesses: [ProcessMetrics]
    public let bottlenecks: [PerformanceBottleneck]
}

public typealias MetricsDictionary = [String: Double]

public struct PerformanceBottleneck: Sendable, Codable {
    public enum BottleneckType: String, Sendable, Codable {
        case cpu = "cpu"
        case memory = "memory"
        case disk = "disk"
        case network = "network"
        case thermal = "thermal"
        case gpu = "gpu"
    }

    public let type: BottleneckType
    public let severity: IssueSeverity
    public let description: String
    public let recommendation: String
    public let metrics: MetricsDictionary
}

// MARK: - Overview Types

public struct MachineOverviewData: Sendable, Codable {
    public let hardware: HardwareInfo
    public let software: SoftwareInfo
    public let storage: [StorageInfo]
    public let network: NetworkInfo
    public let security: SecurityInfo?
    public let performance: PerformanceSnapshot
    public let issues: [DiagnosticIssue]
    public let generatedAt: Date
}

public struct HardwareInfo: Sendable, Codable {
    public let modelName: String
    public let modelIdentifier: String
    public let processorName: String
    public let processorSpeed: String
    public let numberOfProcessors: Int
    public let totalNumberOfCores: Int
    public let l2Cache: String
    public let l3Cache: String
    public let memory: String
    public let bootROMVersion: String
    public let smcVersion: String
    public let serialNumber: String
    public let hardwareUUID: String
    public let activationLockStatus: String
    public let graphics: [GPUInfo]
    public let audio: [AudioDevice]
    public let bluetooth: BluetoothInfo?
}

public struct GPUInfo: Sendable, Codable {
    public let name: String
    public let vendor: String
    public let vram: String
    public let metalSupport: String
    public let driverVersion: String?
}

public struct AudioDevice: Sendable, Codable {
    public let name: String
    public let manufacturer: String
    public let inputChannels: Int
    public let outputChannels: Int
    public let sampleRate: Double
}

public struct BluetoothInfo: Sendable, Codable {
    public let version: String
    public let address: String
    public let supportedFeatures: [String]
}

public struct SoftwareInfo: Sendable, Codable {
    public let osVersion: String
    public let osBuild: String
    public let kernelVersion: String
    public let bootTime: Date
    public let uptime: TimeInterval
    public let xcodeVersion: String?
    public let homebrewVersion: String?
    public let dockerVersion: String?
    public let installedPackages: Int
    public let loginItems: [LoginItem]
    public let launchAgents: [LaunchItem]
    public let launchDaemons: [LaunchItem]
}

public struct LoginItem: Sendable, Codable {
    public let name: String
    public let path: String
    public let hidden: Bool
    public let teamIdentifier: String?
}

public struct LaunchItem: Sendable, Codable {
    public let label: String
    public let program: String?
    public let programArguments: [String]?
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let disabled: Bool
    public let path: String
}

public struct StorageInfo: Sendable, Codable {
    public let device: String
    public let mountPoint: String
    public let fileSystem: String
    public let totalGB: Double
    public let freeGB: Double
    public let usedGB: Double
    public let apfsContainer: String?
    public let isEncrypted: Bool
    public let isBoot: Bool
    public let smartStatus: String
    public let trimSupport: Bool
}

public struct NetworkInfo: Sendable, Codable {
    public let interfaces: [NetworkInterface]
    public let dnsServers: [String]
    public let searchDomains: [String]
    public let defaultRoute: String?
    public let publicIP: String?
    public let vpnConnections: [VPNConnection]
}

public struct NetworkInterface: Sendable, Codable {
    public let name: String
    public let displayName: String
    public let type: String
    public let macAddress: String
    public let ipv4Addresses: [String]
    public let ipv6Addresses: [String]
    public let mtu: Int
    public let speed: String
    public let status: String
    public let bytesIn: Int64
    public let bytesOut: Int64
}

public struct VPNConnection: Sendable, Codable {
    public let name: String
    public let type: String
    public let status: String
    public let server: String?
}

public struct SecurityInfo: Sendable, Codable {
    public let sipEnabled: Bool
    public let amfiEnabled: Bool
    public let gatekeeperEnabled: Bool
    public let firewallEnabled: Bool
    public let firewallStealthMode: Bool
    public let fileVaultEnabled: Bool
    public let secureBoot: String
    public let systemExtensions: [String]
    public let kernelExtensions: [String]
    public let tccDatabases: [TCCDatabase]
    public let certificates: CertificateInfo
}

public struct TCCDatabase: Sendable, Codable {
    public let service: String
    public let allowedApps: Int
    public let deniedApps: Int
    public let promptCount: Int
}

public struct CertificateInfo: Sendable, Codable {
    public let systemRoot: Int
    public let system: Int
    public let user: Int
    public let expired: Int
    public let expiringSoon: Int
}

public struct PerformanceSnapshot: Sendable, Codable {
    public let cpuUsage: Double
    public let memoryPressure: String
    public let diskUsage: Double
    public let loadAverage: LoadAverage
    public let topProcess: String
    public let temperatureCelsius: Double?
}

public struct OverviewMatrix: Sendable, Codable {
    public let overview: MachineOverviewData
    public let diagnostics: DiagnosticReport
    public let performance: PerformanceReport
    public let verification: VerificationSummary
}

public struct DiagnosticReport: Sendable, Codable {
    public let timestamp: Date
    public let duration: TimeInterval
    public let categories: [CategoryDiagnostic]
    public let summary: DiagnosticSummary
}

public struct CategoryDiagnostic: Sendable, Codable {
    public let name: String
    public let status: String
    public let issues: [DiagnosticIssue]
    public let metrics: [String: Double]
    public let duration: TimeInterval
}

public struct DiagnosticSummary: Sendable, Codable {
    public let totalCategories: Int
    public let passedCategories: Int
    public let failedCategories: Int
    public let totalIssues: Int
    public let criticalIssues: Int
    public let warningIssues: Int
    public let infoIssues: Int
}