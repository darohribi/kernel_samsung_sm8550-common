# SM8550 GPU Overclock — Adreno 740 Turbo OPPs

## What it does

Adds two synthetic **turbo operating-points (OPPs)** to the Adreno 740 GPU on
Snapdragon 8 Gen 2 (SM8550), pushing the clock above the stock 767 MHz ceiling:

| OPP | Frequency | Δ vs stock max |
|-----|-----------|----------------|
| Stock max | 767 MHz | — |
| Turbo 1 | 820 MHz | +7% |
| Turbo 2 | 875 MHz | +14% |

**Frequency-setting path:**
```
dev_pm_opp_add()       ← synthetic OPPs registered here
  → devfreq (simple_ondemand)
  → msm_devfreq_target()
  → a6xx_gpu_set_freq()
  → a6xx_gmu_set_freq()
  → GMU HFI → RPMh DCVS vote → GX clock
```

**Research validation:**
- sd-tools (TheGammaSqueeze) documents Adreno 710 practical OC ceiling at ~1000–1050 MHz
  before GMU trips `freq_limiter_irq`. 820/875 MHz is well within safe margin.
- RPMh corner hierarchy: TURBO=0x1A0, TURBO_L1=0x1E0, TURBO_L2=0x200.
  GPU rail regulators (`rpmh-regulator-gfxlvl`) accept levels above stock TURBO —
  voltage headroom exists for turbo frequencies.
- encore_profiler (Rem01Gaming) confirms dual-control architecture:
  devfreq sysfs + legacy KGSL powerlevel sysfs coexist.
  Locking both `min_pwrlevel` and `max_pwrlevel` to level 0 prevents the
  legacy path from fighting devfreq.

## Two ways to activate

### Option A — In-tree kernel (CONFIG_SM8550_GPU_OC, recommended)

Requires:
- `CONFIG_SM8550_GPU_OC=y` in defconfig (enabled in sm8550_perf_defconfig)
- `CONFIG_DRM_MSM=y` (enabled in sm8550_perf_defconfig)
- Stock OPPs must be populated by `adreno_get_pwrlevels()` from device tree

The implementation is inline in `drivers/gpu/drm/msm/msm_gpu.c`,
activated by `sm8550_gpu_oc_add_opps()` called after `msm_devfreq_init()`.

Rebuild kernel, flash, check:
```
cat /sys/class/devfreq/*gpu*/available_frequencies
# should list 820000000 and 875000000
```

### Option B — Device Tree Overlay (no kernel rebuild needed)

1. Compile:
   ```bash
   dtc -@ -I dts -O dtb -o sm8550-gpu-turbo-overlay.dtbo \
          sm8550-gpu-turbo-overlay.dts
   ```

2. Install:
   ```bash
   adb push sm8550-gpu-turbo-overlay.dtbo /vendor/overlays/
   # Enable via fstab overlay or device.mk
   ```

3. Reboot, then check as above.

## Runtime control

```bash
adb push sm8550_gpu_oc_runtime.sh /data/local/tmp/
adb shell su -c sh /data/local/tmp/sm8550_gpu_oc_runtime.sh status
adb shell su -c sh /data/local/tmp/sm8550_gpu_oc_runtime.sh enable
adb shell su -c sh /data/local/tmp/sm8550_gpu_oc_runtime.sh disable
```

The script:
- Locks KGSL powerlevel (legacy sysfs) via `kgsl-3d0/min_pwrlevel=max_pwrlevel=0`
- Tunes devfreq governor (userspace → simple_ondemand)
- Shows GPU temperature and KGSL pwrlevel state
- Validates OPPs are present before enabling

## Files in this directory

| File | Purpose |
|------|---------|
| `sm8550_gpu_oc.c` | Core OC logic: `sm8550_gpu_oc_add_opps()` etc. (in-tree, #ifdef'd) |
| `sm8550_gpu_oc.h` | Header: freq table, CPU lane mask |
| `sm8550_gpu_oc_a6xx.c` | A6xx integration shim |
| `sm8550-gpu-turbo-overlay.dts` | Device tree overlay (Option B) |
| `sm8550_gpu_oc_runtime.sh` | Userspace runtime control |
| `sm8550_gpu_oc_entry.c` | Standalone module entry (alternative to in-tree) |
| `Kbuild` / `Makefile` | Build files for out-of-tree module |
| `README.md` | This file |

## Kernel config requirements

```
CONFIG_PM_OPP=y
CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y
CONFIG_DRM_MSM=y
CONFIG_SM8550_GPU_OC=y          # the OC feature gate
CONFIG_DEVFREQ_EVENT_MSM_GPU=y  # GPU load events for devfreq
```

## Technical notes

- Synthetic OPPs via `dev_pm_opp_add()` — appended to existing OPP table,
  no modification of device tree OPP entries needed
- GMU firmware is **not** modified — uses existing HFI `HFI_GX_SET_LEVEL`
  command with the new frequency value
- ACD (adaptive current draw) per level is preserved from device tree;
  synthetic OPPs inherit no explicit ACD word (uses device-tree default)
- Thermal: GPU thermal zone must be configured; the runtime script monitors it
- Stock frequencies (Adreno 740 / SM8550): 514 / 575 / 681 / 767 MHz
- Stock GMU chip ID: `adreno_7c3_genoa`
