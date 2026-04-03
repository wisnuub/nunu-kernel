# Kernel Build Guide

## Prerequisites

AOSP provides the full toolchain — no system LLVM needed.

```bash
# Python 3.11+ required for build scripts
python3 --version

# repo tool
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
```

## Fetch the kernel source

nunu-kernel targets `android14-6.1` (GKI, Android 14, Linux 6.1 LTS).

```bash
mkdir android-kernel && cd android-kernel

repo init -u https://android.googlesource.com/kernel/manifest \
     -b common-android14-6.1

repo sync -j$(nproc) --no-clone-bundle
```

## Build

```bash
# From the android-kernel/ root
tools/bazel build //common:kernel_aarch64 \
  --config=fast \
  --kconfig_ext=$(pwd)/../nunu-kernel/kernel/gaming_defconfig
```

Output: `bazel-bin/common/kernel_aarch64/Image.gz`

## Apply gaming sysctl at runtime

The `gaming_sysctl.conf` values are applied via an Android init snippet.
Copy `gaming_sysctl.conf` into the Cuttlefish overlay as:

```
device/google/cuttlefish/shared/config/init.gaming.rc
```

Add to the Cuttlefish device `BoardConfig.mk`:
```makefile
PRODUCT_COPY_FILES += device/google/cuttlefish/shared/config/init.gaming.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.gaming.rc
```

## Verify the build

```bash
# Check key config options are set correctly
grep -E "CONFIG_SCHED_WALT|CONFIG_LRU_GEN|CONFIG_VIRTIO_GPU|CONFIG_TCP_CONG_BBR" \
  bazel-bin/common/kernel_aarch64/.config
```

Expected output:
```
CONFIG_SCHED_WALT=y
CONFIG_LRU_GEN=y
CONFIG_VIRTIO_GPU=y
CONFIG_TCP_CONG_BBR=y
```
