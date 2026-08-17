# Apple Feedback Assistant / Radar Bug Report Reference

**Title**: `audiomxd` enters unthrottled 100% CPU spin loop and log flood when system is at `loginwindow` or headless  
**Component**: CoreMedia / MediaExperience / AudioSession (`audiomxd`)  
**Affected Versions**: macOS Tahoe 26.0–26.5 (Build 25D125), macOS Sequoia 15.x  
**Resolved In**: **macOS Tahoe 26.6.1 (Build 25G76)**  
**Classification**: Performance / Crash / Data Loss (Disk Exhaustion)  
**Status**: **Resolved Upstream by Apple in macOS 26.6.1**  


## Description
When an Apple Silicon Mac transitions to `loginwindow` (either after GUI user logout, during headless server operation, or when locked), `/usr/libexec/audiomxd` in macOS 26.0–26.5 consumed ~93.5%–96% CPU on 1 core and emitted ~24,800 Unified Log lines per second (~1.48 million lines/minute). Over several days, this exhausted all available disk space in `/var/db/diagnostics` and `/var/log`.

## Root Cause Summary
1. `audioaccessoryd` is managed by LaunchAgent `/System/Library/LaunchAgents/com.apple.cloudpaird.plist` with `LimitLoadToSessionType = Aqua`.
2. In `audiomxd`, `[MXSessionManager init]` created `[MXAudioAccessoryServices sharedInstance]`, which instantiated `BTAudioRoutingRequest` (`BluetoothServices.framework`).
3. When no Aqua GUI user was logged in, `BTAudioRoutingRequest` detected `TargetUserSession == NULL` and immediately failed with `kUnexpectedErr (-6700: No user logged in)`.
4. `BTAudioRoutingRequest` logged `### audioaccessoryd died` and posted `AudioAccessorydDiedNotification`.
5. `-[MXAudioAccessoryServices handleServerDeath]` caught this notification, logged `audioaccessoryd died :(`, invalidated and re-created `BTAudioRoutingRequest`, and posted `kMXAudioAccessoryServicesNotification_AudioAccessoryServerDied`.
6. `-[MXSessionManager audioAccessoryServerDiedCallback:]` logged `"-MXSessionManager- Syncing with AudioAccessoryServices as they just recovered."` and invoked `[[MXAudioAccessoryServices sharedInstance] updateAppState:sessions startIO:1]`.
7. Because no backoff, delay, or console session check existed, both calls failed immediately against the missing console user, repeating the cycle every 177 microseconds.

## Upstream Resolution in macOS 26.6.1
In macOS Tahoe 26.6.1 (Build 25G76), Apple introduced an entry-point check in `/usr/libexec/audiomxd` that verifies `_os_feature_enabled_impl("BluetoothFeatures", "SmartRoutingMacOS")`. Because `SmartRoutingMacOS` is defaulted to `False` in 26.6.1, `audiomxd` logs:
```
audiomxd: [com.apple.coreaudio:audiomxd] audiomxd feature flag is disabled, exiting
```
and exits cleanly with code 255 before initializing `MXSessionManager`, eliminating the headless runaway loop.
