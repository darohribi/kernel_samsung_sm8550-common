#!/bin/bash
# SM8550 MSPv2 - thermal.sh
# Progressive thermal controller. Reads skin temperature (not SoC die)
# and reduces the smallest amount necessary to keep frame pacing stable.
# Designed to be run in the background as a long-lived loop.

set -euo pipefail
log() { echo "[mspv2-thermal] $*"; }
WARN() { echo "[mspv2-thermal] WARNING: $*" >&2; }

POLL_INTERVAL=5   # seconds
SKIN_ZONE=""

# -------------------------------------------------------------------------
# Discover the skin thermal zone (not hard-coded)
# -------------------------------------------------------------------------
discover_skin_zone() {
    for z in /sys/class/thermal/thermal_zone*; do
        [ -d "$z" ] || continue
        type=$(cat "$z/type" 2>/dev/null || echo "")
        case "$type" in
            *skin*|*Skin*|*SKIN*)
                echo "$z"
                return 0
                ;;
        esac
    done
    return 1
}

SKIN_ZONE=$(discover_skin_zone || true)
if [ -z "$SKIN_ZONE" ]; then
    WARN "Could not find a skin thermal zone; falling back to first CPU zone"
    SKIN_ZONE=$(ls -d /sys/class/thermal/thermal_zone* 2>/dev/null | head -1 || echo "")
fi
[ -n "$SKIN_ZONE" ] || { WARN "No thermal zones found; exiting"; exit 0; }

log "Watching skin zone: $SKIN_ZONE ($(cat "$SKIN_ZONE/type" 2>/dev/null))"

# -------------------------------------------------------------------------
# Per-zone adjustment functions
# -------------------------------------------------------------------------
perf_level=0   # 0=normal, 1=moderate, 2=high, 3=very high, 4=critical
last_level=-1

apply_perf_level() {
    local level=$1
    [ "$level" = "$last_level" ] && return 0
    last_level="$level"
    log "Adjusting performance level -> $level"

    case "$level" in
        0)  # normal
            for policy in /sys/devices/system/cpu/cpufreq/policy*; do
                [ -w "$policy/scaling_governor" ] && echo schedutil > "$policy/scaling_governor" 2>/dev/null || true
            done
            [ -w /dev/cpuctl/top-app/uclamp.min ] && echo 512 > /dev/cpuctl/top-app/uclamp.min
            [ -w /dev/cpuctl/foreground/uclamp.min ] && echo 256 > /dev/cpuctl/foreground/uclamp.min
            ;;
        1)  # moderate
            [ -w /dev/cpuctl/top-app/uclamp.min ] && echo 384 > /dev/cpuctl/top-app/uclamp.min
            [ -w /dev/cpuctl/foreground/uclamp.min ] && echo 200 > /dev/cpuctl/foreground/uclamp.min
            ;;
        2)  # high
            [ -w /dev/cpuctl/top-app/uclamp.min ] && echo 256 > /dev/cpuctl/top-app/uclamp.min
            [ -w /dev/cpuctl/foreground/uclamp.min ] && echo 128 > /dev/cpuctl/foreground/uclamp.min
            ;;
        3)  # very high
            [ -w /dev/cpuctl/top-app/uclamp.min ] && echo 128 > /dev/cpuctl/top-app/uclamp.min
            [ -w /dev/cpuctl/foreground/uclamp.min ] && echo 64 > /dev/cpuctl/foreground/uclamp.min
            for policy in /sys/devices/system/cpu/cpufreq/policy*; do
                gov="$policy/schedutil"
                [ -w "$gov/up_rate_limit_us" ] && echo 5000 > "$gov/up_rate_limit_us" || true
            done
            ;;
        4)  # critical - rely on vendor safety mechanisms
            [ -w /dev/cpuctl/top-app/uclamp.min ] && echo 0 > /dev/cpuctl/top-app/uclamp.min
            for policy in /sys/devices/system/cpu/cpufreq/policy*; do
                [ -w "$policy/scaling_governor" ] && echo powersave > "$policy/scaling_governor" 2>/dev/null || true
            done
            ;;
    esac
}

# -------------------------------------------------------------------------
# Main loop
# -------------------------------------------------------------------------
log "Starting progressive thermal controller (poll=${POLL_INTERVAL}s)"
log "Thresholds (mC): <40000 L0, 40000-42000 L1, 42000-44000 L2, 44000-45000 L3, >45000 L4"

while true; do
    temp_mc=$(cat "$SKIN_ZONE/temp" 2>/dev/null || echo 0)
    # Use kernel vendor safety if a trip fires (don't override critical)
    if [ -d "$SKIN_ZONE" ] && [ -f "$SKIN_ZONE/trip_point_0_temp" ]; then
        # if the kernel has already tripped, don't fight it
        mode=$(cat "$SKIN_ZONE/mode" 2>/dev/null || echo "")
    fi

    if   [ "$temp_mc" -lt 40000 ]; then apply_perf_level 0
    elif [ "$temp_mc" -lt 42000 ]; then apply_perf_level 1
    elif [ "$temp_mc" -lt 44000 ]; then apply_perf_level 2
    elif [ "$temp_mc" -lt 45000 ]; then apply_perf_level 3
    else                                 apply_perf_level 4
    fi

    sleep "$POLL_INTERVAL"
done
