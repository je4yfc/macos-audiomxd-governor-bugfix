# Low-Level Disassembly & Function Traces

This document catalogs the exact ARM64 assembly instructions extracted from macOS Tahoe frameworks that substantiate the failure mechanism.


## 1. `-[MXAudioAccessoryServices handleServerDeath]`
**Framework**: `/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience`  
**Address**: `0x19d1ee6e0`

```asm
MediaExperience`-[MXAudioAccessoryServices handleServerDeath]:
0x19d1ee6e0 <+0>:   pacibsp 
0x19d1ee6e4 <+4>:   stp    x22, x21, [sp, #-0x30]!
0x19d1ee6e8 <+8>:   stp    x20, x19, [sp, #0x10]
0x19d1ee6ec <+12>:  stp    x29, x30, [sp, #0x20]
0x19d1ee6f0 <+16>:  add    x29, sp, #0x20
0x19d1ee6f4 <+20>:  mov    x19, x0                   ; self (MXAudioAccessoryServices)
0x19d1ee700 <+32>:  adrp   x7, 82
0x19d1ee704 <+36>:  add    x7, x7, #0x633            ; "-MXAudioAccessoryServices- %s: audioaccessoryd died :("
0x19d1ee710 <+48>:  bl     0x191b6000c               ; _os_log_send_and_compose_impl
0x19d1ee758 <+120>: ldr    x0, [x19, #0x18]          ; mSerialQueue ("com.apple.mediaexperience.AudioAccessoryServices")
0x19d1ee75c <+124>: adrp   x1, ...                   ; Block literal (__45-[MXAudioAccessoryServices handleServerDeath]_block_invoke)
0x19d1ee764 <+132>: bl     0x191b60280               ; dispatch_async
0x19d1ee778 <+152>: retab
```


## 2. `__45-[MXAudioAccessoryServices handleServerDeath]_block_invoke`
**Framework**: `MediaExperience.framework`  
**Address**: `0x19d1ee780`

```asm
MediaExperience`__45-[MXAudioAccessoryServices handleServerDeath]_block_invoke:
0x19d1ee780 <+0>:   pacibsp 
0x19d1ee790 <+16>:  ldr    x19, [x0, #0x20]          ; captured self
0x19d1ee794 <+20>:  adrp   x1, ...
0x19d1ee798 <+24>:  ldr    x1, [x1, #0x2b0]          ; @selector(finalizeAudioAccessoryConnection)
0x19d1ee79c <+28>:  mov    x0, x19
0x19d1ee7a0 <+32>:  bl     0x191b60580               ; objc_msgSend -> finalizeAudioAccessoryConnection
0x19d1ee7a8 <+40>:  adrp   x1, ...
0x19d1ee7ac <+44>:  ldr    x1, [x1, #0x2b8]          ; @selector(initializeAudioAccessoryConnection)
0x19d1ee7b0 <+48>:  mov    x0, x19
0x19d1ee7b4 <+52>:  bl     0x191b60580               ; objc_msgSend -> initializeAudioAccessoryConnection
0x19d1ee7c0 <+64>:  adrp   x0, ...                   ; [NSNotificationCenter defaultCenter]
0x19d1ee7dc <+92>:  adrp   x2, ...                   ; kMXAudioAccessoryServicesNotification_AudioAccessoryServerDied
0x19d1ee7e4 <+100>: bl     0x191b60580               ; postNotificationName:object:
0x19d1ee7f0 <+112>: retab
```


## 3. `-[MXSessionManager audioAccessoryServerDiedCallback:]`
**Framework**: `MediaExperience.framework`  
**Address**: `0x19d1f39e4`

```asm
MediaExperience`-[MXSessionManager audioAccessoryServerDiedCallback:]:
0x19d1f39e4 <+0>:   pacibsp 
0x19d1f39f8 <+20>:  adrp   x7, ...                   ; "-MXSessionManager- %s: Syncing with AudioAccessoryServices as they just recovered."
0x19d1f3a10 <+44>:  bl     0x191b6000c               ; _os_log_send_and_compose_impl
0x19d1f3a30 <+76>:  bl     0x19d1ee35c               ; +[MXAudioAccessoryServices sharedInstance]
0x19d1f3a38 <+84>:  adrp   x1, ...                   ; @selector(updateAppState:startIO:)
0x19d1f3a40 <+92>:  mov    w3, #0x1                  ; startIO = 1
0x19d1f3a48 <+100>: bl     0x191b60580               ; objc_msgSend -> updateAppState:startIO:
0x19d1f3a58 <+116>: retab
```


## 4. `libsystem_featureflags.dylib` Fastpath / Slowpath Mechanics
**Framework**: `/usr/lib/system/libsystem_featureflags.dylib`

1. **Fast-path**: `_os_feature_enabled_impl` performs a direct hash-table lookup against the mmap'd shared memory region `com.apple.featureflags.shm` created by `init_featureflags` at boot.
2. **Environment Variable Override Detection** (`_os_feature_enabled_envvar_check_once`):
   ```asm
   libsystem_featureflags.dylib`_os_feature_enabled_envvar_check_once:
   0x180366208: adrp   x0, ... ; "FEATUREFLAGS_ENABLED"
   0x180366210: bl     getenv
   0x180366214: cbnz   x0, 0x180366228
   0x180366218: adrp   x0, ... ; "FEATUREFLAGS_DISABLED"
   0x180366220: bl     getenv
   0x180366224: cbz    x0, 0x180366230
   0x180366228: mov    w8, #0x1
   0x18036622c: strb   w8, [x19] ; Sets slowpath flag = 1
   ```
3. Setting `FEATUREFLAGS_DISABLED="BluetoothFeatures/SmartRoutingMacOS:MediaExperience/MoveMXRoutingToAudiomxdOnMac"` forces the process into `_os_feature_enabled_SLOWPATH`, overriding the cached shared memory values.
