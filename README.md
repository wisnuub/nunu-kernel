# nunu-kernel

Custom Android 16 kernel for [nunu](https://github.com/wisnuub/nunu) — the Cuttlefish-based Android emulator for Apple Silicon.

Built from `android16-6.12` (AOSP kernel/common) with:

- **KernelSU** — root management
- **SUSFS** — filesystem-level root hiding (makes root undetectable to apps)

## How it works

The CI pipeline:
1. Shallow-clones `android16-6.12` from Android kernel/common
2. Applies KernelSU via the [official setup script](https://github.com/tiann/KernelSU)
3. Applies SUSFS patches from [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)
4. Builds with Cuttlefish virtual device config
5. Publishes `vmlinuz_full` as a release asset

## Usage

1. Download `vmlinuz_full` from [Releases](../../releases)
2. Replace `~/.nunu/cuttlefish/vmlinuz_full` with it
3. Boot the VM — KernelSU Manager app will appear on the home screen

> **GApps first**: Install Google Play via nunu Settings → Google Play → Install GApps before installing KernelSU.

## Releases

| Asset | Description |
|-------|-------------|
| `vmlinuz_full` | Drop-in kernel replacement for nunu |
| `Image.gz` | Compressed kernel image |
| `build-info.txt` | KernelSU + SUSFS version details |

## Building locally

Requires Ubuntu 22.04 (or WSL2) with:
```bash
sudo apt-get install bc bison flex libssl-dev libelf-dev \
  gcc-aarch64-linux-gnu python3 git
```

Then run:
```bash
# Clone kernel source
git clone --depth=1 -b android16-6.12 \
  https://android.googlesource.com/kernel/common kernel/common

# Apply KernelSU
cd kernel/common
curl -LSs https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh | bash -s main

# Build
make ARCH=arm64 LLVM=1 gki_defconfig
make ARCH=arm64 LLVM=1 -j$(nproc) Image
```
