# SM8550 GPU Overclock — Adreno 740 Turbo OPPs

## What it does

Adds two synthetic **turbo operating-points (OPPs)** to the Adreno 740 GPU on
Snapdragon 8 Gen 2 (SM8550), pushing the clock above the stock 767 MHz ceiling:

| OPP | Frequency | Δ vs stock max |
|-----|-----------|----------------|
| Stock max | 767 MHz | — |
| Turbo 1 | 820 MHz | +7% |
| Turbo 2 | 875 MHz | +14% |

The OPPs sit on top of the device-tree table.  `devfreq`'s `simple_ondemand`
governor automatically ramps up to them under load, and ramps down when idle.

**The actual GPU frequency is ultimately controlled by the GMU (Graphics
Microcontroller Unit) via RPMh DCVS votes.**  The GMU may round the requested
frequency to the nearest supported DCVS level.  Measure with:

```
cat /sys/class/devfreq/*gpu*/cur_freq
```

## Architecture

```
Device Tree (sm8550.dtsi)
    └── gpu_opp_table: 514 / 575 / 681 / 767 MHz
            │
            ▼  [sm8550_gpu_oc kernel module OR sm8550-gpu-turbo-overlay.dtbo]
   Turbo OPPs added: 820 / 875 MHz (speed_bin=0 only)
            │
            ▼
   devfreq framework
   └── simple_ondemand governor
            │
            ▼  msm_devfreq_target()
   a6xx_gpu_set_freq()
            │
            ▼  a6xx_gmu_set_freq()
   GMU HFI → RPMh DCVS vote → GX clock frequency
```

## Two ways to activate

### Option A — Device Tree Overlay (recommended for baked kernels)

1. Compile the `.dts` → `.dtbo`:
   ```bash
   dtc -@ -I dts -O dtb -o sm8550-gpu-turbo-overlay.dtbo \
          sm8550-gpu-turbo-overlay.dts
   ```

2. Install the `.dtbo` on the device:
   ```bash
   adb push sm8550-gpu-turbo-overlay.dtbo /vendor/overlays/
   # Then add to fstab or enable via overlay.dtb
   ```

3. Reboot.  Check:
   ```
   cat /sys/class/devfreq/*gpu*/available_frequencies
   # should now list 820000000 and 875000000
   ```

### Option B — Out-of-tree Kernel Module

1. Build the module (from the kernel source tree):
   ```bash
   # Add to drivers/gpu/drm/msm/Kbuild:
   # obj-y += sm8550_gpu_overclock/
   make -C /path/to/android-kernel O=out ARCH=arm64 \
        LLVM=1 LLVM_IAS=1 sm8550_gpu_oc.ko
   ```

2. Load on device:
   ```bash
   adb push sm8550_gpu_oc.ko /data/local/tmp/
   adb shell su -c insmod /data/local/tmp/sm8550_gpu_oc.ko
   # or via Magisk kernel module (copy to /data/adb/modules/<name>/)
   ```

3. Runtime control:
   ```bash
   adb shell su -c sh /data/local/tmp/sm8550_gpu_oc_runtime.sh enable
   ```

## Kernel config requirements

```
CONFIG_PM_OPP=y
CONFIG_PM_OPP_FORCE_4000=y        # if using >4000 OPPs (unlikely needed)
CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y
CONFIG_DEVFREQ_GOV_USERSPACE=y    # optional, for manual control
CONFIG_MSM_GPU_DEVFREQ=y          # enabled by MSM DRM
```

## Kernel source changes

### 1. `drivers/gpu/drm/msm/Kbuild` — register the subdirectory

```kbuild
# In the existing file, after the other obj-y lines:
obj-y += sm8550_gpu_overclock/
```

### 2. `drivers/gpu/drm/msm/adreno/a6xx_gpu.c` — wire into probe

```c
// In a6xx_gpu_probe(), after adreno_get_pwrlevels() succeeds:
#include "sm8550_gpu_overclock/sm8550_gpu_oc.h"

// ... after adreno_get_pwrlevels(dev, gpu) call ...
sm8550_gpu_oc_register(&gpu->base.pdev->dev);
```

### 3. Device tree overlay (`.dtbo`)

Apply the `.dts` in this directory as a device tree overlay on top of
`sm8550.dtsi`.  This is the production path — no module loading needed.

## Safety

- **Thermal throttling still works.**  The kernel thermal framework monitors
  SoC temperature and will force the GPU down if it exceeds trip points,
  even with turbo OPPs present.  No override of thermal controls is included.
- **Power limits still apply.**  The GMU enforces RPMh power constraints.
- **Use `oc_enabled=0` to disable** (module) or remove the `.dtbo` (overlay).
- **Test with a workload first:** the GPU governor only ramps up under load.
  Idle the GPU will stay at 514 MHz.

## Files

```
sm8550_gpu_overclock/
├── Kbuild                      # Kbuild entry (include in MSM DRM build)
├── sm8550_gpu_oc.h             # Public API header
├── sm8550_gpu_oc.c             # Core: OPP add/remove + module params
├── sm8550_gpu_oc_a6xx.c        # A6xx integration shim
├── sm8550-gpu-turbo-overlay.dts  # Device-tree overlay (Alt A)
├── sm8550_gpu_oc_runtime.sh    # Userspace control script
└── README.md                   # This file
```

## Disabling / rolling back

```bash
# Module way:
echo 0 > /sys/module/sm8550_gpu_oc/parameters/oc_enabled

# Overlay way:
# Remove sm8550-gpu-turbo-overlay.dtbo from /vendor/overlays/ and reboot

# Manual:
echo 767000000 > /sys/class/devfreq/*gpu*/max_freq
```
