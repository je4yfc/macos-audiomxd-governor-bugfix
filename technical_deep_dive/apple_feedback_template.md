# Apple Feedback Assistant / Radar Bug Report Template

**Title**: `audiomxd` enters unthrottled 100% CPU spin loop and log flood when system is at `loginwindow` or headless  
**Component**: CoreMedia / MediaExperience / AudioSession (`audiomxd`)  
**Version**: macOS Tahoe 26.3 (Build 25D125), macOS Sequoia 15.x  
**Classification**: Performance / Crash / Data Loss (Disk Exhaustion)  
**Reproducibility**: Always (100%)  

---

## Description
When an Apple Silicon Mac transitions to `loginwindow` (either after GUI user logout, during headless server operation, or when locked), `/usr/libexec/audiomxd` consumes ~93.5% CPU on 1 core and emits ~24,800 Unified Log lines per second (~1.48 million lines/minute). Over several days, this exhausts all available disk space in `/var/db/diagnostics` and `/var/log`.

## Root Cause Analysis
1. `audioaccessoryd` is managed by LaunchAgent `/System/Library/LaunchAgents/com.apple.cloudpaird.plist` with `LimitLoadToSessionType = Aqua`.
2. In `audiomxd`, `[MXSessionManager init]` creates `[MXAudioAccessoryServices sharedInstance]`, which instantiates `BTAudioRoutingRequest` (`BluetoothServices.framework`).
3. When no Aqua GUI user is logged in, `BTAudioRoutingRequest` detects `TargetUserSession == NULL` and immediately fails with `kUnexpectedErr (-6700: No user logged in)`.
4. `BTAudioRoutingRequest` logs `### audioaccessoryd died` and posts `AudioAccessorydDiedNotification`.
5. `-[MXAudioAccessoryServices handleServerDeath]` catches this notification, logs `audioaccessoryd died :(`, invalidates and re-creates `BTAudioRoutingRequest`, and posts `kMXAudioAccessoryServicesNotification_AudioAccessoryServerDied`.
6. `-[MXSessionManager audioAccessoryServerDiedCallback:]` logs `"-MXSessionManager- Syncing with AudioAccessoryServices as they just recovered."` and invokes `[[MXAudioAccessoryServices sharedInstance] updateAppState:sessions startIO:1]`.
7. Because no backoff, delay, or console session check exists, both calls fail immediately against the missing console user, repeating the cycle every 177 microseconds.

## Proposed Apple Fix
1. In `-[MXAudioAccessoryServices handleServerDeath]` and `-[MXSessionManager audioAccessoryServerDiedCallback:]`, verify that an interactive console user session is present before initiating recovery.
2. Introduce exponential backoff (e.g. 1s, 2s, 5s, 10s) on connection failures rather than a 0-delay recursive dispatch.
3. If no console user is logged in, disarm `AudioAccessoryServices` until a `kTargetUserSessionChanged` or login notification is received.

## Steps to Reproduce
1. Log in to a local macOS Aqua account.
2. From an SSH session or terminal, run `sudo launchctl bootout gui/501`.
3. Check `audiomxd` CPU: `ps -p $(pgrep audiomxd) -o pid,%cpu,command`.
4. Check Unified Log stream: `log stream --predicate 'processImagePath CONTAINS "audiomxd"'`.
