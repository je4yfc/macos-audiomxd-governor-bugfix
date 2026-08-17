# Comprehensive Technical Investigation & Remediation Report: macOS `audiomxd` Headless Spin-Loop

**Target Architecture**: Apple Silicon (arm64e)  
**Verified Platform**: macOS Tahoe 26.3 (Build 25D125) / macOS Sequoia 15.x  
**Classification**: Unthrottled Daemon IPC Recovery Loop & Unified Logging Runaway  
**Remediation**: Runtime Session Governor Daemon  


## 1. Executive Summary & Diagnostic Baseline

On Apple Silicon Mac systems running macOS Tahoe 26.3 (Build 25D125) and macOS Sequoia 15.x, whenever the machine operates headless, unattended at `loginwindow`, or after an interactive console user logs out, `/usr/libexec/audiomxd` enters an unthrottled recursive error loop.

### Measured Impact on Test Hardware:
- **CPU Utilization**: **93.5% – 96.2%** of a single high-performance CPU core continuously (Thread state: `Rs`).
- **Loop Frequency**: **~5,650 iterations per second** (~177 microseconds per cycle).
- **Log Emission**: Over **24,800 entries/sec** (~1.48 million lines/minute) during unthrottled bursts, saturating Unified Logging subsystems and exhausting disk space in `/var/db/diagnostics` and `/var/log` within days.
- **Hardware Audio HAL**: `/usr/sbin/coreaudiod` (UID 202 `_coreaudiod`, PID 463) and hardware output drivers (Built-in Mac mini Speakers, HDMI audio) remain normal and unaffected, confirming the failure is isolated to the high-level session/routing daemon (`audiomxd`).


## 2. Low-Level Root Cause & Causal Mechanism

The fault arises from an unhandled session boundary condition in Apple's audio routing architecture:

```
+-----------------------------------------------------------------------------------+
| 1. LaunchAgent /System/Library/LaunchAgents/com.apple.cloudpaird.plist            |
|    Declared: <key>LimitLoadToSessionType</key><string>Aqua</string>               |
|    Result: audioaccessoryd is ONLY loaded in active Aqua graphical sessions.      |
|    At loginwindow or in headless mode, audioaccessoryd does NOT run.              |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
| 2. /usr/libexec/audiomxd (UID: _audiomxd) initializes MXAudioAccessoryServices    |
|    Allocates BTAudioRoutingRequest (BluetoothServices.framework)                  |
|    BTAudioRoutingRequest checks TargetUserSession -> Returns NULL (UID 0)         |
|    Fails with kUnexpectedErr (-6700: No user logged in)                           |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
| 3. BTAudioRoutingRequest logs:                                                    |
|    "### TargetUserSession, but no console user?"                                  |
|    "### UpdateAudioState failed to start XPC: kUnexpectedErr (No user logged in)" |
|    "### audioaccessoryd died"                                                     |
|    Posts AudioAccessorydDiedNotification via NSNotificationCenter                 |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
| 4. Unthrottled Dual Recursive Feedback Loop (177 µs / cycle):                     |
|    a) -[MXAudioAccessoryServices handleServerDeath]:                              |
|       Logs "audioaccessoryd died :(", executes finalizeAudioAccessoryConnection, |
|       then initializeAudioAccessoryConnection, and posts DiedNotification.        |
|    b) -[MXSessionManager audioAccessoryServerDiedCallback:]:                      |
|       Logs "Syncing with AudioAccessoryServices as they just recovered.",         |
|       immediately calls -[MXAudioAccessoryServices updateAppState:startIO:1].     |
+-----------------------------------------------------------------------------------+
```

Neither `handleServerDeath` nor `audioAccessoryServerDiedCallback:` incorporates retry backoff, delays, or checks for an active console session.


## 3. Empirical Evidence & Controlled Experiment Matrix

To evaluate potential remediations, 6 configurations were tested on an affected Apple Silicon Mac at `loginwindow` (Console session: `root (0)`). 

### Log Stream Measurement Methodology:
- **Rate-Limited Log Stream Count (10s window)**: Captured using `log stream --predicate "processImagePath CONTAINS 'audiomxd'"` for 10 seconds. In macOS, active streaming listeners are throttled by `launchd`'s `OSLogRateLimit` directive (configured to 64 in `com.apple.audiomxd.plist`), yielding ~31.0 lines/second (~310 lines/10s) to client listeners while `audiomxd` spins internally through ~56,500 iterations.
- **Unthrottled Historical Burst Count**: During unthrottled offline captures or disk flushes, `audiomxd` generates **~247,975 entries per 10 seconds** (~24,800 lines/sec).

### Controlled Matrix Results:

| Config | Configuration Tested | Governor Active? | `MoveMXRouting` Override | `SmartRouting` Override | `audiomxd` CPU | `audiomxd` Process Stat | 10s Stream Log Count | Characteristic Loop Signatures Present? | CoreAudio HAL Status | Audio Device Endpoints | Empirical Outcome |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **1** | **Governor + FeatureFlag Overrides** | **YES** | Disabled (0) | Disabled (0) | **0.0%** | **Ts (Stopped)** | **0** | **None (0/3)** | Active (0.0% CPU) | 3 endpoints | **RESOLVED** |
| **2** | **FeatureFlags Only (No Governor)** | NO | Disabled (0) | Disabled (0) | 94.2% | Ss (Running) | 310 | Yes (3/3) | Active (0.0% CPU) | 3 endpoints | **SPINNING (Failed)** |
| **3** | **`MoveMXRouting=0` Only** | NO | Disabled (0) | Stock (1) | 93.2% | Rs (Running) | 311 | Yes (3/3) | Active (0.0% CPU) | 3 endpoints | **SPINNING (Failed)** |
| **4** | **`SmartRouting=0` Only** | NO | Stock (1) | Disabled (0) | 96.2% | Ss (Running) | 310 | Yes (3/3) | Active (0.0% CPU) | 3 endpoints | **SPINNING (Failed)** |
| **5** | **Governor Only (Stock Flags)** | **YES** | **Stock (1)** | **Stock (1)** | **0.0%** | **Ts (Stopped)** | **0** | **None (0/3)** | Active (0.0% CPU) | 3 endpoints | **RESOLVED (Optimal)** |
| **6** | **Stock macOS (Unpatched Control)** | NO | Stock (1) | Stock (1) | 95.7% | Rs (Running) | 311 | Yes (3/3) | Active (0.0% CPU) | 3 endpoints | **SPINNING (Control)** |

*Signatures evaluated*: `TargetUserSession NULL 0` / `TargetUserSession, but no console user?`, `audioaccessoryd died`, `Syncing with AudioAccessoryServices as they just recovered`.


## 4. FeatureFlag Consumer & Call-Site Analysis

Reverse-engineering Darwin frameworks with LLDB revealed why FeatureFlags alone do not break the spin-loop:

### A. `MediaExperience/MoveMXRoutingToAudiomxdOnMac`
- **Call-Site**: `MediaExperience[0x191b2b4d0]` (`MX_FeatureFlags_IsMoveMXRoutingToAudiomxdOnMacEnabled`).
- **Function**: Gates whether AirPlay endpoint discovery and volume contexts are exposed as XPC services in launchd (`com.apple.coremedia.routingcontext.xpc`, `volumecontroller.xpc`).
- **Finding**: Does not guard `MXAudioAccessoryServices` initialization. `MXSessionManager` unconditionally instantiates `MXAudioAccessoryServices` during daemon startup regardless of this flag.

### B. `BluetoothFeatures/SmartRoutingMacOS`
- **Call-Site**: `AudioSession.framework` (`avas::SmartRoutingMacOSEnabled()`).
- **Function**: Controls AirPods automatic switching proximity scoring.
- **Finding**: Disabling proximity scoring does not bypass `BTAudioRoutingRequest` initialization. `BTAudioRoutingRequest` still performs its base session verification, finds `NULL`, and triggers the failure callback.


## 5. Architectural Evaluation of the Native MachService Shim

An alternative approach—providing a native C responder for `com.apple.AudioAccessoryServices` via LaunchDaemon—was analyzed:
1. **Namespace Collision**: `audioaccessoryd` is registered as an Aqua session agent (`gui/501`). Registering `com.apple.AudioAccessoryServices` in the `system` domain satisfies `audiomxd` while headless, but causes a MachService collision when an interactive user logs into the desktop, intercepting and breaking native AirPods switching.
2. **Protocol Simulation**: Returning empty dictionaries with `kError = 0` satisfies the initial handshake, but does not provide complete state transitions for active audio sessions.
3. **Verdict**: **Semantically unsafe for mixed interactive/headless environments**.


## 6. Validated Remediation: The Runtime Session Governor

The optimal, minimal, and solely sufficient solution is the **runtime session governor** (`audiomxd-governor`):

### Mechanism:
- A lightweight LaunchDaemon watchdog monitors `/dev/console` ownership.
- When at `loginwindow` (UID < 500), it sends `SIGSTOP` if `audiomxd` is running and unstopped.
- When an interactive Aqua user logs in (UID >= 500), it sends `SIGCONT` if `audiomxd` is suspended.
- Designed as a stateless, level-triggered supervisor that survives governor restarts, launchd reloads, and daemon crashes without relying on volatile in-memory PID state.

### Hardware Verification on Tested macOS Build:
- **Loginwindow CPU**: Dropped from **~95%** to **0.0%**.
- **Loginwindow Log Rate**: Dropped from **~24,800 lines/sec** to **0 lines/sec**.
- **CoreAudio HAL (`coreaudiod` PID 463)**: 100% operational (0.0% CPU, 75 MB memory).
- **Hardware Output Endpoints**: Built-in Speakers and HDMI output tested and fully functional.
- **Volume / Mute Controls**: Verified responsive via AppleScript API.
- **Interactive Peripherals**: Tested on built-in and HDMI hardware; wireless AirPods auto-switching not tested due to lack of physical peripherals in headless test setup.
