# Reproducing the `audiomxd` Spin-Loop Failure

This document provides exact, reproducible steps to verify the `audiomxd` failure on any Apple Silicon Mac running macOS Tahoe / macOS 15+.


## Prerequisites
- Apple Silicon Mac running macOS Tahoe (or macOS 15.x / 26.x).
- SSH access or dual session access.


## Reproduction Procedure

### Step 1: Establish Baseline (Console User Logged In)
Log into the local Aqua GUI session with an administrative user, then connect via SSH:

```bash
# Check console session owner
stat -f '%Su (UID: %u)' /dev/console
# Expected: <username> (UID: 501)

# Check audiomxd CPU utilization
ps -p $(pgrep audiomxd) -o pid,%cpu,cputime,etime,stat,command
# Expected: %CPU ~0.0%, STAT Ss
```

### Step 2: Transition to `loginwindow` (Simulate Headless/Logout)
From the SSH session, terminate the GUI Aqua session:

```bash
sudo launchctl bootout gui/501
```

Wait 3-5 seconds for the system to settle at `loginwindow`.

### Step 3: Observe CPU Runaway & Log Storm
Check `audiomxd` process status and stream logs:

```bash
# Check CPU usage
ps -p $(pgrep audiomxd) -o pid,%cpu,cputime,etime,stat,command
# Expected: %CPU ~90.0% - 94.0%, STAT Rs (Single-core CPU burn)

# Sample Unified Log output for 3 seconds
log stream --predicate 'processImagePath CONTAINS "audiomxd"'
```

### Observed Log Output Signature:
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


## Verification of the Fix
After applying the `audiomxd-governor` daemon:
```bash
sudo ./daemons/install.sh
sudo launchctl bootout gui/501
ps -p $(pgrep audiomxd) -o pid,%cpu,cputime,etime,stat,command
# Expected: %CPU 0.0%, STAT Ts (Suspended cleanly at loginwindow)
```
Log in to the GUI session -> `audiomxd` automatically resumes (`STAT Ss`, %CPU `0.0%`).
