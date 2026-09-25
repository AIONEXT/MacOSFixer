import Foundation

public struct CommandExecutor: Sendable {
    public static let shared = CommandExecutor()

    public struct Result: Sendable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
        public let duration: TimeInterval

        public var success: Bool { exitCode == 0 }
        public var output: String { stdout + stderr }
    }

    private init() {}

    @discardableResult
    public func run(
        _ command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        timeout: TimeInterval = 30,
        asRoot: Bool = false
    ) async throws -> Result {
        let startTime = Date()

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if asRoot {
            process.launchPath = "/usr/bin/sudo"
            process.arguments = [command] + arguments
        } else {
            process.launchPath = command
            process.arguments = arguments
        }

        if let env = environment {
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }

        if let cwd = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        try process.run()

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning {
                process.terminate()
                throw CommandError.timeout(command: command)
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let duration = Date().timeIntervalSince(startTime)

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return Result(
            exitCode: process.terminationStatus,
            stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration
        )
    }

    @discardableResult
    public func runShell(
        _ command: String,
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> Result {
        return try await run("/bin/zsh", arguments: ["-c", command], environment: environment, workingDirectory: workingDirectory, timeout: timeout)
    }

    public func runAsync(
        _ command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.launchPath = command
        process.arguments = arguments

        if let env = environment {
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }

        if let cwd = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        let stdoutTask = Task {
            for try await line in stdoutHandle.bytes.lines {
                onOutput(line)
            }
        }

        let stderrTask = Task {
            for try await line in stderrHandle.bytes.lines {
                onOutput("[stderr] \(line)")
            }
        }

        try process.run()
        process.waitUntilExit()

        stdoutTask.cancel()
        stderrTask.cancel()

        return process.terminationStatus
    }
}

public enum CommandError: Error, LocalizedError, Sendable {
    case timeout(command: String)
    case failed(command: String, exitCode: Int32, stderr: String)
    case notFound(command: String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let cmd):
            return "Command timed out: \(cmd)"
        case .failed(let cmd, let code, let stderr):
            return "Command failed: \(cmd) (exit code: \(code))\n\(stderr)"
        case .notFound(let cmd):
            return "Command not found: \(cmd)"
        }
    }
}

// MARK: - Convenience Extensions

extension CommandExecutor {
    public func which(_ command: String) async -> String? {
        do {
            let result = try await run("/usr/bin/which", arguments: [command])
            return result.success ? result.stdout : nil
        } catch {
            return nil
        }
    }

    public func isAvailable(_ command: String) async -> Bool {
        await which(command) != nil
    }
}

// MARK: - File System Utilities

public struct FileSystemUtils {
    public static func getDirectorySize(at path: String) throws -> Int64 {
        let url = URL(fileURLWithPath: path)
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var totalSize: Int64 = 0
        if let enumerator = enumerator {
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                if values.isDirectory != true {
                    totalSize += Int64(values.fileSize ?? 0)
                }
            }
        }
        return totalSize
    }

    public static func getFileAge(at path: String) -> TimeInterval? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            if let modDate = attrs[.modificationDate] as? Date {
                return Date().timeIntervalSince(modDate)
            }
        } catch {
            return nil
        }
        return nil
    }

    public static func isOlderThan(at path: String, days: Int) -> Bool {
        guard let age = getFileAge(at: path) else { return false }
        return age > TimeInterval(days * 24 * 60 * 60)
    }

    public static func safeRemoveItem(at path: String) -> Bool {
        do {
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    public static func calculateDirectorySize(_ path: String) -> Int64 {
        var totalSize: Int64 = 0
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }

        for case let file as String in enumerator {
            let fullPath = (path as NSString).appendingPathComponent(file)
            do {
                let attrs = try fileManager.attributesOfItem(atPath: fullPath)
                if let size = attrs[.size] as? Int64 {
                    totalSize += size
                }
            } catch {
                continue
            }
        }
        return totalSize
    }
}

// MARK: - JSON/YAML/Table Output Helpers

public extension Encodable {
    func toJSON(pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func toYAML() throws -> String {
        // Simple YAML conversion for basic types
        let json = try toJSON(pretty: false)
        // This is a simplified version - in production you'd use a proper YAML library
        return json
    }

    /// Renders the value as a standalone HTML report embedding pretty-printed JSON.
    func toHTML(title: String = "MacOSFixer Report") throws -> String {
        let json = try toJSON()
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
          body { font-family: -apple-system, sans-serif; margin: 2rem auto; max-width: 960px; padding: 0 1rem; color: #1d1d1f; }
          h1 { font-size: 1.5rem; }
          .meta { color: #6e6e73; font-size: 0.85rem; margin-bottom: 1.5rem; }
          pre { background: #f5f5f7; border-radius: 8px; padding: 1rem; overflow-x: auto; font-size: 0.8rem; line-height: 1.4; }
        </style>
        </head>
        <body>
        <h1>\(title)</h1>
        <div class="meta">Generated by MacOSFixer</div>
        <pre><code>\(json)</code></pre>
        </body>
        </html>
        """
    }
}

public protocol TableRenderable {
    func toTable() -> String
}

public func renderTable(headers: [String], rows: [[String]], alignments: [Alignment]? = nil) -> String {
    let alignments = alignments ?? Array(repeating: .left, count: headers.count)
    var columnWidths = headers.enumerated().map { index, header in
        max(header.count, rows.map { $0.count > index ? $0[index].count : 0 }.max() ?? 0)
    }

    // Cap column widths
    columnWidths = columnWidths.map { min($0, 60) }

    var lines: [String] = []

    // Header
    let headerLine = headers.enumerated().map { index, header in
        padString(header, width: columnWidths[index], alignment: alignments[index])
    }.joined(separator: " │ ")
    lines.append(headerLine)

    // Separator
    let separator = columnWidths.map { String(repeating: "─", count: $0) }.joined(separator: "─┼─")
    lines.append(separator)

    // Rows
    for row in rows {
        let paddedRow = row.enumerated().map { index, cell in
            let width = index < columnWidths.count ? columnWidths[index] : 20
            return padString(cell, width: width, alignment: index < alignments.count ? alignments[index] : .left)
        }.joined(separator: " │ ")
        lines.append(paddedRow)
    }

    return lines.joined(separator: "\n")
}

public enum Alignment { case left, right, center }

private func padString(_ string: String, width: Int, alignment: Alignment) -> String {
    let truncated = string.count > width ? String(string.prefix(width - 1)) + "…" : string
    let padding = width - truncated.count
    switch alignment {
    case .left: return truncated + String(repeating: " ", count: padding)
    case .right: return String(repeating: " ", count: padding) + truncated
    case .center:
        let left = padding / 2
        let right = padding - left
        return String(repeating: " ", count: left) + truncated + String(repeating: " ", count: right)
    }
}