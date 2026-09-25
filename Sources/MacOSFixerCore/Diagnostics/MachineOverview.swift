import Foundation

public final class MachineOverviewCollector: Sendable {
    private let executor = CommandExecutor.shared
    private let diagnostics = SystemDiagnostics()
    private let performance = PerformanceMonitor()

    public init() {}

    public func generateMatrix(
        includeSecurity: Bool = false,
        includeNetwork: Bool = false
    ) async throws -> OverviewMatrix {
        async let overview = collectOverview(includeSecurity: includeSecurity, includeNetwork: includeNetwork)
        async let diag = diagnostics.runFullDiagnostics(detailed: true)
        async let perf = performance.analyzePerformance(duration: 5, includeThermal: includeSecurity, includePower: includeSecurity)
        async let verify = runVerification()

        let (overviewData, diagReport, perfReport, verifySummary) = try await (overview, diag, perf, verify)

        return OverviewMatrix(
            overview: overviewData,
            diagnostics: diagReport,
            performance: perfReport,
            verification: verifySummary
        )
    }

    private func collectOverview(includeSecurity: Bool, includeNetwork: Bool) async throws -> MachineOverviewData {
        let hardware = try await collectHardwareInfo()
        let software = try await collectSoftwareInfo()
        let storage = try await collectStorageInfo()
        let network = includeNetwork ? try await collectNetworkInfo() : NetworkInfo(
            interfaces: [],
            dnsServers: [],
            searchDomains: [],
            defaultRoute: nil,
            publicIP: nil,
            vpnConnections: []
        )
        let security = includeSecurity ? try await collectSecurityInfo() : nil
        let performance = try await collectPerformanceSnapshot()

        return MachineOverviewData(
            hardware: hardware,
            software: software,
            storage: storage,
            network: network,
            security: security,
            performance: performance,
            issues: [],
            generatedAt: Date()
        )
    }

    // MARK: - Hardware Info

    private func collectHardwareInfo() async throws -> HardwareInfo {
        let spResult = try await executor.run("/usr/sbin/system_profiler", arguments: ["SPHardwareDataType", "-json"])

        var modelName = "Unknown"
        var modelIdentifier = "Unknown"
        var processorName = "Unknown"
        var processorSpeed = "Unknown"
        var numberOfProcessors = 1
        var totalNumberOfCores = 1
        var l2Cache = "Unknown"
        var l3Cache = "Unknown"
        var memory = "Unknown"
        var bootROMVersion = "Unknown"
        var smcVersion = "Unknown"
        var serialNumber = "Unknown"
        var hardwareUUID = "Unknown"
        var activationLockStatus = "Unknown"

        if spResult.success,
           let data = spResult.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hardware = json["SPHardwareDataType"] as? [[String: Any]],
           let first = hardware.first {
            modelName = first["machine_model"] as? String ?? "Unknown"
            modelIdentifier = first["machine_id"] as? String ?? "Unknown"
            processorName = first["cpu_type"] as? String ?? "Unknown"
            processorSpeed = first["current_processor_speed"] as? String ?? "Unknown"
            numberOfProcessors = first["number_processors"] as? Int ?? 1
            totalNumberOfCores = first["physical_cpu_count"] as? Int ?? 1
            l2Cache = first["l2_cache"] as? String ?? "Unknown"
            l3Cache = first["l3_cache"] as? String ?? "Unknown"
            memory = first["physical_memory"] as? String ?? "Unknown"
            bootROMVersion = first["boot_rom_version"] as? String ?? "Unknown"
            smcVersion = first["smc_version"] as? String ?? "Unknown"
            serialNumber = first["serial_number"] as? String ?? "Unknown"
            hardwareUUID = first["platform_uuid"] as? String ?? "Unknown"
            activationLockStatus = first["activation_lock_status"] as? String ?? "Unknown"
        }

        // Graphics
        let graphics = try await collectGraphicsInfo()

        // Audio
        let audio = try await collectAudioInfo()

        // Bluetooth
        let bluetooth = try await collectBluetoothInfo()

        return HardwareInfo(
            modelName: modelName,
            modelIdentifier: modelIdentifier,
            processorName: processorName,
            processorSpeed: processorSpeed,
            numberOfProcessors: numberOfProcessors,
            totalNumberOfCores: totalNumberOfCores,
            l2Cache: l2Cache,
            l3Cache: l3Cache,
            memory: memory,
            bootROMVersion: bootROMVersion,
            smcVersion: smcVersion,
            serialNumber: serialNumber,
            hardwareUUID: hardwareUUID,
            activationLockStatus: activationLockStatus,
            graphics: graphics,
            audio: audio,
            bluetooth: bluetooth
        )
    }

    private func collectGraphicsInfo() async throws -> [GPUInfo] {
        var gpus: [GPUInfo] = []

        let spResult = try await executor.run("/usr/sbin/system_profiler", arguments: ["SPDisplaysDataType", "-json"])
        if spResult.success,
           let data = spResult.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let displays = json["SPDisplaysDataType"] as? [[String: Any]] {
            for display in displays {
                let name = display["sppci_model"] as? String ?? "Unknown GPU"
                let vendor = display["sppci_vendor"] as? String ?? "Unknown"
                let vram = display["sppci_vram"] as? String ?? "Unknown"
                let metal = display["sppci_metal"] as? String ?? "Unknown"
                let driver = display["sppci_driver"] as? String

                gpus.append(GPUInfo(
                    name: name,
                    vendor: vendor,
                    vram: vram,
                    metalSupport: metal,
                    driverVersion: driver
                ))
            }
        }

        return gpus
    }

    private func collectAudioInfo() async throws -> [AudioDevice] {
        var devices: [AudioDevice] = []

        let spResult = try await executor.run("/usr/sbin/system_profiler", arguments: ["SPAudioDataType", "-json"])
        if spResult.success,
           let data = spResult.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let audio = json["SPAudioDataType"] as? [[String: Any]] {
            for device in audio {
                let name = device["_name"] as? String ?? "Unknown"
                let manufacturer = device["manufacturer"] as? String ?? "Unknown"
                let inputChannels = device["input_channels"] as? Int ?? 0
                let outputChannels = device["output_channels"] as? Int ?? 0
                let sampleRate = device["sample_rate"] as? Double ?? 48000

                devices.append(AudioDevice(
                    name: name,
                    manufacturer: manufacturer,
                    inputChannels: inputChannels,
                    outputChannels: outputChannels,
                    sampleRate: sampleRate
                ))
            }
        }

        return devices
    }

    private func collectBluetoothInfo() async throws -> BluetoothInfo? {
        let spResult = try await executor.run("/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"])
        if spResult.success,
           let data = spResult.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let bluetooth = json["SPBluetoothDataType"] as? [[String: Any]],
           let first = bluetooth.first {
            let version = first["bluetooth_version"] as? String ?? "Unknown"
            let address = first["bluetooth_address"] as? String ?? "Unknown"
            let features = first["supported_features"] as? [String] ?? []

            return BluetoothInfo(
                version: version,
                address: address,
                supportedFeatures: features
            )
        }
        return nil
    }

    // MARK: - Software Info

    private func collectSoftwareInfo() async throws -> SoftwareInfo {
        let swResult = try await executor.run("/usr/bin/sw_vers")
        var osVersion = "Unknown"
        var osBuild = "Unknown"

        if swResult.success {
            for line in swResult.stdout.components(separatedBy: .newlines) {
                if line.contains("ProductVersion:") {
                    osVersion = line.replacingOccurrences(of: "ProductVersion:", with: "").trimmingCharacters(in: .whitespaces)
                } else if line.contains("BuildVersion:") {
                    osBuild = line.replacingOccurrences(of: "BuildVersion:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
        }

        let kernelResult = try await executor.run("/usr/bin/uname", arguments: ["-v"])
        let kernelVersion = kernelResult.stdout.trimmingCharacters(in: .whitespaces)

        let bootTime = await getBootTime()
        let uptime = Date().timeIntervalSince(bootTime)

        // Xcode version
        var xcodeVersion: String? = nil
        let xcodeResult = try await executor.run("/usr/bin/xcodebuild", arguments: ["-version"])
        if xcodeResult.success {
            xcodeVersion = xcodeResult.stdout.components(separatedBy: .newlines).first
        }

        // Homebrew
        var homebrewVersion: String? = nil
        if await executor.isAvailable("brew") {
            let brewResult = try await executor.run("brew", arguments: ["--version"])
            homebrewVersion = brewResult.stdout.components(separatedBy: .newlines).first
        }

        // Docker
        var dockerVersion: String? = nil
        if await executor.isAvailable("docker") {
            let dockerResult = try await executor.run("docker", arguments: ["--version"])
            dockerVersion = dockerResult.stdout.trimmingCharacters(in: .whitespaces)
        }

        // Login items
        let loginItems = try await collectLoginItems()

        // Launch agents/daemons
        let launchAgents = try await collectLaunchItems(user: true)
        let launchDaemons = try await collectLaunchItems(user: false)

        return SoftwareInfo(
            osVersion: osVersion,
            osBuild: osBuild,
            kernelVersion: kernelVersion,
            bootTime: bootTime,
            uptime: uptime,
            xcodeVersion: xcodeVersion,
            homebrewVersion: homebrewVersion,
            dockerVersion: dockerVersion,
            installedPackages: 0, // Would need pkgutil count
            loginItems: loginItems,
            launchAgents: launchAgents,
            launchDaemons: launchDaemons
        )
    }

    private func getBootTime() async -> Date {
        do {
            let uptimeResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "kern.boottime"])
            if uptimeResult.success {
                // Parse: sec = 1234567890, usec = 123456
                let pattern = #"sec = (\d+)"#
                let regex = try? NSRegularExpression(pattern: pattern)
                let range = NSRange(location: 0, length: uptimeResult.stdout.utf16.count)
                if let match = regex?.firstMatch(in: uptimeResult.stdout, options: [], range: range),
                   let range = Range(match.range(at: 1), in: uptimeResult.stdout),
                   let seconds = Int(uptimeResult.stdout[range]) {
                    return Date(timeIntervalSince1970: TimeInterval(seconds))
                }
            }
        } catch {
            // Ignore error, fall back to system uptime
        }
        return Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
    }

    private func collectLoginItems() async throws -> [LoginItem] {
        var items: [LoginItem] = []

        let script = """
        tell application "System Events"
            get the name, path, hidden, bundle identifier of every login item
        end tell
        """

        let result = try await executor.run("/usr/bin/osascript", arguments: ["-e", script])
        if result.success {
            // Parse osascript output - simplified
        }

        return items
    }

    private func collectLaunchItems(user: Bool) async throws -> [LaunchItem] {
        var items: [LaunchItem] = []

        let dirs = user ?
            ["~/Library/LaunchAgents".expandingTildeInPath] :
            ["/Library/LaunchAgents", "/Library/LaunchDaemons"]

        for dir in dirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            let plists = contents.filter { $0.hasSuffix(".plist") }

            for plist in plists {
                let path = (dir as NSString).appendingPathComponent(plist)
                if let data = FileManager.default.contents(atPath: path),
                   let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {

                    items.append(LaunchItem(
                        label: dict["Label"] as? String ?? plist,
                        program: dict["Program"] as? String,
                        programArguments: dict["ProgramArguments"] as? [String],
                        runAtLoad: dict["RunAtLoad"] as? Bool ?? false,
                        keepAlive: dict["KeepAlive"] as? Bool ?? false,
                        disabled: dict["Disabled"] as? Bool ?? false,
                        path: path
                    ))
                }
            }
        }

        return items
    }

    // MARK: - Storage Info

    private func collectStorageInfo() async throws -> [StorageInfo] {
        var storage: [StorageInfo] = []

        let dfResult = try await executor.run("/bin/df", arguments: ["-H"])
        let lines = dfResult.stdout.components(separatedBy: .newlines).dropFirst()

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 6 else { continue }

            let device = String(parts[0])
            let totalGB = Double(parts[1]) ?? 0
            let usedGB = Double(parts[2]) ?? 0
            let freeGB = Double(parts[3]) ?? 0
            let mountPoint = String(parts[5])

            // Skip virtual filesystems
            if device.hasPrefix("devfs") || device.hasPrefix("map ") || device.hasPrefix("tmpfs") {
                continue
            }

            // Get filesystem info
            let fsResult = try await executor.run("/usr/sbin/diskutil", arguments: ["info", device])
            var fileSystem = "Unknown"
            var isEncrypted = false
            var isBoot = mountPoint == "/"
            var apfsContainer: String? = nil
            var trimSupport = false

            if fsResult.success {
                for fsLine in fsResult.stdout.components(separatedBy: .newlines) {
                    if fsLine.contains("File System Personality:") {
                        fileSystem = fsLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
                    } else if fsLine.contains("Encrypted:") {
                        isEncrypted = fsLine.contains("Yes")
                    } else if fsLine.contains("APFS Container:") {
                        apfsContainer = fsLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
                    } else if fsLine.contains("TRIM Support:") {
                        trimSupport = fsLine.contains("Yes")
                    }
                }
            }

            // SMART status
            let smartResult = try await executor.run("/usr/sbin/smartctl", arguments: ["-H", device])
            var smartStatus = "Unknown"
            if smartResult.success {
                if smartResult.stdout.contains("PASSED") { smartStatus = "PASSED" }
                else if smartResult.stdout.contains("FAILED") { smartStatus = "FAILED" }
            }

            storage.append(StorageInfo(
                device: device,
                mountPoint: mountPoint,
                fileSystem: fileSystem,
                totalGB: totalGB / 1_000_000_000,
                freeGB: freeGB / 1_000_000_000,
                usedGB: usedGB / 1_000_000_000,
                apfsContainer: apfsContainer,
                isEncrypted: isEncrypted,
                isBoot: isBoot,
                smartStatus: smartStatus,
                trimSupport: trimSupport
            ))
        }

        return storage
    }

    // MARK: - Network Info

    private func collectNetworkInfo() async throws -> NetworkInfo {
        var interfaces: [NetworkInterface] = []

        let ifconfigResult = try await executor.run("/sbin/ifconfig")
        let sections = ifconfigResult.stdout.split(separator: "\n\n")

        for section in sections {
            let lines = section.split(separator: "\n")
            guard let firstLine = lines.first else { continue }

            let name = firstLine.split(separator: ":")[0].trimmingCharacters(in: .whitespaces)
            var displayName = name
            var type = "Unknown"
            var macAddress = ""
            var ipv4Addresses: [String] = []
            var ipv6Addresses: [String] = []
            var mtu = 0
            var speed = "Unknown"
            var status = "inactive"
            var bytesIn: Int64 = 0
            var bytesOut: Int64 = 0

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("status:") {
                    status = trimmed.replacingOccurrences(of: "status:", with: "").trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("ether ") {
                    macAddress = trimmed.replacingOccurrences(of: "ether ", with: "").trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("inet ") {
                    let parts = trimmed.split(separator: " ")
                    if parts.count > 1 {
                        ipv4Addresses.append(String(parts[1]))
                    }
                } else if trimmed.hasPrefix("inet6 ") {
                    let parts = trimmed.split(separator: " ")
                    if parts.count > 1 {
                        ipv6Addresses.append(String(parts[1]))
                    }
                } else if trimmed.hasPrefix("mtu ") {
                    mtu = Int(trimmed.split(separator: " ")[1]) ?? 0
                }
            }

            // Get traffic stats
            let netstatResult = try await executor.run("/usr/sbin/netstat", arguments: ["-ibn", "-I", name])
            if netstatResult.success {
                let stats = netstatResult.stdout.components(separatedBy: .newlines).dropFirst()
                for stat in stats {
                    let parts = stat.split(separator: " ", omittingEmptySubsequences: true)
                    if parts.count >= 10 {
                        bytesIn = Int64(parts[6]) ?? 0
                        bytesOut = Int64(parts[9]) ?? 0
                        break
                    }
                }
            }

            // Determine type
            if name.hasPrefix("en") { type = "Ethernet"; displayName = "Ethernet" }
            else if name.hasPrefix("lo") { type = "Loopback"; displayName = "Loopback" }
            else if name.hasPrefix("awdl") { type = "AWDL"; displayName = "Apple Wireless Direct" }
            else if name.hasPrefix("llw") { type = "Low Latency"; displayName = "Low Latency" }
            else if name.hasPrefix("utun") { type = "VPN"; displayName = "VPN Tunnel" }
            else if name.hasPrefix("bridge") { type = "Bridge"; displayName = "Bridge" }

            interfaces.append(NetworkInterface(
                name: name,
                displayName: displayName,
                type: type,
                macAddress: macAddress,
                ipv4Addresses: ipv4Addresses,
                ipv6Addresses: ipv6Addresses,
                mtu: mtu,
                speed: speed,
                status: status,
                bytesIn: bytesIn,
                bytesOut: bytesOut
            ))
        }

        // DNS servers
        let dnsResult = try await executor.run("/usr/sbin/networksetup", arguments: ["-getdnsservers", "Wi-Fi"])
        let dnsServers = dnsResult.success ? dnsResult.stdout.components(separatedBy: .newlines).filter { !$0.contains("There aren't") } : []

        // Search domains
        let searchResult = try await executor.run("/usr/sbin/networksetup", arguments: ["-getsearchdomains", "Wi-Fi"])
        let searchDomains = searchResult.success ? searchResult.stdout.components(separatedBy: .newlines).filter { !$0.contains("There aren't") } : []

        // Default route
        let routeResult = try await executor.run("/usr/sbin/netstat", arguments: ["-rn", "-f", "inet"])
        var defaultRoute: String? = nil
        if routeResult.success {
            for line in routeResult.stdout.components(separatedBy: .newlines) {
                if line.hasPrefix("default") {
                    defaultRoute = line.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first.map(String.init)
                    break
                }
            }
        }

        // Public IP
        let publicIPResult = try await executor.run("/usr/bin/curl", arguments: ["-s", "https://api.ipify.org"])
        let publicIP = publicIPResult.success ? publicIPResult.stdout : nil

        return NetworkInfo(
            interfaces: interfaces,
            dnsServers: dnsServers,
            searchDomains: searchDomains,
            defaultRoute: defaultRoute,
            publicIP: publicIP,
            vpnConnections: []
        )
    }

    // MARK: - Security Info

    private func collectSecurityInfo() async throws -> SecurityInfo {
        // SIP
        let sipResult = try await executor.run("/usr/bin/csrutil", arguments: ["status"])
        let sipEnabled = sipResult.stdout.contains("enabled")

        // AMFI
        let amfiResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "kern.amfi.trustcache.enabled"])
        let amfiEnabled = amfiResult.stdout.trimmingCharacters(in: .whitespaces) == "1"

        // Gatekeeper
        let gkResult = try await executor.run("/usr/sbin/spctl", arguments: ["--status"])
        let gatekeeperEnabled = gkResult.stdout.contains("enabled")

        // Firewall
        let fwResult = try await executor.run("/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--getglobalstate"])
        let firewallEnabled = fwResult.stdout.contains("enabled")

        let fwStealthResult = try await executor.run("/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--getstealthmode"])
        let firewallStealthMode = fwStealthResult.stdout.contains("enabled")

        // FileVault
        let fvResult = try await executor.run("/usr/bin/fdesetup", arguments: ["status"])
        let fileVaultEnabled = fvResult.stdout.contains("On")

        // Secure Boot
        let sbResult = try await executor.run("/usr/sbin/nvram", arguments: ["-p"])
        let secureBoot = sbResult.stdout.contains("SecureBootModel") ? "Full" : "None"

        // System Extensions
        let seResult = try await executor.run("/usr/bin/systemextensionsctl", arguments: ["list"])
        let systemExtensions = seResult.success ? seResult.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("---") } : []

        // Kernel Extensions (legacy)
        let kextResult = try await executor.run("/usr/sbin/kextstat", arguments: ["-l"])
        let kernelExtensions = kextResult.success ? kextResult.stdout.components(separatedBy: .newlines).dropFirst().map { $0.split(separator: " ").last.map(String.init) ?? "" }.filter { !$0.isEmpty } : []

        // TCC Databases
        let tccDatabases = try await collectTCCInfo()

        // Certificates
        let certificates = try await collectCertificateInfo()

        return SecurityInfo(
            sipEnabled: sipEnabled,
            amfiEnabled: amfiEnabled,
            gatekeeperEnabled: gatekeeperEnabled,
            firewallEnabled: firewallEnabled,
            firewallStealthMode: firewallStealthMode,
            fileVaultEnabled: fileVaultEnabled,
            secureBoot: secureBoot,
            systemExtensions: systemExtensions,
            kernelExtensions: kernelExtensions,
            tccDatabases: tccDatabases,
            certificates: certificates
        )
    }

    private func collectTCCInfo() async throws -> [TCCDatabase] {
        var databases: [TCCDatabase] = []

        let tccPaths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "~/Library/Application Support/com.apple.TCC/TCC.db".expandingTildeInPath
        ]

        for path in tccPaths where FileManager.default.fileExists(atPath: path) {
            let result = try await executor.run("/usr/bin/sqlite3", arguments: [path, "SELECT service, COUNT(*) FROM access WHERE allowed=1 GROUP BY service;"])
            if result.success {
                var allowedApps = 0, deniedApps = 0, promptCount = 0
                for line in result.stdout.components(separatedBy: .newlines) {
                    let parts = line.split(separator: "|")
                    if parts.count == 2, let count = Int(parts[1]) {
                        allowedApps += count
                    }
                }

                let deniedResult = try await executor.run("/usr/bin/sqlite3", arguments: [path, "SELECT COUNT(*) FROM access WHERE allowed=0;"])
                if deniedResult.success {
                    deniedApps = Int(deniedResult.stdout.trimmingCharacters(in: .whitespaces)) ?? 0
                }

                let promptResult = try await executor.run("/usr/bin/sqlite3", arguments: [path, "SELECT COUNT(*) FROM access WHERE prompt_count > 0;"])
                if promptResult.success {
                    promptCount = Int(promptResult.stdout.trimmingCharacters(in: .whitespaces)) ?? 0
                }

                databases.append(TCCDatabase(
                    service: path.contains("Library/Application Support/com.apple.TCC") ? "System" : "User",
                    allowedApps: allowedApps,
                    deniedApps: deniedApps,
                    promptCount: promptCount
                ))
            }
        }

        return databases
    }

    private func collectCertificateInfo() async throws -> CertificateInfo {
        var systemRoot = 0, system = 0, user = 0, expired = 0, expiringSoon = 0

        let keychains = [
            "/System/Library/Keychains/SystemRootCertificates.keychain",
            "/Library/Keychains/System.keychain",
            "~/Library/Keychains/login.keychain-db".expandingTildeInPath
        ]

        for (index, keychain) in keychains.enumerated() {
            let result = try await executor.run("/usr/bin/security", arguments: ["find-certificate", "-a", "-c", "", keychain])
            if result.success {
                let count = result.stdout.components(separatedBy: "-----END CERTIFICATE-----").count - 1
                switch index {
                case 0: systemRoot = count
                case 1: system = count
                case 2: user = count
                default: break
                }
            }
        }

        // Check for expired (simplified)
        return CertificateInfo(
            systemRoot: systemRoot,
            system: system,
            user: user,
            expired: expired,
            expiringSoon: expiringSoon
        )
    }

    // MARK: - Performance Snapshot

    private func collectPerformanceSnapshot() async throws -> PerformanceSnapshot {
        let cpuResult = try await executor.run("/usr/bin/ps", arguments: ["-A", "-o", "%cpu"])
        let cpuUsage = cpuResult.stdout.components(separatedBy: .newlines).dropFirst()
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .reduce(0, +)

        let memResult = try await executor.run("/usr/bin/vm_stat")
        let mem = parseVMStat(memResult.stdout)
        let totalPages = mem.free + mem.active + mem.inactive + mem.wired + mem.compressed
        let usedPages = totalPages - mem.free
        let memPressure = totalPages > 0 ? Double(usedPages) / Double(totalPages) * 100 : 0

        let diskResult = try await executor.run("/bin/df", arguments: ["/"])
        let diskUsage = diskResult.stdout.components(separatedBy: .newlines).dropFirst()
            .compactMap { line -> Double? in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 5, let used = Double(parts[2]), let total = Double(parts[1]) {
                    return used / total * 100
                }
                return nil
            }.first ?? 0

        let loadResult = try await executor.run("/usr/bin/uptime")
        let loadAvg = parseLoadAverage(loadResult.stdout)

        let topProcess = try await getTopProcess()

        return PerformanceSnapshot(
            cpuUsage: cpuUsage,
            memoryPressure: memPressure > 80 ? "High" : memPressure > 60 ? "Moderate" : "Normal",
            diskUsage: diskUsage,
            loadAverage: loadAvg,
            topProcess: topProcess,
            temperatureCelsius: nil
        )
    }

    private func parseLoadAverage(_ output: String) -> LoadAverage {
        let pattern = #"load averages?: ([\d.]+) ([\d.]+) ([\d.]+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: output.utf16.count)
        if let match = regex?.firstMatch(in: output, options: [], range: range),
           let r1 = Range(match.range(at: 1), in: output),
           let r2 = Range(match.range(at: 2), in: output),
           let r3 = Range(match.range(at: 3), in: output) {
            return LoadAverage(
                Double(output[r1]) ?? 0,
                Double(output[r2]) ?? 0,
                Double(output[r3]) ?? 0
            )
        }
        return LoadAverage(0, 0, 0)
    }

    private struct VMStat {
        let free: Int
        let active: Int
        let inactive: Int
        let wired: Int
        let compressed: Int
    }

    private func parseVMStat(_ output: String) -> VMStat {
        var free = 0, active = 0, inactive = 0, wired = 0, compressed = 0
        for line in output.components(separatedBy: .newlines) {
            if line.contains("Pages free:") { free = extractNumber(from: line) ?? 0 }
            else if line.contains("Pages active:") { active = extractNumber(from: line) ?? 0 }
            else if line.contains("Pages inactive:") { inactive = extractNumber(from: line) ?? 0 }
            else if line.contains("Pages wired down:") { wired = extractNumber(from: line) ?? 0 }
            else if line.contains("Pages occupied by compressor:") { compressed = extractNumber(from: line) ?? 0 }
        }
        return VMStat(free: free, active: active, inactive: inactive, wired: wired, compressed: compressed)
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

    private func getTopProcess() async throws -> String {
        let psResult = try await executor.run("/usr/bin/ps", arguments: ["-eo", "pcpu,comm", "-r"])
        let lines = psResult.stdout.components(separatedBy: .newlines).dropFirst()
        if let first = lines.first {
            let parts = first.trimmingCharacters(in: .whitespaces).split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[1]) (\(parts[0])%)"
            }
        }
        return "Unknown"
    }

    // MARK: - Verification

    private func runVerification() async throws -> VerificationSummary {
        let verification = SystemVerification()
        return try await verification.runVerification(types: VerificationType.allCases, verbose: false, autoFix: false)
    }
}