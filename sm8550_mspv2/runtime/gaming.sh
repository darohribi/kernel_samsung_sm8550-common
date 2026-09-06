#!/bin/bash
# SM8550 MSPv2 - gaming.sh
# High-burst, low-latency profile for game starts.
# Pairs with thermal.sh which will scale DOWN if skin temp rises.
# Use temporarily; do not leave running in background.
#
# NOTE: This profile modifies C-states. Restore with restore.sh when done.

set -euo pipefail
log() { echo "[mspv2-gaming] $*"; }

# Capture current state for restore
# shellcheck source=../tools/capture_state.sh
. "$(dirname "${BASH_SOURCE[0]}")/../tools/capture_state.sh"

# -------------------------------------------------------------------------
# UCLAMP - boost top-app and a dedicated "gaming" cgroup
# -------------------------------------------------------------------------
[ -w /dev/cpuctl/top-app/uclamp.min ] && echo 768 > /dev/cpuctl/top-app/uclamp.min
[ -w /dev/cpuctl/top-app/uclamp.max ] && echo 1024 > /dev/cpuctl/top-app/uclamp.max

if [ -d /dev/cpuctl/gaming ]; then
    [ -w /dev/cpuctl/gaming/uclamp.min ] && echo 650 > /dev/cpuctl/gaming/uclamp.min
    [ -w /dev/cpuctl/gaming/uclamp.max ] && echo 1024 > /dev/cpuctl/gaming/uclamp.max
fi

# -------------------------------------------------------------------------
# schedutil - more aggressive ramp
# -------------------------------------------------------------------------
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    gov="$policy/schedutil"
    [ -d "$gov" ] || continue
    [ -w "$gov/up_rate_limit_us" ]   && echo 1000 > "$gov/up_rate_limit_us"
    [ -w "$gov/down_rate_limit_us" ] && echo 8000 > "$gov/down_rate_limit_us"
done

# -------------------------------------------------------------------------
# CPU idle - detect and disable deepest state(s) based on latency/depth
# -------------------------------------------------------------------------
# Strategy: Find the deepest available idle state per CPU (highest exit
# latency + residency) and disable ONLY that one. This reduces wake-up
# latency during gaming without killing all idle power saving.
# Qualcomm CPUs typically expose 3-5 idle states per CPU.
# We identify the deepest by exit_latency_us and disable only that.

log "Detecting and disabling deepest idle state per CPU..."
disable_deepest_idle() {
    for cpu_dir in /sys/devices/system/cpu/cpu*; do
        [ -d "$cpu_dir/cpuidle" ] || continue
        local cpu_name deepest deepest_latency
        cpu_name=$(basename "$cpu_dir")
        deepest=""
        deepest_latency=0
        for state in "$cpu_dir"/cpuidle/state*; do
            [ -d "$state" ] || continue
            [ -w "$state/disable" ] || continue
            local latency
            latency=$(cat "$state/exit_latency_us" 2>/dev/null || echo "0")
            if [ "$latency" -gt "$deepest_latency" ]; then
                deepest_latency=$latency
                deepest=$state
            fi
        done
        if [ -n "$deepest" ] && [ -w "$deepest/disable" ]; then
            local desc lat
            desc=$(cat "$deepest/desc" 2>/dev/null || echo "unknown")
            lat=$(cat "$deepest/exit_latency_us" 2>/dev/null || echo "?")
            echo 1 > "$deepest/disable" 2>/dev/null || true
            log "  $cpu_name: disabled deepest idle ($desc, exit_latency=${lat}us)"
        fi
    done
}

# Disable deepest idle state per CPU (better than disabling by name)
disable_deepest_idle

# -------------------------------------------------------------------------
# GPU: performance governor + set floor to 80% of max
# No permanent force_clk_on / force_bus_on — those defeat dynamic power.
# -------------------------------------------------------------------------
for devfreq in /sys/class/devfreq/*; do
    [ -d "$devfreq" ] || continue
    dev_name=$(basename "$devfreq")
    # Only touch GPU-related devfreq domains
    case "$dev_name" in
        *gpu*|*Gx*|*mx*|*kgsl*|*mdss*)
            [ -w "$devfreq/governor" ] && echo performance > "$devfreq/governor" 2>/dev/null || true
            # Set 80% floor
            if [ -w "$devfreq/min_freq" ]; then
                max_freq=$(cat "$devfreq/max_freq" 2>/dev/null || echo "0")
                if [ -n "$max_freq" ] && [ "$max_freq" -gt 0 ]; then
                    floor=$((max_freq * 80 / 100))
                    echo "$floor" > "$devfreq/min_freq" 2>/dev/null || true
                    log "  GPU devfreq $dev_name: min_freq set to 80% ($floor Hz)"
                fi
            fi
            ;;
    esac
done

# -------------------------------------------------------------------------
# I/O: tighter latency for storage during gaming
# -------------------------------------------------------------------------
for queue in /sys/block/*/queue; do
    [ -d "$queue" ] || continue
    [ -w "$queue/read_ahead_kb" ] && echo 128 > "$queue/read_ahead_kb" 2>/dev/null || true
    [ -w "$queue/nr_requests" ] && echo 64 > "$queue/nr_requests" 2>/dev/null || true
    [ -w "$queue/nomerges" ] && echo 1 > "$queue/nomerges" 2>/dev/null || true
done

log "Gaming profile active. Run restore.sh to revert."
