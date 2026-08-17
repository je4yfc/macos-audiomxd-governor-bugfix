# `audiomxd` Spin-Loop & Log Flood Remediation for macOS Tahoe & Sequoia

[![macOS](https://img.shields.io/badge/macOS-15.x%20%7C%2026.x%20(Tahoe)-blue.svg)](https://apple.com)
[![Platform](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64e)-orange.svg)](https://apple.com)
[![Status](https://img.shields.io/badge/Status-Tested%20%26%20Verified-brightgreen.svg)]()
[![License: Unlicense](https://img.shields.io/badge/License-Unlicense-blue.svg)](LICENSE)

An open-source, production-proven remediation for the **macOS `audiomxd` 100% CPU runaway and Unified Log flood bug** affecting Apple Silicon Macs operating headless, in CI/CD build farms, or unattended at `loginwindow`.

---

## The Issue

On Apple Silicon Macs running macOS Tahoe 26.3 (Build 25D125) and macOS Sequoia 15.x, whenever the machine operates headless, unattended at `loginwindow`, or after an interactive GUI user logs out:

- **`/usr/libexec/audiomxd` consumes ~94% – 96% CPU** of a single core continuously.
- **Unified Log flood**: Emits over **24,800 log lines per second** (~1.48 million lines/minute) during unthrottled bursts.
- **Disk exhaustion**: In multi-day unattended operations, this flood fills `/var/db/diagnostics` and `/var/log` with **100+ GiB of duplicate error entries**, risking disk exhaustion.

```
audiomxd: (CoreUtils) [com.apple.bluetooth:BTAudioRoutingRequest] TargetUserSession NULL 0
audiomxd: (CoreUtils) [com.apple.bluetooth:BTAudioRoutingRequest] ### TargetUserSession, but no console user?
audiomxd: (CoreUtils) [com.apple.bluetooth:BTAudioRoutingRequest] ### UpdateAudioState failed to start XPC: kUnexpectedErr (No user logged in)
audiomxd: (CoreUtils) [com.apple.bluetooth:BTAudioRoutingRequest] ### audioaccessoryd died
audiomxd: (MediaExperience) [com.apple.coremedia:] -MXAudioAccessoryServices- -[MXAudioAccessoryServices handleServerDeath]: audioaccessoryd died :(
audiomxd: (CoreUtils) [com.apple.bluetooth:BTAudioRoutingRequest] Invalidating
audiomxd: (MediaExperience) [com.apple.coremedia:] -MXSessionManager- -[MXSessionManager audioAccessoryServerDiedCallback:]_block_invoke: Syncing with AudioAccessoryServices as they just recovered.
audiomxd: (CoreUtils) [com.apple.bluetooth:BTAudioRoutingRequest] UpdateAudioState CID 0x... audioState Stop apps {}
```

---

## Root Cause

1. **Session Boundary Constraint**: `/System/Library/CoreServices/audioaccessoryd` is managed by `/System/Library/LaunchAgents/com.apple.cloudpaird.plist` with `LimitLoadToSessionType = Aqua`. It is loaded only when an interactive user desktop session exists.
2. **Missing Console User Check**: `audiomxd` initializes `MXAudioAccessoryServices`, which instantiates `BTAudioRoutingRequest`. When `TargetUserSession == NULL`, it immediately fails with `kUnexpectedErr (-6700: No user logged in)` and posts `AudioAccessorydDiedNotification`.
3. **Zero-Backoff Dual Loop**: `-[MXAudioAccessoryServices handleServerDeath]` immediately reinitializes the connection, and `-[MXSessionManager audioAccessoryServerDiedCallback:]` immediately calls `updateAppState:startIO:` to "resync" with the daemon it believes recovered.
4. **Spin Frequency**: Without backoff, delay, or a console session check, this recursive cycle iterates every **177 microseconds** (~5,650 iterations/sec).

*For the complete low-level disassembly and function traces, see [Technical Deep Dive](technical_deep_dive/investigation_report.md).*

---

## Controlled Experiment Matrix

Evaluated on an Apple Silicon Mac mini running macOS Tahoe 26.3 (Build 25D125) at `loginwindow` (Console session: `root (0)`):

| Configuration Tested | Governor Active? | FeatureFlag Overrides | `audiomxd` CPU | `audiomxd` STAT | 10s Stream Count* | Loop Signatures Present? | CoreAudio HAL Status | Hardware Outputs | Result |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Stock macOS (Unpatched)** | NO | None (Stock) | 95.7% | Rs (Running) | 311 lines | Yes (3/3) | Active (0.0% CPU) | 3 endpoints | **SPINNING** |
| **FeatureFlags Only** | NO | `MoveMX=0`, `SmartRouting=0` | 94.2% | Ss (Running) | 310 lines | Yes (3/3) | Active (0.0% CPU) | 3 endpoints | **SPINNING** |
| **`MoveMXRouting=0` Only** | NO | `MoveMX=0`, `SmartRouting=1` | 93.2% | Rs (Running) | 311 lines | Yes (3/3) | Active (0.0% CPU) | 3 endpoints | **SPINNING** |
| **`SmartRouting=0` Only** | NO | `MoveMX=1`, `SmartRouting=0` | 96.2% | Ss (Running) | 310 lines | Yes (3/3) | Active (0.0% CPU) | 3 endpoints | **SPINNING** |
| **Governor (Stock Flags)** | **YES** | **None (Stock)** | **0.0%** | **Ts (Stopped)** | **0 lines** | **None (0/3)** | **Active (0.0% CPU)** | **3 endpoints** | **RESOLVED** |

*\*Note on Log Counts*: Active `log stream` client sessions are subject to `launchd` rate limiting (`OSLogRateLimit = 64`), yielding ~31 lines/second (~310 lines/10s) to live stream listeners while `audiomxd` spins internally through ~56,500 iterations. During unthrottled burst captures, raw emission exceeds **~247,975 entries per 10 seconds** (~24,800 lines/sec).

---

## Quick Start (1-Minute Installation)

### Automated Bash Installer

```bash
git clone https://github.com/your-org/audiomxd-fix.git
cd audiomxd-fix/daemons
sudo ./install.sh
```

To uninstall and restore completely stock behavior:
```bash
sudo ./uninstall.sh
```

---

## Deployment Options

### Option 1: Standalone Governor Daemon (Recommended)
Installs `/usr/local/libexec/audiomxd-governor.py` and LaunchDaemon `/Library/LaunchDaemons/com.macfixes.audiomxd-governor.plist`.
- Monitors `/dev/console` session ownership.
- Suspends `audiomxd` via `SIGSTOP` when at `loginwindow` (UID < 500) if unstopped.
- Resumes `audiomxd` via `SIGCONT` when an interactive user logs in (UID >= 500) if suspended.
- Stateless, level-triggered design ensures self-healing behavior across governor restarts and process crashes without fragile in-memory PID state.

### Option 2: Fleet Automation via Ansible
Copy the `ansible/` role into your infrastructure repository:
```yaml
- name: Remediate macOS audiomxd Headless Spin Loop
  hosts: mac_fleet
  become: true
  roles:
    - audiomxd_remediation
```

---

## Repository Structure

```
audiomxd_fix/
├── README.md                          # Main repository documentation
├── LICENSE                            # MIT License
├── daemons/                           # Standalone Python governor & launchd service
│   ├── audiomxd-governor.py           # Self-contained governor daemon
│   ├── com.macfixes.audiomxd-governor.plist # LaunchDaemon definition
│   ├── install.sh                     # Automated installer
│   └── uninstall.sh                   # Clean uninstaller
├── feature_flags/                     # Domain override plists (for reference/testing)
│   ├── BluetoothFeatures.plist        # Disables SmartRoutingMacOS
│   ├── MediaExperience.plist          # Disables MoveMXRoutingToAudiomxdOnMac
│   └── apply_flags.sh                 # Installer script
├── ansible/                           # Production Ansible deployment role
│   ├── tasks/main.yml
│   └── handlers/main.yml
├── shim/                              # Native C MachService responder (for research)
│   ├── audioaccessory_shim.c
│   ├── Makefile
│   └── com.macfixes.audioaccessory-shim.plist
└── technical_deep_dive/               # Comprehensive technical documentation
    ├── investigation_report.md        # Canonical end-to-end investigation report
    ├── root_cause_analysis.md         # Detailed 11-step loop breakdown & timing
    ├── disassembly_trace.md           # ARM64 assembly of MediaExperience & BluetoothServices
    ├── reproducing_the_bug.md         # Step-by-step reproduction instructions
    ├── xpc_architecture_diagram.md   # Mermaid sequence & state machine diagrams
    └── apple_feedback_template.md     # Apple Feedback Assistant / Radar template
```

---

## Functional Scope & Hardware Verification

### Verified on Apple Silicon Test Hardware:
- **CoreAudio HAL (`coreaudiod` PID 463)**: 100% operational (0.0% CPU, 75 MB memory).
- **Built-in Speakers & HDMI Audio**: Output streams and sample clocks remain fully functional.
- **Volume & Mute Controls**: Verified responsive via AppleScript API (`osascript -e "set volume output volume 75"`).
- **Session Transitions**: Clean transition between `loginwindow` (`SIGSTOP`) and interactive user login (`SIGCONT`).
- **Daemon Respawn Handling**: Automatically intercepts and manages new `audiomxd` PIDs within 2 seconds.
- **Untested Peripherals**: Wireless AirPods automatic proximity handoff was not tested due to lack of physical Bluetooth peripherals in the headless server environment.

---

## License & Disclaimer

- **Original Code & Tools**: Released into the public domain under [The Unlicense](LICENSE). You are free to copy, modify, and distribute the scripts, playbooks, and daemons without restriction.
- **Third-Party Trademarks & Research**: Apple, macOS, Darwin, CoreAudio, and MediaExperience are trademarks of Apple Inc. Disassembly fragments and symbol references in documentation are cited strictly under fair use for interoperability analysis, debugging, and bug remediation.
