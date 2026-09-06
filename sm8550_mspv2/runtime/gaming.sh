#!/bin/bash
# SM8550 MSPv2 - gaming.sh
# High-burst, low-latency profile for game starts.
# Pairs with thermal.sh which will scale DOWN if skin temp rises.
# Use temporarily; do not leave running in background.

set -euo pipefail
log() { echo "[mspv2-gaming] $*"; }

# -------------------------------------------------------------------------
# UCLAMP - boost top-app and a dedicated "gaming" cgroup
# -------------------------------------------------------------------------
# Top-app gets a high floor but not 1024
[ -w /dev/cpuctl/top-app/uclamp.min ] && echo 768 > /dev/cpuctl/top-app/uclamp.min
[ -w /dev/cpuctl/top-app/uclamp.max ] && echo 1024 > /dev/cpuctl/top-app/uclamp.max

# If a "gaming" cgroup exists, boost it
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
# CPU idle - only disable the DEEPEST state during the game,
# leave others enabled so we keep thermal headroom.
# -------------------------------------------------------------------------
# Mark deep C-states (C6, C7) as disabled on all CPUs for the duration
# of the game. They will be re-enabled by restore.sh on game end.
for state in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
    [ -d "$state" ] || continue
    [ -w "$state/disable" ] || continue
    desc=$(cat "$state/desc" 2>/dev/null || echo "")
    case "$desc" in
        *"C6"*|*"C7"*|*"pc6"*|*"pc7"*)
            echo 1 > "$state/disable" 2>/dev/null || true
            ;;
    esac
done

# -------------------------------------------------------------------------
# GPU: performance governor + raise floor (NOT max)
# -------------------------------------------------------------------------
# No permanent force_clk_on / force_bus_on. Those defeat dynamic power.

# -------------------------------------------------------------------------
# I/O: tighter latency for storage
# -------------------------------------------------------------------------
for queue in /sys/block/*/queue; do
    [ -d "$queue" ] || continue
    [ -w "$queue/read_ahead_kb" ] && echo 128 > "$queue/read_ahead_kb" 2>/dev/null || true
    [ -w "$queue/nr_requests" ] && echo 64 > "$queue/nr_requests" 2>/dev/null || true
    [ -w "$queue/nomerges" ] && echo 1 > "$queue/nomerges" 2>/dev/null || true
done

log "gaming profile active. Run restore.sh to revert."
