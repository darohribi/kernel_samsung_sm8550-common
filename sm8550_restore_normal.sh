#!/bin/bash
# SM8550 RESTORE NORMAL MODE
# Run after benchmark to restore safe thermal/performance settings

set -euo pipefail

log() { echo -e "\033[1;32m[RESTORE]\033[0m $*"; }

log "=== RESTORING NORMAL OPERATION ==="

# =========================================================================
# THERMAL: RESTORE SAFETY
# =========================================================================
log "Restoring thermal protection..."
for zone in /sys/class/thermal/thermal_zone*; do
    [ -d "$zone" ] || continue
    echo enabled > "$zone/mode" 2>/dev/null || true
    # Restore default trip points (will be set by thermald)
done

echo 1 > /sys/module/thermal/parameters/enabled 2>/dev/null || true
echo 1 > /sys/module/msm_thermal/parameters/enabled 2>/dev/null || true

# =========================================================================
# CPU: RESTORE GOVERNORS
# =========================================================================
log "Restoring CPU governors..."
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$policy" ] || continue
    echo schedutil > "$policy/scaling_governor" 2>/dev/null || true
    
    # Restore min/max
    minf=$(cat "$policy/cpuinfo_min_freq" 2>/dev/null || echo 300000)
    maxf=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo 3187200)
    echo "$minf" > "$policy/scaling_min_freq" 2>/dev/null || true
    echo "$maxf" > "$policy/scaling_max_freq" 2>/dev/null || true
done

# Core control: restore
for ctl in /sys/devices/system/cpu/cpu*/core_ctl; do
    [ -d "$ctl" ] && {
        echo 1 > "$ctl/enabled" 2>/dev/null || true
    }
done

# CPU Boost: normal
echo 1 > /sys/module/cpu_boost/parameters/input_boost_enabled 2>/dev/null || true
echo "0:1036800 1:1036800 2:1036800 3:1036800" > /sys/module/cpu_boost/parameters/input_boost_freq 2>/dev/null || true
echo 120 > /sys/module/cpu_boost/parameters/input_boost_ms 2>/dev/null || true

# =========================================================================
# GPU: RESTORE
# =========================================================================
log "Restoring GPU..."
if [ -d /sys/class/kgsl/kgsl-3d0 ]; then
    echo simple_ondemand > /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null || true
    echo 300000000 > /sys/class/kgsl/kgsl-3d0/min_gpuclk 2>/dev/null || true
    echo 900000000 > /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null || true
    echo 0 > /sys/class/kgsl/kgsl-3d0/force_clk_on 2>/dev/null || true
    echo 0 > /sys/class/kgsl/kgsl-3d0/force_bus_on 2>/dev/null || true
    echo 0 > /sys/class/kgsl/kgsl-3d0/force_rail_on 2>/dev/null || true
    echo 1 > /sys/class/kgsl/kgsl-3d0/throttling 2>/dev/null || true
fi

# =========================================================================
# DDR / BUS: RESTORE
# =========================================================================
log "Restoring DDR/bus..."
for devfreq in /sys/class/devfreq/*; do
    [ -d "$devfreq" ] || continue
    echo simple_ondemand > "$devfreq/governor" 2>/dev/null || true
done

# =========================================================================
# SCHEDULER: RESTORE
# =========================================================================
log "Restoring scheduler..."
echo 500000 > /proc/sys/kernel/sched_migration_cost_ns 2>/dev/null || true
echo 1000000 > /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null || true
echo 250000 > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null || true
echo 1000000 > /proc/sys/kernel/sched_latency_ns 2>/dev/null || true
echo 1 > /proc/sys/kernel/sched_child_runs_first 2>/dev/null || true
echo 1 > /proc/sys/kernel/sched_autogroup_enabled 2>/dev/null || true
echo 950000 > /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null || true
echo 1 > /proc/sys/kernel/sched_energy_aware 2>/dev/null || true

# Uclamp: restore defaults
echo 200 > /dev/cpuctl/top-app/uclamp.min 2>/dev/null || true
echo 100 > /dev/cpuctl/foreground/uclamp.min 2>/dev/null || true
echo 600 > /dev/cpuctl/background/uclamp.max 2>/dev/null || true
echo 800 > /dev/cpuctl/rt/uclamp.min 2>/dev/null || true

# =========================================================================
# MEMORY: RESTORE
# =========================================================================
log "Restoring memory..."
echo 100 > /proc/sys/vm/swappiness
echo 500 > /proc/sys/vm/vfs_cache_pressure
echo 10 > /proc/sys/vm/dirty_ratio
echo 5 > /proc/sys/vm/dirty_background_ratio
echo 3 > /proc/sys/vm/page-cluster
echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true

# =========================================================================
# I/O: RESTORE
# =========================================================================
log "Restoring I/O..."
for dev in /sys/block/sd* /sys/block/mmcblk*; do
    [ -e "$dev" ] || continue
    echo kyber > "$dev/queue/scheduler" 2>/dev/null || true
    echo 256 > "$dev/queue/nr_requests" 2>/dev/null || true
    echo 1 > "$dev/queue/nomerges" 2>/dev/null || true
    echo 1 > "$dev/queue/add_random" 2>/dev/null || true
    echo 1 > "$dev/queue/iostats" 2>/dev/null || true
    echo 2 > "$dev/queue/rq_affinity" 2>/dev/null || true
done

# =========================================================================
# IRQ: RESTORE
# =========================================================================
log "Restoring IRQ affinity..."
for irq in /proc/irq/*/smp_affinity; do
    [ -w "$irq" ] && echo f0 > "$irq" 2>/dev/null || true
done

# =========================================================================
# CPU IDLE: RESTORE
# =========================================================================
log "Restoring CPU idle..."
echo teo > /sys/devices/system/cpu/cpuidle/current_governor 2>/dev/null || true
for cpu in /sys/devices/system/cpu/cpu*/cpuidle; do
    [ -d "$cpu" ] || continue
    for state in "$cpu"/state*; do
        [ -d "$state" ] && echo 0 > "$state/disable" 2>/dev/null || true
    done
done

# =========================================================================
# LOGGING: RESTORE
# =========================================================================
echo 3 > /proc/sys/kernel/printk 2>/dev/null || true

# =========================================================================
# RCU: RESTORE
# =========================================================================
echo 100 > /sys/module/rcutree/parameters/rcu_boost_delay 2>/dev/null || true
echo 99 > /sys/module/rcutree/parameters/rcu_boost_prio 2>/dev/null || true

# =========================================================================
# VERIFY
# =========================================================================
log "=== RESTORATION COMPLETE ==="
echo "Verify:"
echo "  CPU gov: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"
echo "  GPU gov: $(cat /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null)"
echo "  Thermal: $(cat /sys/class/thermal/thermal_zone0/mode 2>/dev/null)"
echo "  Cores online: $(cat /sys/devices/system/cpu/online)"
echo "  I/O sched: $(cat /sys/block/sda/queue/scheduler)"