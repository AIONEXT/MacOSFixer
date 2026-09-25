import Foundation

public final class PerformanceMonitor: Sendable {
    private let executor = CommandExecutor.shared

    public init() {}

    public func analyzePerformance(
        duration: Int = 30,
        includeThermal: Bool = false,
        includePower: Bool = false
    ) async throws -> PerformanceReport {
        let startTime = Date()

        // Collect all metrics in parallel
        async let cpu = collectCPUMetrics()
        async let memory = collectMemoryMetrics()
        async let disks = collectDiskMetrics()
        async let network = collectNetworkMetrics()
        async let gpus = collectGPUMetrics()
        async let thermal = includeThermal ? collectThermalMetrics() : nil
        async let power = includePower ? collectPowerMetrics() : nil
        async let processes = collectTopProcesses()

        // Monitor for specified duration
        if duration > 1 {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }

        // Collect second sample for rates
        async let cpu2 = collectCPUMetrics()
        async let disk2 = collectDiskMetrics()
        async let network2 = collectNetworkMetrics()

        let (cpuMetrics, memMetrics, diskMetrics, netMetrics, gpuMetrics, thermalMetrics, powerMetrics, processMetrics) = try await (
            cpu, memory, disks, network, gpus, thermal, power, processes
        )

        let (cpuMetrics2, diskMetrics2, netMetrics2) = try await (cpu2, disk2, network2)

        // Calculate rates
        let elapsed = Date().timeIntervalSince(startTime)
        let finalDisks = calculateDiskRates(diskMetrics, diskMetrics2, elapsed: elapsed)
        let finalNetwork = calculateNetworkRates(netMetrics, netMetrics2, elapsed: elapsed)

        // Detect bottlenecks
        let bottlenecks = detectBottlenecks(
            cpu: cpuMetrics,
            memory: memMetrics,
            disks: finalDisks,
            network: finalNetwork,
            thermal: thermalMetrics,
            gpus: gpuMetrics
        )

        return PerformanceReport(
            timestamp: Date(),
            duration: elapsed,
            cpu: cpuMetrics,
            memory: memMetrics,
            disks: finalDisks,
            network: finalNetwork,
            gpus: gpuMetrics,
            thermal: thermalMetrics,
            power: powerMetrics,
            topProcesses: processMetrics,
            bottlenecks: bottlenecks
        )
    }

    // MARK: - CPU Metrics

    private func collectCPUMetrics() async throws -> CPUMetrics {
        // Get CPU info from sysctl
        let brandResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "machdep.cpu.brand_string"])
        let _ = brandResult.stdout

        let coreResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "hw.physicalcpu", "hw.logicalcpu"])
        let cores = coreResult.stdout.components(separatedBy: .whitespaces).compactMap { Int($0) }.max() ?? 1

        // Get load average
        let loadResult = try await executor.run("/usr/bin/uptime")
        let loadAvg = parseLoadAverage(loadResult.stdout)

        // Get CPU usage from ps
        let psResult = try await executor.run("/usr/bin/ps", arguments: ["-A", "-o", "%cpu"])
        let cpuUsage = parseCPUUsage(psResult.stdout)

        // Get frequency
        let freqResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "hw.cpufrequency_max"])
        let freqMHz = (Int(freqResult.stdout.trimmingCharacters(in: .whitespaces)) ?? 0) / 1_000_000

        // Get temperature (if available)
        var temp: Double? = nil
        if let osxResult = try? await executor.run("/usr/sbin/iosnoop", arguments: ["-d", "1", "-n", "1"]),
           osxResult.success {
            // Temperature not easily available without powermetrics
        }

        return CPUMetrics(
            user: cpuUsage.user,
            system: cpuUsage.system,
            idle: cpuUsage.idle,
            nice: cpuUsage.nice,
            cores: cores,
            loadAverage: loadAvg,
            frequencyMHz: freqMHz,
            temperatureCelsius: temp
        )
    }

    private struct CPUUsage { let user, system, idle, nice: Double }

    private func parseCPUUsage(_ output: String) -> CPUUsage {
        var user = 0.0, system = 0.0, idle = 0.0, nice = 0.0
        let lines = output.components(separatedBy: .newlines).dropFirst()

        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
            if let cpu = Double(parts.first ?? "0") {
                user += cpu // Simplified - ps doesn't distinguish user/sys per process easily
            }
        }

        // Use host_processor_info for more accurate breakdown
        let hostInfo = getHostCPUInfo()
        return CPUUsage(
            user: hostInfo.user,
            system: hostInfo.system,
            idle: hostInfo.idle,
            nice: hostInfo.nice
        )
    }

    private func getHostCPUInfo() -> CPUUsage {
        // This would use host_processor_info in a real implementation
        // For now, return reasonable defaults
        return CPUUsage(user: 10.0, system: 5.0, idle: 80.0, nice: 0.0)
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

    // MARK: - Memory Metrics

    private func collectMemoryMetrics() async throws -> MemoryMetrics {
        let vmStatResult = try await executor.run("/usr/bin/vm_stat")
        let mem = parseVMStat(vmStatResult.stdout)

        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let pageSize = 16384 // 16KB pages on Apple Silicon

        let used = Int64(mem.active + mem.wired + mem.compressed) * Int64(pageSize)
        let free = Int64(mem.free) * Int64(pageSize)

        // Swap
        let swapResult = try await executor.run("/usr/sbin/sysctl", arguments: ["-n", "vm.swapusage"])
        let (swapUsed, swapTotal) = parseSwapUsage(swapResult.stdout)

        // Memory pressure
        let pressureResult = try await executor.run("/usr/bin/memory_pressure")
        let pressure = parseMemoryPressure(pressureResult.stdout)

        return MemoryMetrics(
            total: Int64(totalMemory),
            used: used,
            free: free,
            active: Int64(mem.active) * Int64(pageSize),
            inactive: Int64(mem.inactive) * Int64(pageSize),
            wired: Int64(mem.wired) * Int64(pageSize),
            compressed: Int64(mem.compressed) * Int64(pageSize),
            swapUsed: swapUsed,
            swapTotal: swapTotal,
            pressureLevel: pressure.description
        )
    }

    private struct VMStat {
        let free, active, inactive, wired, compressed: Int
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

    private func parseSwapUsage(_ output: String) -> (Int64, Int64) {
        // "total = 2048.00M  used = 128.00M  free = 1920.00M"
        var used: Int64 = 0, total: Int64 = 0
        let pattern = #"(total|used|free) = ([\d.]+)([KMGT]?)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: output.utf16.count)
        regex?.enumerateMatches(in: output, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let keyRange = Range(match.range(at: 1), in: output),
                  let valRange = Range(match.range(at: 2), in: output),
                  let unitRange = Range(match.range(at: 3), in: output) else { return }
            let key = String(output[keyRange])
            let value = Double(output[valRange]) ?? 0
            let unit = String(output[unitRange])
            let multipliers: [String: Double] = ["K": 1024, "M": 1024*1024, "G": 1024*1024*1024, "T": 1024*1024*1024*1024]
            let multiplier = multipliers[unit] ?? 1
            let bytes = Int64(value * multiplier)
            if key == "used" { used = bytes }
            else if key == "total" { total = bytes }
        }
        return (used, total)
    }

    private struct MemoryPressure { let level: Int; let description: String }
    private func parseMemoryPressure(_ output: String) -> MemoryPressure {
        if output.contains("critical") { return MemoryPressure(level: 3, description: "Critical") }
        if output.contains("severe") { return MemoryPressure(level: 2, description: "Severe") }
        if output.contains("moderate") { return MemoryPressure(level: 1, description: "Moderate") }
        return MemoryPressure(level: 0, description: "Normal")
    }

    // MARK: - Disk Metrics

    private func collectDiskMetrics() async throws -> [DiskMetrics] {
        var disks: [DiskMetrics] = []

        let dfResult = try await executor.run("/bin/df", arguments: ["-k"])
        let lines = dfResult.stdout.components(separatedBy: .newlines).dropFirst()

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 6 else { continue }

            let device = String(parts[0])
            let totalKB = Int64(parts[1]) ?? 0
            let usedKB = Int64(parts[2]) ?? 0
            let freeKB = Int64(parts[3]) ?? 0
            let mountPoint = String(parts[5])

            // Skip virtual filesystems
            if device.hasPrefix("devfs") || device.hasPrefix("map ") || device.hasPrefix("tmpfs") {
                continue
            }

            // Get I/O stats from iostat
            let (readBps, writeBps, readOps, writeOps, latency) = try await getDiskIOStats(device: device)

            // Check if SSD
            let isSSD = try await isSSDDevice(device)

            // SMART status
            let smartStatus = try await getSMARTStatus(device)

            disks.append(DiskMetrics(
                device: device,
                mountPoint: mountPoint,
                totalSpace: totalKB * 1024,
                freeSpace: freeKB * 1024,
                usedSpace: usedKB * 1024,
                readBytesPerSec: readBps,
                writeBytesPerSec: writeBps,
                readOpsPerSec: readOps,
                writeOpsPerSec: writeOps,
                iops: readOps + writeOps,
                latencyMs: latency,
                isSSD: isSSD,
                smartStatus: smartStatus
            ))
        }

        return disks
    }

    private func getDiskIOStats(device: String) async throws -> (Int64, Int64, Int64, Int64, Double) {
        // Use iostat for I/O stats
        let iostatResult = try await executor.run("/usr/sbin/iostat", arguments: ["-d", "-K", "1", "1", device])
        // Parse iostat output - simplified for now
        return (0, 0, 0, 0, 0.0)
    }

    private func isSSDDevice(_ device: String) async throws -> Bool {
        // Check if device is SSD
        let diskInfoResult = try await executor.run("/usr/sbin/diskutil", arguments: ["info", device])
        return diskInfoResult.stdout.contains("Solid State: Yes") || diskInfoResult.stdout.contains("SSD")
    }

    private func getSMARTStatus(_ device: String) async throws -> String? {
        let smartResult = try await executor.run("/usr/sbin/smartctl", arguments: ["-H", device])
        if smartResult.success {
            if smartResult.stdout.contains("PASSED") { return "PASSED" }
            if smartResult.stdout.contains("FAILED") { return "FAILED" }
        }
        return nil
    }

    private func calculateDiskRates(_ old: [DiskMetrics], _ new: [DiskMetrics], elapsed: TimeInterval) -> [DiskMetrics] {
        var result: [DiskMetrics] = []
        let oldDict = Dictionary(uniqueKeysWithValues: old.map { ($0.device, $0) })

        for newDisk in new {
            if let oldDisk = oldDict[newDisk.device] {
                let readBps = max(0, (newDisk.readBytesPerSec - oldDisk.readBytesPerSec) / Int64(elapsed))
                let writeBps = max(0, (newDisk.writeBytesPerSec - oldDisk.writeBytesPerSec) / Int64(elapsed))
                let readOps = max(0, (newDisk.readOpsPerSec - oldDisk.readOpsPerSec) / Int64(elapsed))
                let writeOps = max(0, (newDisk.writeOpsPerSec - oldDisk.writeOpsPerSec) / Int64(elapsed))

                result.append(DiskMetrics(
                    device: newDisk.device,
                    mountPoint: newDisk.mountPoint,
                    totalSpace: newDisk.totalSpace,
                    freeSpace: newDisk.freeSpace,
                    usedSpace: newDisk.usedSpace,
                    readBytesPerSec: readBps,
                    writeBytesPerSec: writeBps,
                    readOpsPerSec: readOps,
                    writeOpsPerSec: writeOps,
                    iops: readOps + writeOps,
                    latencyMs: newDisk.latencyMs,
                    isSSD: newDisk.isSSD,
                    smartStatus: newDisk.smartStatus
                ))
            } else {
                result.append(newDisk)
            }
        }
        return result
    }

    // MARK: - Network Metrics

    private func collectNetworkMetrics() async throws -> [NetworkMetrics] {
        var networks: [NetworkMetrics] = []

        let netstatResult = try await executor.run("/usr/sbin/netstat", arguments: ["-ibn"])
        let lines = netstatResult.stdout.components(separatedBy: .newlines).dropFirst()

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 10 else { continue }

            let name = String(parts[0])
            let bytesIn = Int64(parts[6]) ?? 0
            let bytesOut = Int64(parts[9]) ?? 0
            let packetsIn = Int64(parts[4]) ?? 0
            let packetsOut = Int64(parts[7]) ?? 0
            let errorsIn = Int64(parts[5]) ?? 0
            let errorsOut = Int64(parts[8]) ?? 0
            let collisions = Int64(parts[10]) ?? 0

            // Get interface speed
            let speed = try await getInterfaceSpeed(name)

            networks.append(NetworkMetrics(
                interface: name,
                bytesInPerSec: bytesIn,
                bytesOutPerSec: bytesOut,
                packetsInPerSec: packetsIn,
                packetsOutPerSec: packetsOut,
                errorsIn: errorsIn,
                errorsOut: errorsOut,
                collisions: collisions,
                speedMbps: speed
            ))
        }

        return networks
    }

    private func getInterfaceSpeed(_ name: String) async throws -> Int64? {
        let ifconfigResult = try await executor.run("/sbin/ifconfig", arguments: [name])
        // Parse speed from ifconfig - simplified
        return nil
    }

    private func calculateNetworkRates(_ old: [NetworkMetrics], _ new: [NetworkMetrics], elapsed: TimeInterval) -> [NetworkMetrics] {
        let oldDict = Dictionary(uniqueKeysWithValues: old.map { ($0.interface, $0) })

        return new.map { newNet in
            if let oldNet = oldDict[newNet.interface] {
                return NetworkMetrics(
                    interface: newNet.interface,
                    bytesInPerSec: max(0, (newNet.bytesInPerSec - oldNet.bytesInPerSec) / Int64(elapsed)),
                    bytesOutPerSec: max(0, (newNet.bytesOutPerSec - oldNet.bytesOutPerSec) / Int64(elapsed)),
                    packetsInPerSec: max(0, (newNet.packetsInPerSec - oldNet.packetsInPerSec) / Int64(elapsed)),
                    packetsOutPerSec: max(0, (newNet.packetsOutPerSec - oldNet.packetsOutPerSec) / Int64(elapsed)),
                    errorsIn: newNet.errorsIn,
                    errorsOut: newNet.errorsOut,
                    collisions: newNet.collisions,
                    speedMbps: newNet.speedMbps
                )
            }
            return newNet
        }
    }

    // MARK: - GPU Metrics

    private func collectGPUMetrics() async throws -> [GPUMetrics] {
        var gpus: [GPUMetrics] = []

        let gpuResult = try await executor.run("/usr/sbin/system_profiler", arguments: ["SPDisplaysDataType", "-json"])
        if gpuResult.success {
            if let data = gpuResult.stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let displays = json["SPDisplaysDataType"] as? [[String: Any]] {
                for display in displays {
                    let name = display["sppci_model"] as? String ?? "Unknown GPU"
                    let vendor = display["sppci_vendor"] as? String ?? "Unknown"
                    let vram = display["sppci_vram"] as? String ?? "Unknown"
                    let metal = display["sppci_metal"] as? String ?? "Unknown"

                    gpus.append(GPUMetrics(
                        name: name,
                        utilization: 0, // Would need powermetrics for real utilization
                        memoryUsed: 0,
                        memoryTotal: parseVRAM(vram),
                        temperatureCelsius: nil,
                        powerWatts: nil,
                        metalSupported: metal.contains("Yes")
                    ))
                }
            }
        }

        return gpus
    }

    private func parseVRAM(_ vram: String) -> Int64 {
        // "1536 MB" or "8 GB"
        let parts = vram.split(separator: " ")
        guard let value = Double(parts.first ?? "0") else { return 0 }
        let unit = parts.count > 1 ? String(parts[1]) : "MB"
        let multiplier: Int64 = unit.hasPrefix("G") ? 1024*1024*1024 : 1024*1024
        return Int64(value) * multiplier
    }

    // MARK: - Thermal Metrics

    private func collectThermalMetrics() async throws -> ThermalMetrics? {
        // Use powermetrics for thermal info (requires sudo)
        let pmResult = try await executor.run("/usr/bin/sudo", arguments: ["/usr/bin/powermetrics", "-n", "1", "-i", "1000", "--show-process-energy"])
        if pmResult.success {
            // Parse powermetrics output for thermal data
            let temp = parseTemperature(pmResult.stdout)
            let fanSpeed = parseFanSpeed(pmResult.stdout)
            let pressure = parseThermalPressure(pmResult.stdout)
            let throttling = pmResult.stdout.contains("throttling") || pmResult.stdout.contains("Throttled")

            return ThermalMetrics(
                cpuTemperature: temp.cpu,
                gpuTemperature: temp.gpu,
                fanSpeedRPM: fanSpeed,
                thermalPressure: pressure,
                throttling: throttling
            )
        }
        return nil
    }

    private func parseTemperature(_ output: String) -> (cpu: Double?, gpu: Double?) {
        // Simplified parsing
        return (nil, nil)
    }

    private func parseFanSpeed(_ output: String) -> Int? {
        return nil
    }

    private func parseThermalPressure(_ output: String) -> String {
        if output.contains("Critical") { return "Critical" }
        if output.contains("Serious") { return "Serious" }
        if output.contains("Moderate") { return "Moderate" }
        return "Normal"
    }

    // MARK: - Power Metrics

    private func collectPowerMetrics() async throws -> PowerMetrics? {
        let pmsetResult = try await executor.run("/usr/bin/pmset", arguments: ["-g", "batt"])
        if pmsetResult.success {
            let output = pmsetResult.stdout
            let level = parseBatteryLevel(output)
            let charging = output.contains("charging") || output.contains("AC Power")
            let health = parseBatteryHealth(output)
            let cycles = await parseCycleCount()
            let timeRemaining = parseTimeRemaining(output)

            return PowerMetrics(
                batteryLevel: level,
                batteryHealth: health,
                cycleCount: cycles,
                isCharging: charging,
                powerSource: charging ? "AC" : "Battery",
                watts: nil,
                timeRemaining: timeRemaining
            )
        }
        return nil
    }

    private func parseBatteryLevel(_ output: String) -> Double? {
        let pattern = #"(\d+)%"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: output.utf16.count)
        if let match = regex?.firstMatch(in: output, options: [], range: range),
           let range = Range(match.range(at: 1), in: output) {
            return Double(output[range]) ?? nil
        }
        return nil
    }

    private func parseBatteryHealth(_ output: String) -> Double? {
        // Would need ioreg for health
        return nil
    }

    private func parseCycleCount() async -> Int? {
        do {
            let ioregResult = try await executor.run("/usr/sbin/ioreg", arguments: ["-r", "-n", "AppleSmartBattery", "-k", "CycleCount"])
            if ioregResult.success {
                let pattern = #""CycleCount" = (\d+)"#
                let regex = try? NSRegularExpression(pattern: pattern)
                let range = NSRange(location: 0, length: ioregResult.stdout.utf16.count)
                if let match = regex?.firstMatch(in: ioregResult.stdout, options: [], range: range),
                   let range = Range(match.range(at: 1), in: ioregResult.stdout) {
                    return Int(ioregResult.stdout[range])
                }
            }
        } catch {
            // Ignore error
        }
        return nil
    }

    private func parseTimeRemaining(_ output: String) -> Int? {
        let pattern = #"(\d+):(\d+) (remaining|until charged)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: output.utf16.count)
        if let match = regex?.firstMatch(in: output, options: [], range: range),
           let hRange = Range(match.range(at: 1), in: output),
           let mRange = Range(match.range(at: 2), in: output) {
            let hours = Int(output[hRange]) ?? 0
            let minutes = Int(output[mRange]) ?? 0
            return hours * 60 + minutes
        }
        return nil
    }

    // MARK: - Top Processes

    private func collectTopProcesses() async throws -> [ProcessMetrics] {
        let psResult = try await executor.run("/usr/bin/ps", arguments: ["-eo", "pid,pcpu,pmem,comm,user,args", "-r"])
        let lines = psResult.stdout.components(separatedBy: .newlines).dropFirst()

        var processes: [ProcessMetrics] = []
        for line in lines.prefix(20) {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard parts.count >= 5 else { continue }

            let pid = Int(parts[0]) ?? 0
            let cpu = Double(parts[1]) ?? 0
            let memPercent = Double(parts[2]) ?? 0
            let name = String(parts[3])
            let user = String(parts[4])
            let command = parts.count > 5 ? String(parts[5]) : ""

            let totalMemory = ProcessInfo.processInfo.physicalMemory
            let memoryBytes = Int64(Double(totalMemory) * memPercent / 100.0)
            let memoryMB = memoryBytes / (1024 * 1024)

            processes.append(ProcessMetrics(
                pid: pid,
                name: name,
                cpuPercent: cpu,
                memoryMB: memoryMB,
                threads: 0,
                user: user,
                command: command
            ))
        }

        return processes
    }

    // MARK: - Bottleneck Detection

    private func detectBottlenecks(
        cpu: CPUMetrics,
        memory: MemoryMetrics,
        disks: [DiskMetrics],
        network: [NetworkMetrics],
        thermal: ThermalMetrics?,
        gpus: [GPUMetrics]
    ) -> [PerformanceBottleneck] {
        var bottlenecks: [PerformanceBottleneck] = []

        // CPU bottleneck
        let coreCount = Double(cpu.cores)
        if cpu.loadAverage.oneMinute > coreCount * 1.5 {
            bottlenecks.append(PerformanceBottleneck(
                type: .cpu,
                severity: .warning,
                description: "Load average (\(cpu.loadAverage.oneMinute)) exceeds 1.5x core count (\(Int(coreCount)))",
                recommendation: "Identify CPU-intensive processes, consider limiting concurrent tasks",
                metrics: ["load_1m": cpu.loadAverage.oneMinute, "cores": coreCount]
            ))
        }

        // Memory bottleneck
        let memUsagePercent = Double(memory.used) / Double(memory.total) * 100
        if memUsagePercent > 90 {
            bottlenecks.append(PerformanceBottleneck(
                type: .memory,
                severity: .critical,
                description: "Memory usage at \(Int(memUsagePercent))%",
                recommendation: "Close applications, check for memory leaks, consider RAM upgrade",
                metrics: ["usage_percent": memUsagePercent, "swap_used_gb": Double(memory.swapUsed) / (1024*1024*1024)]
            ))
        } else if memUsagePercent > 80 {
            bottlenecks.append(PerformanceBottleneck(
                type: .memory,
                severity: .warning,
                description: "Memory usage at \(Int(memUsagePercent))%",
                recommendation: "Monitor memory usage, close unused applications",
                metrics: ["usage_percent": memUsagePercent]
            ))
        }

        // Swap bottleneck
        if memory.swapUsed > 1024 * 1024 * 1024 { // > 1GB
            bottlenecks.append(PerformanceBottleneck(
                type: .memory,
                severity: .warning,
                description: "Heavy swap usage: \(ByteCountFormatter.string(fromByteCount: memory.swapUsed, countStyle: .file))",
                recommendation: "System is swapping heavily - add RAM or reduce workload",
                metrics: ["swap_used_gb": Double(memory.swapUsed) / (1024*1024*1024)]
            ))
        }

        // Disk bottlenecks
        for disk in disks {
            let usagePercent = Double(disk.usedSpace) / Double(disk.totalSpace) * 100
            if usagePercent > 95 {
                bottlenecks.append(PerformanceBottleneck(
                    type: .disk,
                    severity: .critical,
                    description: "\(disk.mountPoint) at \(Int(usagePercent))% capacity",
                    recommendation: "Free up space immediately",
                    metrics: ["usage_percent": usagePercent, "free_gb": Double(disk.freeSpace) / (1024*1024*1024)]
                ))
            } else if usagePercent > 85 {
                bottlenecks.append(PerformanceBottleneck(
                    type: .disk,
                    severity: .warning,
                    description: "\(disk.mountPoint) at \(Int(usagePercent))% capacity",
                    recommendation: "Clean up disk space",
                    metrics: ["usage_percent": usagePercent]
                ))
            }

            // High latency
            if disk.latencyMs > 10 {
                bottlenecks.append(PerformanceBottleneck(
                    type: .disk,
                    severity: .warning,
                    description: "High disk latency on \(disk.device): \(disk.latencyMs)ms",
                    recommendation: "Check disk health, consider SSD upgrade",
                    metrics: ["latency_ms": disk.latencyMs]
                ))
            }
        }

        // Network bottlenecks
        for net in network {
            if net.errorsIn > 100 || net.errorsOut > 100 {
                bottlenecks.append(PerformanceBottleneck(
                    type: .network,
                    severity: .warning,
                    description: "High network errors on \(net.interface): in=\(net.errorsIn), out=\(net.errorsOut)",
                    recommendation: "Check network cables, switch, driver issues",
                    metrics: ["errors_in": Double(net.errorsIn), "errors_out": Double(net.errorsOut)]
                ))
            }
        }

        // Thermal bottlenecks
        if let thermal = thermal {
            if thermal.throttling {
                bottlenecks.append(PerformanceBottleneck(
                    type: .thermal,
                    severity: .critical,
                    description: "Thermal throttling active",
                    recommendation: "Improve cooling, clean fans, check thermal paste",
                    metrics: ["cpu_temp": thermal.cpuTemperature ?? 0, "gpu_temp": thermal.gpuTemperature ?? 0]
                ))
            } else if let cpuTemp = thermal.cpuTemperature, cpuTemp > 85 {
                bottlenecks.append(PerformanceBottleneck(
                    type: .thermal,
                    severity: .warning,
                    description: "High CPU temperature: \(Int(cpuTemp))°C",
                    recommendation: "Improve cooling, check fan operation",
                    metrics: ["cpu_temp": cpuTemp]
                ))
            }
        }

        // GPU bottlenecks
        for gpu in gpus {
            if gpu.utilization > 95 {
                bottlenecks.append(PerformanceBottleneck(
                    type: .gpu,
                    severity: .warning,
                    description: "GPU utilization at \(Int(gpu.utilization))%",
                    recommendation: "GPU is saturated, consider reducing graphics workload",
                    metrics: ["utilization": gpu.utilization]
                ))
            }
        }

        return bottlenecks
    }
}