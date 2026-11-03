# nunu-kernel

Custom Android **emulator** (goldfish/ranchu) kernel for [nunu](https://github.com/wisnuub/nunu) — the native macOS Android app for Apple Silicon.

Built from `android14-6.1` (AOSP kernel/common), matching the stock emulator image's `6.1.23-android14` kernel, with:

- **KernelSU-Next** — root management (matches the manager app nunu installs)
- **SUSFS** — kernel-side root hiding, so root is undetectable to apps (Play Integrity, anti-cheat)

> nunu runs Google's **Android emulator** engine, not Cuttlefish. The kernel branch and SUSFS patch version must match the installed system image's kernel (`adb shell uname -r`), currently `android14-6.1`.

## How it works

The CI pipeline:
1. Shallow-clones `android14-6.1` from Android kernel/common
2. Applies KernelSU-Next (`next`) via its setup script
3. Applies SUSFS patches (`gki-android14-6.1`)
4. Configures GKI + goldfish/ranchu + virtio for the emulated hardware
5. Publishes a drop-in **`kernel-ranchu`** (gzipped `Image.gz`) as a release asset

## Usage

In nunu → **Settings → Root**:
1. **Download kernel + manager** — pulls `kernel-ranchu` (this repo) and the KernelSU-Next manager APK
2. Turn on **KernelSU root** and Apply & Restart — nunu boots this kernel only while root is on; turning it off boots the stock kernel with no trace
3. Pick a **Device profile** to spoof a real phone's fingerprint (applied as a SUSFS-friendly `resetprop` module)

The kernel is booted via the emulator's `-kernel` flag; it never replaces the stock image on disk.

## Building locally

Ubuntu 22.04 (or WSL2):
```bash
sudo apt-get install bc bison flex libssl-dev libelf-dev \
  gcc-aarch64-linux-gnu python3 git clang-18 lld-18

git clone --depth=1 -b android14-6.1 \
  https://android.googlesource.com/kernel/common kernel/common
cd kernel/common
curl -LSs https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh | bash -s next
make ARCH=arm64 LLVM=1 gki_defconfig
make ARCH=arm64 LLVM=1 -j$(nproc) Image.gz
```

## Status

The boot-compatibility of a from-scratch GKI + goldfish kernel in the emulator may
need config iteration (the first boot is the test). Check `adb shell uname -r` for
the SUSFS suffix and that the KernelSU-Next manager shows "Working".
