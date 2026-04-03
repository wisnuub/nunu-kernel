# nunu-kernel

Custom Android kernel and VM engine powering [nunu](https://github.com/wisnuub/nunu) on Apple Silicon.

Built on Google Cuttlefish and Apple's `Virtualization.framework` — no QEMU, no translation layer. ARM64 Android running natively on ARM64 macOS.

---

## Architecture

```
nunu (Electron launcher)
    │
    ├─ macOS Apple Silicon → nunu-kernel (this repo)
    │       Virtualization.framework → Cuttlefish ARM64
    │
    └─ Windows → AVM (github.com/wisnuub/AVM)
                QEMU + WHPX → Android x86_64
```

### Why Cuttlefish

Cuttlefish is Google's official virtual Android device, built specifically for VirtIO hardware. Unlike the Android SDK emulator images (which are built for QEMU's virtual hardware profile), Cuttlefish targets the same virtio device tree that `Virtualization.framework` exposes — making it the right image format for this project.

### Why not QEMU

On Apple Silicon, QEMU adds an unnecessary abstraction layer between Android and the hardware. `Virtualization.framework` is Apple's native hypervisor API — the same one used by Parallels and UTM. With ARM64 Android running on ARM64 hardware through a native hypervisor, there is no instruction translation and minimal overhead.

---

## Components

```
nunu-kernel/
├── kernel/          Android kernel source config + patches
├── image/           Cuttlefish image build scripts (AOSP)
├── launcher/        Swift CLI — boots Cuttlefish via Virtualization.framework
└── gapps/           Minimal GApps integration scripts
```

### kernel/
Custom Android kernel based on `android-common` (Google's GKI kernel tree). Tuned for gaming workloads:
- Lower scheduler latency
- `vm.swappiness=0` (no swap thrashing during game sessions)
- Stripped modules not needed in a VM context
- Binder thread tuning for heavy game IPC

### image/
Build scripts for the Cuttlefish AOSP target (`aosp_cf_arm64_phone-userdebug`). Produces:
- `system.img` — Android system partition
- `vendor.img` — vendor partition  
- `userdata.img` — writable data partition
- `kernel` — the custom kernel image

### launcher/
Swift CLI (`nunu-vm`) that boots a Cuttlefish image using `Virtualization.framework`:

```
VZVirtualMachineConfiguration
├── VZLinuxBootLoader        Android kernel + initrd
├── VZVirtioBlockDevice      system.img, userdata.img
├── VZVirtioNetworkDevice    ADB over TCP (port 5555)
├── VZVirtioGraphicsDevice   Display → Metal
├── VZVirtioSoundDevice      Audio
└── VZVirtioEntropyDevice    /dev/random
```

### gapps/
Scripts to integrate the minimum required Google components into the AOSP build:
- `com.google.android.gms` — Play Services core
- `com.android.vending` — Play Store
- `com.google.android.gsf` — Google Services Framework

Nothing else. No YouTube, Drive, Photos, Maps, or other Google apps baked in.

---

## Roadmap

### Phase 1 — Kernel build pipeline
- [ ] Clone and configure `android-common` kernel
- [ ] Set up ARM64 cross-compile toolchain (LLVM/clang from AOSP)
- [ ] Base config from `gki_defconfig`
- [ ] GitHub Actions CI — builds `Image.gz` artifact on push
- [ ] Gaming-specific kernel config patches

### Phase 2 — Cuttlefish image build
- [ ] AOSP build environment setup (`aosp_cf_arm64_phone-userdebug`)
- [ ] Minimal GApps integration
- [ ] Validate on Linux + KVM (baseline before macOS port)
- [ ] Play Integrity verification — confirm games pass attestation
- [ ] Automated image builds in CI

### Phase 3 — macOS Virtualization.framework launcher
- [ ] Swift package setup with `Virtualization.framework`
- [ ] Entitlements (`com.apple.security.virtualization`)
- [ ] Boot Cuttlefish image via `VZLinuxBootLoader`
- [ ] virtio-blk disk image mounting
- [ ] virtio-net + ADB TCP forwarding
- [ ] virtio-gpu Metal-backed display

### Phase 4 — Display and input
- [ ] `VZVirtualMachineView` display integration
- [ ] Touch/mouse input forwarding
- [ ] Audio via `VZVirtioSoundDevice`
- [ ] Resolution and DPI configuration

### Phase 5 — nunu integration
- [ ] IPC protocol (mirrors existing AVM interface)
- [ ] nunu detects platform and calls correct backend
- [ ] Image download and management via nunu installer
- [ ] Seamless switchover from SDK emulator on macOS

### Phase 6 — Gaming optimization
- [ ] CPU governor (`performance` mode during game sessions)
- [ ] Memory pressure tuning per game profile
- [ ] Boot time optimization (snapshot/restore)
- [ ] Background GMS service suppression via ADB

---

## Requirements

**Build:**
- macOS 13+ (Ventura) on Apple Silicon
- Xcode 15+
- Linux build machine or CI for AOSP image builds (AOSP does not build on macOS)

**Runtime:**
- macOS 13+ on Apple Silicon (M1/M2/M3/M4)
- `com.apple.security.virtualization` entitlement

---

## Relation to AVM

[AVM](https://github.com/wisnuub/AVM) remains the Windows backend for nunu — QEMU + WHPX running Android x86_64. nunu-kernel is macOS-only by design. The two projects share the same IPC interface so nunu can call either transparently.

---

## Status

Early development. Phase 1 in progress.
