#!/bin/bash
# SM8550 BENCHMARK MODE - ABSOLUTE MAXIMUM PERFORMANCE
# ============================================================
# WARNING: This disables ALL safety margins, thermal protection,
# power limits, and stability guards. Use ONLY for benchmark runs.
# Will cause: overheating, instability, data loss, hardware damage.
# ============================================================

set -euo pipefail

log() { echo -e "\033[1;31m[BENCH]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }

# =========================================================================
# DISABLE ALL THERMAL PROTECTION
# =========================================================================
log "=== DISABLING ALL THERMAL PROTECTION ==="

# Set all thermal zones to userspace with MAX critical temps
for zone in /sys/class/thermal/thermal_zone*; do
    [ -d "$zone" ] || continue
    echo user_space > "$zone/mode" 2>/dev/null || true
    
    # Set trip points to MAXIMUM possible
    for trip in "$zone"/trip_point*_temp; do
        [ -w "$trip" ] && echo 125000 > "$trip" 2>/dev/null || true  # 125°C
    done
done

# Disable thermal framework entirely if possible
echo 0 > /sys/module/thermal/parameters/enabled 2>/dev/null || true

# Disable thermald/perfd thermal pressure
echo 0 > /sys/module/msm_thermal/parameters/enabled 2>/dev/null || true

# =========================================================================
# CPU: MAX FREQUENCY LOCK (all cores, all clusters)
# =========================================================================
log "=== LOCKING ALL CORES TO MAX FREQUENCY ==="

for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$policy" ] || continue
    
    # Disable governor, use userspace
    echo userspace > "$policy/scaling_governor" 2>/dev/null || true
    
    # Lock to max frequency
    maxf=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo 0)
    [ "$maxf" -gt 0 ] && echo "$maxf" > "$policy/scaling_setspeed" 2>/dev/null || true
    [ "$maxf" -gt 0 ] && echo "$maxf" > "$policy/scaling_min_freq" 2>/dev/null || true
    [ "$maxf" -gt 0 ] && echo "$maxf" > "$policy/scaling_max_freq" 2>/dev/null || true
done

# Core control: FORCE ALL CORES ONLINE
log "=== FORCING ALL CORES ONLINE ==="
for cpu in /sys/devices/system/cpu/cpu*/online; do
    [ -w "$cpu" ] && echo 1 > "$cpu" 2>/dev/null || true
done

# Disable core_ctl entirely
for ctl in /sys/devices/system/cpu/cpu*/core_ctl; do
    [ -d "$ctl" ] && {
        echo 0 > "$ctl/enabled" 2>/dev/null || true
        # Set min=max=all cores
        n=$(ls /sys/devices/system/cpu/cpu*/core_ctl 2>/dev/null | wc -l)
        [ -w "$ctl/min_cpus" ] && echo $n > "$ctl/min_cpus" 2>/dev/null || true
    }
done

# CPU Boost: MAXIMUM
echo 1 > /sys/module/cpu_boost/parameters/input_boost_enabled 2>/dev/null || true
# Lock boost to max freq for ALL cores
echo "0:3187200 1:3187200 2:3187200 3:3187200 4:3187200 5:3187200 6:3187200 7:3187200" > /sys/module/cpu_boost/parameters/input_boost_freq 2>/dev/null || true
echo 10000 > /sys/module/cpu_boost/parameters/input_boost_ms 2>/dev/null || true  # 10 second boost

# =========================================================================
# GPU: MAX FREQUENCY LOCK
# =========================================================================
log "=== LOCKING GPU TO MAX FREQUENCY ==="

if [ -d /sys/class/kgsl/kgsl-3d0 ]; then
    echo userspace > /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null || true
    echo 900000000 > /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null || true
    echo 900000000 > /sys/class/kgsl/kgsl-3d0/min_gpuclk 2>/dev/null || true
    echo 900000000 > /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null || true
    
    # Disable all GPU power management
    echo 0 > /sys/class/kgsl/kgsl-3d0/pwrlevel 2>/dev/null || true
    echo 1 > /sys/class/kgsl/kgsl-3d0/force_clk_on 2>/dev/null || true
    echo 1 > /sys/class/kgsl/kgsl-3d0/force_bus_on 2>/dev/null || true
    echo 1 > /sys/class/kgsl/kgsl-3d0/force_rail_on 2>/dev/null || true
    
    # Max bus bandwidth
    echo 51200 > /sys/class/kgsl/kgsl-3d0/max_pwrlevel 2>/dev/null || true
fi

# =========================================================================
# DDR / BUS: MAX BANDWIDTH
# =========================================================================
log "=== MAXIMIZING DDR / BUS BANDWIDTH ==="

for devfreq in /sys/class/devfreq/*; do
    [ -d "$devfreq" ] || continue
    echo performance > "$devfreq/governor" 2>/dev/null || true
    maxf=$(cat "$devfreq/max_freq" 2>/dev/null || echo 0)
    [ "$maxf" -gt 0 ] && echo "$maxf" > "$devfreq/min_freq" 2>/dev/null || true
done

# BIMC / DDR
echo 51200 > /sys/class/devfreq/soc:qcom,mincpubw/max_freq 2>/dev/null || true
echo 51200 > /sys/class/devfreq/soc:qcom,mincpubw/min_freq 2>/dev/null || true

# =========================================================================
# SCHEDULER: AGGRESSIVE REAL-TIME
# =========================================================================
log "=== SCHEDULER: REAL-TIME PRIORITY ==="

# Disable all fairness, go pure throughput
echo 0 > /proc/sys/kernel/sched_child_runs_first 2>/dev/null || true
echo 0 > /proc/sys/kernel/sched_autogroup_enabled 2>/dev/null || true
echo 0 > /proc/sys/kernel/sched_migration_cost_ns 2>/dev/null || true
echo 100000 > /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null || true
echo 50000 > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null || true
echo 200000 > /proc/sys/kernel/sched_latency_ns 2>/dev/null || true

# RT runtime: UNLIMITED
echo -1 > /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null || true

# Uclamp: all tasks at MAX
for cg in /dev/cpuctl/*/uclamp.min; do
    [ -w "$cg" ] && echo 1024 > "$cg" 2>/dev/null || true
done
for cg in /dev/cpuctl/*/uclamp.max; do
    [ -w "$cg" ] && echo 1024 > "$cg" 2>/dev/null || true
done

# Energy aware scheduling: OFF (pure performance)
echo 0 > /proc/sys/kernel/sched_energy_aware 2>/dev/null || true

# =========================================================================
# MEMORY: DISABLE ALL COMPACTION/RECLAIM OVERHEAD
# =========================================================================
log "=== MEMORY: ZERO OVERHEAD ==="

echo 0 > /proc/sys/vm/swappiness
echo 0 > /proc/sys/vm/vfs_cache_pressure
echo 0 > /proc/sys/vm/dirty_ratio
echo 0 > /proc/sys/vm/dirty_background_ratio
echo 0 > /proc/sys/vm/page-cluster
echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true
echo 1 > /proc/sys/vm/compact_unevictable_allowed 2>/dev/null || true
echo 0 > /proc/sys/vm/overcommit_memory
echo 1 > /proc/sys/vm/overcommit_ratio

# Hugepages: MAX
echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/defrag 2>/dev/null || true

# KSM: OFF
echo 0 > /sys/kernel/mm/ksm/run 2>/dev/null || true

# ZRAM: disable writeback (latency)
echo 0 > /sys/block/zram0/writeback 2>/dev/null || true

# =========================================================================
# I/O: RAW MODE (no scheduler, no merges)
# =========================================================================
log "=== I/O: RAW MODE ==="

for dev in /sys/block/sd* /sys/block/mmcblk* /sys/block/nvme*; do
    [ -e "$dev" ] || continue
    echo none > "$dev/queue/scheduler" 2>/dev/null || true
    echo 0 > "$dev/queue/nomerges" 2>/dev/null || true  # Actually DO merge for throughput
    echo 0 > "$dev/queue/add_random" 2>/dev/null || true
    echo 0 > "$dev/queue/iostats" 2>/dev/null || true
    echo 1024 > "$dev/queue/nr_requests" 2>/dev/null || true
    echo 2 > "$dev/queue/rq_affinity" 2>/dev/null || true
    echo 0 > "$dev/queue/read_ahead_kb" 2>/dev/null || true
done

# =========================================================================
# IRQ: PIN ALL TO PRIME CORE (cpu7)
# =========================================================================
log "=== IRQ AFFINITY: PIN TO PRIME CORE ==="

# Prime core mask (cpu7 = 0x80)
for irq in /proc/irq/*/smp_affinity; do
    [ -w "$irq" ] && echo 80 > "$irq" 2>/dev/null || true
done

# =========================================================================
# PM QOS: MAXIMUM
# =========================================================================
log "=== PM QOS: MAXIMUM ==="

for qos in /sys/devices/system/cpu/cpu*/pm_qos_resume_latency_us; do
    [ -w "$qos" ] && echo 0 > "$qos" 2>/dev/null || true
done

# =========================================================================
# CPU IDLE: DISABLE ALL
# =========================================================================
log "=== DISABLING ALL CPU IDLE STATES ==="

for cpu in /sys/devices/system/cpu/cpu*/cpuidle; do
    [ -d "$cpu" ] || continue
    for state in "$cpu"/state*; do
        [ -d "$state" ] && echo 1 > "$state/disable" 2>/dev/null || true
    done
done

# =========================================================================
# GPU: DISABLE ALL POWER SAVING
# =========================================================================
log "=== GPU: DISABLE ALL POWER SAVING ==="

if [ -d /sys/class/kgsl/kgsl-3d0 ]; then
    echo 0 > /sys/class/kgsl/kgsl-3d0/throttling 2>/dev/null || true
    echo 0 > /sys/class/kgsl/kgsl-3d0/bus_split 2>/dev/null || true
    echo 1 > /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null || true
fi

# =========================================================================
# PMIC / RPMh: MAX POWER (if accessible)
# =========================================================================
log "=== PMIC: MAX POWER MODE ==="

# These require root + kernel support
echo 0 > /sys/module/pm8005_charger/parameters/charging_disabled 2>/dev/null || true
echo 5000000 > /sys/class/power_supply/battery/constant_charge_current_max 2>/dev/null || true

# =========================================================================
# NETWORK: MAX THROUGHPUT
# =========================================================================
log "=== NETWORK: MAX THROUGHPUT ==="

echo 262144 > /proc/sys/net/core/rmem_max 2>/dev/null || true
echo 262144 > /proc/sys/net/core/wmem_max 2>/dev/null || true
echo 262144 > /proc/sys/net/core/rmem_default 2>/dev/null || true
echo 262144 > /proc/sys/net/core/wmem_default 2>/dev/null || true

# =========================================================================
# DISABLE ALL LOGGING/DEBUG
# =========================================================================
log "=== DISABLLING ALL LOGGING ==="

echo 0 > /proc/sys/kernel/printk 2>/dev/null || true
echo 0 > /proc/sys/kernel/printk_devkmsg 2>/dev/null || true
echo 0 > /proc/sys/kernel/printk_ratelimit 2>/dev/null || true

# =========================================================================
# RCU: MINIMUM LATENCY
# =========================================================================
log "=== RCU: MINIMUM LATENCY ==="

echo 0 > /sys/module/rcutree/parameters/rcu_boost_delay 2>/dev/null || true
echo 99 > /sys/module/rcutree/parameters/rcu_boost_prio 2>/dev/null || true

# =========================================================================
# COMPLETION
# =========================================================================
log "=== BENCHMARK MODE ACTIVATED ==="
warn "SYSTEM IS NOW UNSTABLE - MONITOR TEMPERATURES!"
warn "Run benchmark NOW, then run 'sm8550_restore_normal.sh' immediately after"

cat << 'EOF'

=== VERIFY BENCHMARK MODE ===
# CPU freqs (should all be max):
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq

# GPU freq (should be 900000000):
cat /sys/class/kgsl/kgsl-3d0/gpuclk

# All cores online:
cat /sys/devices/system/cpu/online

# Thermal zones (should be user_space):
cat /sys/class/thermal/thermal_zone*/mode

# I/O scheduler (should be none):
cat /sys/block/sda/queue/scheduler

EOF