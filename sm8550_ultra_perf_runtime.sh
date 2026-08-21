#!/bin/bash
# SM8550 ULTRA MAXIMUM PERFORMANCE - Comprehensive sysfs/runtime tuning
# Run at boot (init.rc) or manually as root
# Applies ALL tunable performance knobs across every subsystem

set -euo pipefail

log() { echo -e "\033[1;36m[sm8550-ultra]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }

# =========================================================================
# 1. CPU SCHEDULER / EAS / UCLAMP
# =========================================================================
log "=== CPU Scheduler / EAS / uclamp ==="

# uclamp buckets (if sysfs exposed)
for f in /proc/sys/kernel/sched_util_clamp_min /proc/sys/kernel/sched_util_clamp_max; do
    [ -w "$f" ] && echo 0 > "$f" 2>/dev/null || true
    [ -w "$f" ] && echo 1024 > "$f" 2>/dev/null || true
done

# Scheduler migration/granularity
echo 500000 > /proc/sys/kernel/sched_migration_cost_ns 2>/dev/null || true
echo 1000000 > /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null || true
echo 250000 > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null || true
echo 1000000 > /proc/sys/kernel/sched_latency_ns 2>/dev/null || true

# RT runtime: unlimited
echo -1 > /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null || true
echo 950000 > /proc/sys/kernel/sched_rt_period_us 2>/dev/null || true

# EAS energy aware scheduling
echo 1 > /proc/sys/kernel/sched_energy_aware 2>/dev/null || true

# Child runs first (reduces wakeup latency)
echo 1 > /proc/sys/kernel/sched_child_runs_first 2>/dev/null || true

# Autogroup disable (if not via cmdline)
echo 0 > /proc/sys/kernel/sched_autogroup_enabled 2>/dev/null || true

# NUMA balancing off (mobile is single-node)
echo 0 > /proc/sys/kernel/numa_balancing 2>/dev/null || true

# =========================================================================
# 2. CPUFREQ / GOVERNORS (per-policy)
# =========================================================================
log "=== CPUFreq / Governors ==="

for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$policy" ] || continue
    
    # Ensure schedutil is active
    echo schedutil > "$policy/scaling_governor" 2>/dev/null || true
    
    # Aggressive up, conservative down
    gov="$policy/schedutil"
    [ -d "$gov" ] && {
        echo 5000 > "$gov/up_rate_limit_us" 2>/dev/null || true
        echo 20000 > "$gov/down_rate_limit_us" 2>/dev/null || true
        echo 1 > "$gov/iowait_boost_enable" 2>/dev/null || true
        echo 0 > "$gov/rate_limit_us" 2>/dev/null || true  # Disable rate limiting if exposed
    }
    
    # Max freq
    [ -w "$policy/scaling_max_freq" ] && cat "$policy/cpuinfo_max_freq" > "$policy/scaling_max_freq" 2>/dev/null || true
    [ -w "$policy/scaling_min_freq" ] && echo 300000 > "$policy/scaling_min_freq" 2>/dev/null || true  # Keep low for idle
    
    # Boost frequencies (if exposed)
    [ -w "$policy/scaling_boost_freq" ] && cat "$policy/cpuinfo_max_freq" > "$policy/scaling_boost_freq" 2>/dev/null || true
done

# Global boost
echo 1 > /sys/module/cpu_boost/parameters/input_boost_enabled 2>/dev/null || true
echo "0:1036800 1:1036800 2:1036800 3:1036800 4:1401600 5:1401600 6:1401600 7:1401600" > /sys/module/cpu_boost/parameters/input_boost_freq 2>/dev/null || true
echo 200 > /sys/module/cpu_boost/parameters/input_boost_ms 2>/dev/null || true

# =========================================================================
# 3. CORE CONTROL (big.LITTLE cluster management)
# =========================================================================
log "=== Core Control ==="

# Big cluster (cpu4-7 on SM8550: 1xX3 + 3xA715)
if [ -d /sys/devices/system/cpu/cpu4/core_ctl ]; then
    echo 1 > /sys/devices/system/cpu/cpu4/core_ctl/min_cpus
    echo 4 > /sys/devices/system/cpu/cpu4/core_ctl/max_cpus
    echo 85 > /sys/devices/system/cpu/cpu4/core_ctl/busy_up_thres
    echo 35 > /sys/devices/system/cpu/cpu4/core_ctl/busy_down_thres
    echo 50 > /sys/devices/system/cpu/cpu4/core_ctl/offline_delay_ms
    echo 1 > /sys/devices/system/cpu/cpu4/core_ctl/is_big_cluster
fi

# Mid cluster (if separate)
for cpu in 1 2 3; do
    if [ -d /sys/devices/system/cpu/cpu$cpu/core_ctl ]; then
        echo 1 > /sys/devices/system/cpu/cpu$cpu/core_ctl/min_cpus
        echo 90 > /sys/devices/system/cpu/cpu$cpu/core_ctl/busy_up_thres
        echo 40 > /sys/devices/system/cpu/cpu$cpu/core_ctl/busy_down_thres
        echo 100 > /sys/devices/system/cpu/cpu$cpu/core_ctl/offline_delay_ms
    fi
done

# LITTLE cluster (cpu0)
if [ -d /sys/devices/system/cpu/cpu0/core_ctl ]; then
    echo 2 > /sys/devices/system/cpu/cpu0/core_ctl/min_cpus
    echo 4 > /sys/devices/system/cpu/cpu0/core_ctl/max_cpus
    echo 75 > /sys/devices/system/cpu/cpu0/core_ctl/busy_up_thres
    echo 30 > /sys/devices/system/cpu/cpu0/core_ctl/busy_down_thres
    echo 200 > /sys/devices/system/cpu/cpu0/core_ctl/offline_delay_ms
fi

# =========================================================================
# 4. CPU IDLE
# =========================================================================
log "=== CPU Idle ==="

for cpu in /sys/devices/system/cpu/cpu*/cpuidle; do
    [ -d "$cpu" ] || continue
    for state in "$cpu"/state*; do
        [ -d "$state" ] || continue
        # Disable deepest C-states for latency (keep C1-C2)
        name=$(cat "$state/name" 2>/dev/null || echo "")
        case "$name" in
            *C3*|*C4*|*C5*|*C6*|*C7*) echo 1 > "$state/disable" 2>/dev/null || true ;;
        esac
    done
done

# Governor: TEO (timer events oriented - better for interactive)
echo teo > /sys/devices/system/cpu/cpuidle/current_governor 2>/dev/null || true

# =========================================================================
# 5. MEMORY / ZRAM / SWAP / VM
# =========================================================================
log "=== Memory / VM / ZRAM ==="

# zram (assume zram0 exists)
if [ -b /dev/zram0 ]; then
    echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || true
    echo 4294967296 > /sys/block/zram0/disksize 2>/dev/null || true  # 4GB
    echo 4096 > /sys/block/zram0/lru_writeback_limit 2>/dev/null || true
    echo 1 > /sys/block/zram0/writeback 2>/dev/null || true
fi

# zswap
echo zstd > /sys/module/zswap/parameters/compressor 2>/dev/null || true
echo z3fold > /sys/module/zswap/parameters/zpool 2>/dev/null || true
echo 1 > /sys/module/zswap/parameters/enabled 2>/dev/null || true
echo 100 > /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || true
echo 0 > /sys/module/zswap/parameters/accept_threshold_percent 2>/dev/null || true

# frontswap
echo 1 > /sys/module/frontswap/parameters/enabled 2>/dev/null || true

# VM tunables
echo 100 > /proc/sys/vm/swappiness
echo 500 > /proc/sys/vm/vfs_cache_pressure
echo 10 > /proc/sys/vm/dirty_ratio
echo 5 > /proc/sys/vm/dirty_background_ratio
echo 3 > /proc/sys/vm/page-cluster
echo 0 > /proc/sys/vm/overcommit_memory  # Heuristic overcommit
echo 8192 > /proc/sys/vm/min_free_kbytes
echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true
echo 1 > /proc/sys/vm/compact_unevictable_allowed 2>/dev/null || true

# Hugepages
echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/defrag 2>/dev/null || true
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none 2>/dev/null || true
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_shared 2>/dev/null || true

# KSM (kernel samepage merging) - off for latency
echo 0 > /sys/kernel/mm/ksm/run 2>/dev/null || true

# =========================================================================
# 6. BLOCK / I/O SCHEDULER
# =========================================================================
log "=== Block / I/O ==="

for dev in /sys/block/sd* /sys/block/mmcblk* /sys/block/nvme*; do
    [ -e "$dev" ] || continue
    [ -w "$dev/queue/scheduler" ] && echo kyber > "$dev/queue/scheduler"
    [ -w "$dev/queue/nr_requests" ] && echo 256 > "$dev/queue/nr_requests"
    [ -w "$dev/queue/read_ahead_kb" ] && echo 0 > "$dev/queue/read_ahead_kb"
    [ -w "$dev/queue/add_random" ] && echo 0 > "$dev/queue/add_random"
    [ -w "$dev/queue/iostats" ] && echo 0 > "$dev/queue/iostats"
    [ -w "$dev/queue/nomerges" ] && echo 1 > "$dev/queue/nomerges"  # Disable merge for latency
    [ -w "$dev/queue/rq_affinity" ] && echo 2 > "$dev/queue/rq_affinity"  # Complete on same CPU
    
    # Kyber specific
    if [ -d "$dev/queue/kyber" ]; then
        echo 256 > "$dev/queue/kyber/read_lat_nsec" 2>/dev/null || true
        echo 512 > "$dev/queue/kyber/write_lat_nsec" 2>/dev/null || true
    fi
done

# =========================================================================
# 7. GPU (Adreno 740 / KGSL)
# =========================================================================
log "=== GPU (Adreno 740) ==="

if [ -d /sys/class/kgsl/kgsl-3d0 ]; then
    # Clocks
    echo 900000000 > /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null || true
    echo 900000000 > /sys/class/kgsl/kgsl-3d0/max_pwrlevel 2>/dev/null || true
    echo 1 > /sys/class/kgsl/kgsl-3d0/force_clk_on 2>/dev/null || true
    echo 1 > /sys/class/kgsl/kgsl-3d0/force_bus_on 2>/dev/null || true
    echo 0 > /sys/class/kgsl/kgsl-3d0/force_rail_on 2>/dev/null || true
    
    # Preemption
    echo 1 > /sys/class/kgsl/kgsl-3d0/preempt_timeout_ms 2>/dev/null || true
    echo 1 > /sys/class/kgsl/kgsl-3d0/preempt_enable 2>/dev/null || true
    
    # Power
    echo performance > /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null || true
    echo 1 > /sys/class/kgsl/kgsl-3d0/throttling 2>/dev/null || true
    
    # Scheduler
    echo 1 > /sys/class/kgsl/kgsl-3d0/priority 2>/dev/null || true
fi

# =========================================================================
# 8. THERMAL (userspace governor - no automatic throttling)
# =========================================================================
log "=== Thermal ==="

for zone in /sys/class/thermal/thermal_zone*; do
    [ -d "$zone" ] || continue
    # Set to userspace (manual control via perfd/thermald)
    echo user_space > "$zone/mode" 2>/dev/null || true
    # Raise trip points if writable
    for trip in "$zone"/trip_point*_temp; do
        [ -w "$trip" ] && echo 105000 > "$trip" 2>/dev/null || true  # 105°C critical
    done
done

# Disable power allocator if present
echo 0 > /sys/module/thermal/parameters/enabled 2>/dev/null || true

# =========================================================================
# 9. DEVFREQ (bus/DDR/GPU interconnect)
# =========================================================================
log "=== Devfreq / Bus scaling ==="

for devfreq in /sys/class/devfreq/*; do
    [ -d "$devfreq" ] || continue
    governor=$(cat "$devfreq/governor" 2>/dev/null || echo "")
    case "$governor" in
        simple_ondemand|ondemand)
            echo performance > "$devfreq/governor" 2>/dev/null || true
            ;;
    esac
    # Max freq
    [ -w "$devfreq/max_freq" ] && cat "$devfreq/max_freq" > "$devfreq/min_freq" 2>/dev/null || true
done

# =========================================================================
# 10. INTERRUPTS / IRQ AFFINITY
# =========================================================================
log "=== IRQ Affinity ==="

# Move IRQs to big cores (cpu4-7)
# This is approximate; actual IRQ numbers vary by device
# Common: GPU, UFS, Display, CPUs
for irq in /proc/irq/*/smp_affinity; do
    [ -w "$irq" ] && echo f0 > "$irq" 2>/dev/null || true  # cpu4-7 mask
done

# =========================================================================
# 11. NETWORK STACK (if needed for gaming/streaming)
# =========================================================================
log "=== Network ==="

echo 1 > /proc/sys/net/core/netdev_budget_usecs 2>/dev/null || true
echo 10000 > /proc/sys/net/core/netdev_budget 2>/dev/null || true
echo 2 > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || true
echo 1 > /proc/sys/net/ipv4/tcp_low_latency 2>/dev/null || true

# =========================================================================
# 12. FPU / SIMD / CRYPTO
# =========================================================================
log "=== Crypto / SIMD ==="

# Enable kernel crypto acceleration
echo 1 > /proc/sys/crypto/fips_enabled 2>/dev/null || true

# =========================================================================
# 13. LOCKDOWN / SECURITY (disable for perf)
# =========================================================================
log "=== Security (reduce overhead) ==="

echo 0 > /sys/kernel/security/lockdown 2>/dev/null || true  # May not be writable

# =========================================================================
# 14. PRINTK / CONSOLE
# =========================================================================
log "=== Console / Logging ==="

echo 3 > /proc/sys/kernel/printk 2>/dev/null || true
echo 0 > /proc/sys/kernel/printk_devkmsg 2>/dev/null || true
echo 0 > /proc/sys/kernel/printk_ratelimit 2>/dev/null || true

# =========================================================================
# 15. RCU
# =========================================================================
log "=== RCU ==="

echo 100 > /sys/module/rcutree/parameters/rcu_boost_delay 2>/dev/null || true
echo 99 > /sys/module/rcutree/parameters/rcu_boost_prio 2>/dev/null || true

# =========================================================================
# 16. SCHEDSTATS / DEBUG (off)
# =========================================================================
echo 0 > /proc/sys/kernel/sched_schedstats 2>/dev/null || true

# =========================================================================
# COMPLETION
# =========================================================================
log "=== ALL ULTRA PERFORMANCE TUNES APPLIED ==="
echo ""
echo "Verify key settings:"
echo "  Scheduler:  cat /proc/sys/kernel/sched_migration_cost_ns"
echo "  CPUFreq:    cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor"
echo "  CoreCtl:    cat /sys/devices/system/cpu/cpu4/core_ctl/min_cpus"
echo "  zram:       cat /sys/block/zram0/comp_algorithm"
echo "  GPU:        cat /sys/class/kgsl/kgsl-3d0/max_gpuclk"
echo "  I/O:        cat /sys/block/sda/queue/scheduler"
echo "  Thermal:    cat /sys/class/thermal/thermal_zone*/mode"