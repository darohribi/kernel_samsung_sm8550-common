#!/bin/bash
# SM8550 Maximum Performance Runtime Profile
# Run at boot via init.rc / vendor init / kernel cmdline hook
# Applies vendor-specific tunables that can't be in GKI common kernel config

set -euo pipefail

log() { echo "[sm8550-perf] $*"; }

# =========================================================================
# SCHEDULER / UCLAMP (via cgroups)
# =========================================================================
log "Configuring uclamp..."

# Foreground / top-app: guarantee minimum CPU share
[ -w /dev/cpuctl/top-app/uclamp.min ] && echo 200 > /dev/cpuctl/top-app/uclamp.min
[ -w /dev/cpuctl/foreground/uclamp.min ] && echo 100 > /dev/cpuctl/foreground/uclamp.min

# Background: cap at 60%
[ -w /dev/cpuctl/background/uclamp.max ] && echo 600 > /dev/cpuctl/background/uclamp.max

# RT tasks: high priority
[ -w /dev/cpuctl/rt/uclamp.min ] && echo 800 > /dev/cpuctl/rt/uclamp.min

# =========================================================================
# CPUFREQ: schedutil responsiveness
# =========================================================================
log "Tuning schedutil governor..."
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    gov_path="$policy/schedutil"
    [ -d "$gov_path" ] || continue
    [ -w "$gov_path/up_rate_limit_us" ] && echo 10000 > "$gov_path/up_rate_limit_us"
    [ -w "$gov_path/down_rate_limit_us" ] && echo 50000 > "$gov_path/down_rate_limit_us"
    [ -w "$gov_path/iowait_boost_enable" ] && echo 1 > "$gov_path/iowait_boost_enable"
done

# =========================================================================
# CPU BOOST (downstream vendor driver)
# =========================================================================
if [ -f /sys/module/cpu_boost/parameters/input_boost_enabled ]; then
    log "Enabling CPU input boost..."
    echo 1 > /sys/module/cpu_boost/parameters/input_boost_enabled
    # Boost all little + mid cores to ~1.0 GHz for 120ms on touch
    echo "0:1036800 1:1036800 2:1036800 3:1036800" > /sys/module/cpu_boost/parameters/input_boost_freq 2>/dev/null || true
    echo 120 > /sys/module/cpu_boost/parameters/input_boost_ms
fi

# =========================================================================
# CORE CONTROL (downstream vendor driver)
# =========================================================================
if [ -f /sys/devices/system/cpu/cpu4/core_ctl/min_cpus ]; then
    log "Configuring core_ctl (big cluster)..."
    # Keep at least 1 big core online
    echo 1 > /sys/devices/system/cpu/cpu4/core_ctl/min_cpus
    echo 80 > /sys/devices/system/cpu/cpu4/core_ctl/busy_up_thres
    echo 30 > /sys/devices/system/cpu/cpu4/core_ctl/busy_down_thres
    echo 100 > /sys/devices/system/cpu/cpu4/core_ctl/offline_delay_ms
fi

if [ -f /sys/devices/system/cpu/cpu0/core_ctl/min_cpus ]; then
    log "Configuring core_ctl (LITTLE cluster)..."
    echo 2 > /sys/devices/system/cpu/cpu0/core_ctl/min_cpus
    echo 70 > /sys/devices/system/cpu/cpu0/core_ctl/busy_up_thres
    echo 25 > /sys/devices/system/cpu/cpu0/core_ctl/busy_down_thres
    echo 200 > /sys/devices/system/cpu/cpu0/core_ctl/offline_delay_ms
fi

# =========================================================================
# I/O SCHEDULER (UFS 4.0 prefers kyber/none)
# =========================================================================
log "Setting I/O scheduler..."
for block in /sys/block/sd*; do
    [ -e "$block" ] || continue
    [ -w "$block/queue/scheduler" ] && echo kyber > "$block/queue/scheduler"
    [ -w "$block/queue/nr_requests" ] && echo 256 > "$block/queue/nr_requests"
    [ -w "$block/queue/read_ahead_kb" ] && echo 0 > "$block/queue/read_ahead_kb"
done

# =========================================================================
# GPU (Adreno 740)
# =========================================================================
if [ -d /sys/class/kgsl/kgsl-3d0 ]; then
    log "Tuning GPU..."
    echo 1 > /sys/class/kgsl/kgsl-3d0/force_clk_on 2>/dev/null || true
    echo 1 > /sys/class/kgsl/kgsl-3d0/force_bus_on 2>/dev/null || true
    echo 900000000 > /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null || true
    # Disable forced rail (let RPMh manage)
    echo 0 > /sys/class/kgsl/kgsl-3d0/force_rail_on 2>/dev/null || true
fi

# =========================================================================
# VIRTUAL MEMORY
# =========================================================================
log "Tuning VM..."
[ -w /proc/sys/vm/swappiness ] && echo 100 > /proc/sys/vm/swappiness
[ -w /proc/sys/vm/vfs_cache_pressure ] && echo 500 > /proc/sys/vm/vfs_cache_pressure
[ -w /proc/sys/vm/dirty_ratio ] && echo 10 > /proc/sys/vm/dirty_ratio
[ -w /proc/sys/vm/dirty_background_ratio ] && echo 5 > /proc/sys/vm/dirty_background_ratio
[ -w /proc/sys/vm/page-cluster ] && echo 3 > /proc/sys/vm/page-cluster

# =========================================================================
# THERMAL (if userspace governor active)
# =========================================================================
if [ -d /sys/class/thermal ]; then
    log "Checking thermal zones..."
    for zone in /sys/class/thermal/thermal_zone*; do
        [ -w "$zone/mode" ] && echo user_space > "$zone/mode" 2>/dev/null || true
    done
fi

log "SM8550 performance profile applied."