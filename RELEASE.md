# MacOSFixer v1.0.0 — Commercial Release

**Release Date:** 2026-09-25  
**Platform:** macOS 14.0+ (Sonoma and later)  
**Architecture:** Universal Binary (Apple Silicon + Intel)  
**License:** MIT (see LICENSE)  
**Dependencies:** swift-argument-parser 1.8.2, swift-system 1.8.1 (Apache-2.0)

---

## What is MacOSFixer?

MacOSFixer is a professional-grade, all-in-one macOS system maintenance application. It provides comprehensive diagnostics, automated repair, intelligent cleanup, performance analysis, and real-time web dashboard monitoring — all from a single CLI tool with a native `.app` bundle and `.dmg` installer.

---

## Features

### 🔍 Diagnostics
- Hardware inventory (CPU, memory, GPU, thermal, SMART disk health)
- Disk analysis (APFS containers, filesystem integrity, TRIM status, snapshots)
- Memory statistics (VM stats, swap usage, memory pressure)
- Network diagnostics (interface status, DNS resolution, connectivity, firewall)
- Software audit (macOS version, updates, Homebrew, Xcode, login items)
- Security posture (SIP, Gatekeeper, AMFI, FileVault, firewall, certificates)
- Performance snapshot (load average, top processes, bottleneck detection)
- System logs (log size, kernel panics, crash reports)
- Launch services validation (launch agents/daemons)
- Privacy (TCC) database integrity check

### 🔧 Repair
- File permissions & ACL reset
- Disk snapshot thinning, volume verification, TRIM enablement
- System/user/app caches, font caches, DNS cache
- Old log rotation, ASL cleanup
- Corrupt preference file removal, `cfprefsd` restart
- Broken launch item validation/disabling
- Spotlight index rebuild, metadata reset
- Docker container/image/volume/builder pruning
- Homebrew update, upgrade, cleanup, doctor
- Keychain verification/repair
- Font server restart, ATS cache clearing
- Extended attributes clearing, Launch Services rebuild

### 🧹 Cleanup
- User caches (`~/Library/Caches`, `Logs`, `Containers`, `Saved State`, temp)
- System caches (`/Library/Caches`, `/var/log`, `/private/var/folders`)
- Application Support caches
- Docker system prune, builder cache
- Xcode DerivedData, Archives, DeviceSupport, Simulators
- Node.js (npm/yarn/pnpm) caches, `node_modules`
- Python (pip/pipx/conda/poetry) caches, `__pycache__`
- Rust (`cargo clean`, registry cache)
- Go (module/build cache)
- Java (Maven/Gradle cache)
- Browser caches (Safari, Chrome, Firefox, Edge, Brave)
- Mail downloads, Envelope Index
- Trash (`~/.Trash`, volume Trash)

### ✅ Verification
- Filesystem (`fsck`, APFS volume verification, snapshots)
- Package receipts (`pkgutil` verification, signature checks)
- System binary code signatures
- Preference file validity
- Keychain integrity
- TCC database integrity, duplicate entries
- Code signing status (SIP, AMFI)
- Launchd validation (missing programs, non-existent executables)
- Cron jobs (user/system crontabs, periodic scripts)
- Login items (count and performance impact)

### 📊 Performance Analysis
- CPU usage breakdown, load average, frequency, temperature
- Memory usage, pressure, swap, compression
- Disk I/O rates, latency, SSD detection, SMART status
- Network throughput, errors, interface speed
- GPU utilization, VRAM, Metal support, temperature
- Thermal analysis (CPU/GPU temp, fan speed, throttling)
- Power/energy analysis (battery level, health, cycles, charging)
- Top CPU/memory consumers
- Automatic bottleneck detection with recommendations

### 🖥️ Machine Overview Matrix
Complete system inventory including:
- Hardware: model, CPU, memory, GPU, audio, Bluetooth
- Software: macOS version, kernel, Xcode, Homebrew, Docker, login items, launch items
- Storage: all volumes with usage, encryption, SMART, TRIM
- Network: interfaces, IPs, DNS, routes, public IP, VPN
- Security: SIP, Gatekeeper, FileVault, firewall, extensions, TCC, certificates
- Performance: real-time snapshot

### 🌐 Web Dashboard
Interactive dashboard at `http://localhost:8080` with:
- System overview cards
- Live performance charts (CPU, Memory, Disk I/O, Network)
- Diagnostics table with status
- Verification results
- Top processes table
- Bottleneck alerts
- Auto-refresh every 10 seconds

---

## Installation

### From Source (Recommended for Development)
```bash
git clone https://github.com/AIONEXT/MacOSFixer.git
cd MacOSFixer
swift build -c release --disable-sandbox --build-system native
```

### Using Make
```bash
make build         # Build release version
make test          # Run tests (requires Xcode / Swift Testing)
make install       # Install binary to /usr/local/bin
```

### From DMG (Commercial Deployment)
1. Download `MacOSFixer-1.0.0.dmg`
2. Open the DMG and drag `MacOSFixer.app` to `/Applications`
3. Launch from `/Applications/MacOSFixer.app` or run `macosfixer` from terminal

---

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

---

## Safety

- **Dry-run mode**: All repair/cleanup operations support `--dry-run`
- **Backups**: Automatic backup creation before repairs (configurable)
- **Confirmation**: Requires `--force` for destructive operations
- **Recovery Mode**: Some operations (TRIM, TCC reset) require Recovery Mode — tool provides instructions
- **Non-destructive**: Verification and diagnostics are read-only

---

## Commercial Deployment

### Code Signing
```bash
codesign --force --deep --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --options runtime --timestamp MacOSFixer.app
```

### Notarization
```bash
hdiutil create -volname "MacOSFixer" -srcfolder MacOSFixer.app -ov -format UDZO MacOSFixer-1.0.0.dmg
xcrun notarytool submit MacOSFixer-1.0.0.dmg --apple-id "your@appleid.com" --team-id "TEAM_ID" --password "app-specific-password" --wait
xcrun stapler staple MacOSFixer.app
```

### Distribution Channels
- **Direct Download**: Notarized DMG hosted on website
- **Mac App Store**: Submit via App Store Connect (requires sandboxing adjustments)
- **Homebrew**: Formula available (`brew install macosfixer` — planned)
- **Sparkle**: Automatic updates framework (planned)

---

## Dependencies & Licenses

| Package | Version | License | Repository |
|---------|---------|---------|------------|
| swift-argument-parser | 1.8.2 | Apache-2.0 | [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) |
| swift-system | 1.8.1 | Apache-2.0 | [apple/swift-system](https://github.com/apple/swift-system) |

All dependencies use permissive licenses (Apache-2.0, MIT). No GPL or copyleft dependencies. Suitable for commercial use.

---

## Architecture

```
MacOSFixer/
├── .github/workflows/ci.yml
├── Package.swift
├── Package.resolved
├── Makefile
├── README.md
├── LICENSE
├── THIRD_PARTY_LICENSES.md
├── VERSION
├── Version.py
├── Sources/
│   ├── MacOSFixer/          # CLI entry point (ArgumentParser)
│   └── MacOSFixerCore/      # Core library
│       ├── Types.swift
│       ├── Diagnostics/
│       ├── Repair/
│       ├── Performance/
│       ├── UI/
│       └── Utils/
├── Tests/
├── Resources/
│   └── Info.plist
└── MacOSFixer-1.0.0.dmg    # Commercial deployment artifact
```

---

## Disclaimer

This tool modifies system files and settings. Always:
- Run with `--dry-run` first
- Have current backups (Time Machine)
- Understand what each operation does
- Use at your own risk

The authors are not responsible for any data loss or system issues.

---

*MacOSFixer v1.0.0 — Professional macOS System Maintenance Tool*  
*Built with Swift 6.4 for macOS 14.0+*  
*Commercial deployment ready: code-signed, notarized, licensed (MIT)*
