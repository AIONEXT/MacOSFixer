# MacOSFixer

A comprehensive macOS diagnostic, repair, and performance analysis tool written in Swift. Fix common macOS issues, analyze system performance, and get a complete overview of your machine.

## Features

### 🔍 Diagnostics
- **Hardware**: CPU, memory, thermal, battery, SMART disk health
- **Disk**: APFS container usage, filesystem integrity, TRIM status, snapshots
- **Memory**: VM stats, memory pressure, swap usage
- **Network**: Interface status, DNS resolution, connectivity, firewall
- **Software**: macOS version, updates, Homebrew, Xcode, login items
- **Security**: SIP, Gatekeeper, AMFI, FileVault, firewall, certificates
- **Performance**: Load average, top processes
- **Logs**: System log size, kernel panics, crash reports
- **Launch Services**: Launch agents/daemons validation
- **Privacy (TCC)**: Database integrity, permissions

### 🔧 Repair
- **Permissions**: Home directory ownership, user permissions reset
- **Disk**: Snapshot thinning, volume verification, TRIM enablement
- **Caches**: System/user/app caches, font caches, DNS cache
- **Logs**: Old log rotation, ASL cleanup
- **Preferences**: Corrupt plist detection/removal, cfprefsd restart
- **Launchd**: Broken launch item validation/disabling
- **Spotlight**: Index rebuild, metadata reset
- **Docker**: Container/image/volume/builder pruning
- **Homebrew**: Update, upgrade, cleanup, doctor
- **Keychain**: Login/system keychain verification/repair
- **TCC**: Database reset guidance (requires Recovery Mode)
- **Fonts**: ATS cache clearing, font server restart
- **Metadata**: Extended attributes, Launch Services rebuild

### 🧹 Cleanup
- **User**: ~/Library/Caches, Logs, Containers, Saved State, temp
- **System**: /Library/Caches, /var/log, /private/var/folders
- **Apps**: Application Support caches
- **Docker**: System prune, builder cache
- **Xcode**: DerivedData, Archives, DeviceSupport, Simulators
- **Node.js**: npm/yarn/pnpm cache, node_modules
- **Python**: pip/pipx/conda/poetry cache, __pycache__
- **Rust**: cargo clean, registry cache
- **Go**: Module/build cache
- **Java**: Maven/Gradle cache
- **Browsers**: Safari, Chrome, Firefox, Edge, Brave caches
- **Mail**: Downloads, Envelope Index
- **Trash**: ~/.Trash, volume Trash

### ✅ Verification
- **Filesystem**: fsck, APFS volume verification, snapshots
- **Packages**: pkgutil verification, signature checks
- **Binaries**: System binary code signatures
- **Preferences**: Plist validity
- **Keychain**: Login/system keychain integrity
- **TCC**: Database integrity, duplicate entries
- **Code Signing**: SIP, AMFI status
- **SIP**: System Integrity Protection
- **AMFI**: Trust cache
- **Launchd**: Missing programs, non-existent executables
- **Cron**: User/system crontabs, periodic scripts
- **Login Items**: Count and performance impact

### 📊 Performance Analysis
- **CPU**: Usage breakdown, load average, frequency, temperature
- **Memory**: Usage, pressure, swap, compression
- **Disk**: I/O rates, latency, SSD detection, SMART
- **Network**: Throughput, errors, collisions, interface speed
- **GPU**: Utilization, VRAM, Metal support, temperature
- **Thermal**: CPU/GPU temp, fan speed, pressure, throttling
- **Power**: Battery level, health, cycles, charging, time remaining
- **Processes**: Top CPU/memory consumers
- **Bottlenecks**: Automatic detection with recommendations

### 🖥️ Machine Overview Matrix
Complete system inventory including:
- Hardware: Model, CPU, memory, GPU, audio, Bluetooth
- Software: macOS version, kernel, Xcode, Homebrew, Docker, login items, launch items
- Storage: All volumes with usage, encryption, SMART, TRIM
- Network: Interfaces, IPs, DNS, routes, public IP, VPN
- Security: SIP, Gatekeeper, FileVault, firewall, extensions, TCC, certificates
- Performance: Real-time snapshot

### 🌐 Web Dashboard
Real-time interactive dashboard at `http://localhost:8080` with:
- System overview cards
- Live performance charts (CPU, Memory, Disk I/O, Network)
- Diagnostics table with status
- Verification results
- Top processes table
- Bottleneck alerts
- Auto-refresh every 10 seconds

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6.0+
- Xcode 15+ or Command Line Tools

## Installation

### From Source
```bash
git clone https://github.com/yourusername/MacOSFixer.git
cd MacOSFixer
make build
make install  # Optional: installs to /usr/local/bin
```

### Using Make
```bash
make build       # Build release version
make test        # Run tests
make install     # Install to /usr/local/bin
```

### Homebrew (planned)
```bash
brew install macosfixer
```

## Usage

### Command Line

```bash
# Show help
macosfixer --help

# Complete machine overview
macosfixer overview

# Detailed diagnostics
macosfixer diagnose --detailed --format json

# Repair all issues (dry-run first)
macosfixer repair --dry-run
macosfixer repair --category disk --force

# Cleanup (dry-run first)
macosfixer cleanup --dry-run
macosfixer cleanup --category docker,xcode --min-age 30

# Performance analysis
macosfixer performance --duration 60 --thermal --power

# System verification
macosfixer verify --type all --verbose

# Web dashboard
macosfixer dashboard --port 8080 --open
```

### Subcommands

| Command | Description |
|---------|-------------|
| `overview` | Complete machine overview matrix |
| `diagnose` | Run comprehensive diagnostics |
| `repair` | Fix common macOS issues |
| `cleanup` | Clean caches, logs, temp files |
| `verify` | Verify system integrity |
| `performance` | Analyze performance & bottlenecks |
| `dashboard` | Launch web dashboard |

### Options

**Global Options:**
- `--format` - Output format: `table` (default), `json`, `yaml`, `html`, `csv`
- `--save` - Save results to file
- `--verbose` - Verbose output

**Repair Options:**
- `--category` - Specific category: `all`, `permissions`, `disk`, `caches`, `logs`, `prefs`, `launchd`, `spotlight`, `docker`, `homebrew`, `keychain`, `tcc`, `fonts`, `metadata`
- `--dry-run` - Show what would be fixed
- `--force` - Run without confirmation
- `--backup` - Create backup before repairs

**Cleanup Options:**
- `--category` - Specific category: `all`, `user`, `system`, `apps`, `docker`, `xcode`, `node`, `python`, `rust`, `go`, `java`, `browsers`, `mail`, `trash`
- `--dry-run` - Show what would be cleaned
- `--min-age` - Minimum file age in days (default: 7)
- `--verbose` - Show size before/after

**Performance Options:**
- `--duration` - Monitoring duration in seconds (default: 30)
- `--thermal` - Include thermal throttling analysis
- `--power` - Include power/energy analysis

**Verification Options:**
- `--type` - Verification type: `all`, `filesystem`, `packages`, `binaries`, `prefs`, `keychain`, `tcc`, `codesign`, `sip`, `amfi`, `launchd`, `cron`, `login-items`
- `--auto-fix` - Automatically fix detected issues

## Output Formats

### Table (Default)
Human-readable formatted tables with colors and alignment.

### JSON
Machine-readable JSON for scripting and integration.

### YAML
Human-readable YAML format.

### HTML
Generates standalone HTML report with embedded CSS/JS.

### CSV
Comma-separated values for spreadsheet import.

## Examples

### Automated Maintenance Script
```bash
#!/bin/bash
# Run weekly maintenance
macosfixer cleanup --category all --min-age 30
macosfixer repair --category caches,logs,spotlight --force
macosfixer verify --type filesystem,packages,keychain
```

### CI/CD Integration
```bash
# Check system health in CI
macosfixer diagnose --format json --save > diagnostics.json
macosfixer verify --type sip,amfi,codesign --format json
```

### Performance Monitoring
```bash
# 5-minute performance analysis with thermal/power
macosfixer performance --duration 300 --thermal --power --format json > perf.json
```

### Web Dashboard
```bash
# Start dashboard accessible on network
macosfixer dashboard --port 8080
# Open http://localhost:8080 in browser
```

## Architecture

```
MacOSFixer/
├── Package.swift              # Swift Package Manager manifest
├── Makefile                   # Build automation
├── Sources/
│   ├── MacOSFixer/
│   │   └── main.swift         # CLI entry point
│   └── MacOSFixerCore/        # Core library
│       ├── MacOSFixerCore.swift    # Module exports
│       ├── Types.swift           # Shared type definitions
│       ├── Diagnostics/
│       │   ├── SystemDiagnostics.swift
│       │   ├── MachineOverview.swift
│       │   └── SystemVerification.swift
│       ├── Repair/
│       │   ├── SystemRepair.swift
│       │   └── SystemCleanup.swift
│       ├── Performance/
│       │   └── PerformanceMonitor.swift
│       ├── UI/
│       │   └── WebDashboard.swift
│       └── Utils/
│           └── CommandExecutor.swift
├── Tests/
│   └── MacOSFixerTests.swift
└── Resources/
```

## Safety

- **Dry-run mode**: All repair/cleanup operations support `--dry-run` to preview changes
- **Backups**: Automatic backup creation before repairs (configurable)
- **Confirmation**: Requires `--force` for destructive operations
- **Recovery Mode**: Some operations (TRIM, TCC reset) require Recovery Mode - tool provides instructions
- **Non-destructive**: Verification and diagnostics are read-only

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Run `make test` and `make lint`
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Disclaimer

This tool modifies system files and settings. Always:
- Run with `--dry-run` first
- Have current backups (Time Machine)
- Understand what each operation does
- Use at your own risk

The authors are not responsible for any data loss or system issues.

## Commercial Deployment

### Code Signing

For commercial distribution, the application must be code-signed with a valid Apple Developer ID:

```bash
# Sign the binary
codesign --force --deep --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --options runtime \
  --timestamp \
  MacOSFixer.app

# Verify signature
codesign --verify --deep --strict --verbose=2 MacOSFixer.app
```

### Notarization

Submit the signed app for Apple notarization:

```bash
# Create DMG for notarization
hdiutil create -volname "MacOSFixer" -srcfolder MacOSFixer.app -ov -format UDZO MacOSFixer-1.0.0.dmg

# Submit for notarization
xcrun notarytool submit MacOSFixer-1.0.0.dmg \
  --apple-id "your@appleid.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password" \
  --wait

# Staple the notarization ticket
xcrun stapler staple MacOSFixer.app
```

### Distribution

1. **Direct Download**: Host the notarized DMG on your website
2. **Mac App Store**: Submit via App Store Connect (requires additional sandboxing)
3. **Homebrew**: Create a formula in homebrew-core or your own tap
4. **Sparkle**: Implement Sparkle framework for automatic updates

### Build for Distribution

```bash
# Clean build
make clean

# Build universal binary (Intel + Apple Silicon)
make universal

# Create app bundle
make app-bundle

# Create DMG
make dmg

# Sign and notarize (requires Apple Developer account)
# See Code Signing and Notarization sections above
```

## Dependencies & Licenses

### Direct Dependencies

| Package | Version | License | Repository |
|---------|---------|---------|------------|
| swift-argument-parser | 1.3.0+ | Apache-2.0 | [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) |
| swift-system | 1.4.0+ | Apache-2.0 | [apple/swift-system](https://github.com/apple/swift-system) |

### Transitive Dependencies

All transitive dependencies are Apache-2.0 or MIT licensed. See `Package.resolved` for complete dependency tree.

### License Compliance

- All dependencies use permissive licenses (Apache-2.0, MIT)
- No GPL or copyleft dependencies
- Suitable for commercial use
- License notices included in binary via `--static-swift-stdlib`

### Third-Party Licenses

See `THIRD_PARTY_LICENSES.md` for complete license texts of all dependencies.

## GitHub Repository Setup

### Repository Structure

```
MacOSFixer/
├── .github/
│   ├── workflows/
│   │   ├── ci.yml          # CI pipeline
│   │   ├── release.yml     # Release automation
│   │   └── notarize.yml    # Notarization workflow
│   ├── ISSUE_TEMPLATE/
│   └── PULL_REQUEST_TEMPLATE.md
├── Sources/
├── Tests/
├── Resources/
├── Package.swift
├── Package.resolved
├── Makefile
├── README.md
├── LICENSE
├── THIRD_PARTY_LICENSES.md
└── CHANGELOG.md
```

### CI/CD Pipeline

The `.github/workflows/ci.yml` includes:
- Swift 6.0+ build on macOS 14+
- Unit tests with coverage
- Static analysis (swiftlint, swift-format)
- Universal binary build
- DMG creation
- Code signing (with secrets)
- Notarization (with secrets)
- Release asset upload

### Release Process

1. Update version in `Package.swift` and `Makefile`
2. Update `CHANGELOG.md`
3. Create git tag: `git tag v1.0.0`
4. Push tag: `git push origin v1.0.0`
5. GitHub Actions builds, signs, notarizes, and creates release

## Support & Maintenance

- **Issues**: GitHub Issues for bug reports and feature requests
- **Security**: Report security issues privately via GitHub Security Advisories
- **Updates**: Automatic updates via Sparkle framework (planned)
- **Documentation**: Wiki and inline help (`macosfixer --help`)

---

*MacOSFixer - Professional macOS System Maintenance Tool*
*Built with Swift 6.0+ for macOS 14.0+*