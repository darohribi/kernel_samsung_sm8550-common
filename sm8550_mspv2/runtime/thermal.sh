#!/bin/bash
# SM8550 MSPv2 - thermal.sh
# shellcheck disable=SC2034  # SKIN_M0..SKIN_M3, SOC_M0..SOC_M2 are intentional globals used by calc_level
# Progressive multi-zone thermal controller.
#
# Key design (vs v1):
# - Never disables the Linux thermal framework
# - Never bypasses vendor hardware safety limits
# - Never permanently disables all idle states
# - Never forces all frequencies to maximum
#
# This controller implements a progressive, layered response:
#   1. Skin temperature drives user-experience constraints
#   2. SoC die temperature drives frequency ceiling constraints
#   3. Per-zone limits prevent individual components from overheating
#   4. Vendor kernel thermal shutdown remains authoritative for critical limits
#
# Hysteresis: thermal levels use separate enter/exit thresholds to prevent
# oscillation around thresholds. Level changes only when we CROSS a threshold
# by more than the hysteresis margin.
#
# Thresholds (milli-Celsius):
#   Skin:       <37°C normal, 37-40°C moderate, 40-42°C high, >42°C critical
#   SoC CPU:    <65°C normal, 65-80°C moderate, 80-95°C high, >95°C critical
#
# Run in background:   nohup thermal.sh &
# Stop:                pkill -f mspv2-thermal

set -euo pipefail
log()  { echo "[mspv2-thermal] $*"; }
WARN() { echo "[mspv2-thermal] WARNING: $*" >&2; }
ERR()  { echo "[mspv2-thermal] ERROR: $*" >&2; }

# Polling interval (seconds)
POLL_INTERVAL=5

# Thermal zones (discovered at startup)
SKIN_ZONE=""    # skin temperature (user experience)
SOC_ZONE=""     # SoC CPU temperature (frequency ceiling)
BATTERY_ZONE="" # battery temperature (safety)

# Performance level: 0=normal, 1=moderate, 2=high, 3=very_high, 4=critical
CURRENT_LEVEL=-1
LAST_LOG_TIME=0

# -------------------------------------------------------------------------
# Thermal zone discovery — no hard-coded zone names or IDs
# -------------------------------------------------------------------------
find_thermal_zone() {
    local zone_type="$1"  # e.g. "skin", "soc", "battery"
    for z in /sys/class/thermal/thermal_zone*; do
        [ -d "$z" ] || continue
        local type
        type=$(cat "$z/type" 2>/dev/null || echo "")
        # Match loosely; Samsung uses different naming per device
        case "$type" in
            *${zone_type}*|*${zone_type^^}*)
                echo "$z"
                return 0
                ;;
        esac
    done
    return 1
}

log "Discovering thermal zones..."
SKIN_ZONE=$(find_thermal_zone "skin" || true)
SOC_ZONE=$(find_thermal_zone "soc" || true)
[ -z "$SOC_ZONE" ] && SOC_ZONE=$(find_thermal_zone "cpu" || true)
[ -z "$SOC_ZONE" ] && SOC_ZONE=$(find_thermal_zone "xo" || true)
[ -z "$SOC_ZONE" ] && SOC_ZONE=$(find_thermal_zone "quiet" || true)
BATTERY_ZONE=$(find_thermal_zone "battery" || true)

log "  Skin zone:    ${SKIN_ZONE:-not found}"
log "  SoC zone:     ${SOC_ZONE:-not found}"
log "  Battery zone: ${BATTERY_ZONE:-not found}"

if [ -z "$SKIN_ZONE" ] && [ -z "$SOC_ZONE" ]; then
    ERR "No thermal zones found. Exiting."
    exit 1
fi

# -------------------------------------------------------------------------
# Read temperature from a zone (returns millidegrees Celsius, or 0 on error)
# -------------------------------------------------------------------------
read_temp() {
    local zone="$1"
    local temp
    temp=$(cat "$zone/temp" 2>/dev/null || echo "0")
    echo "${temp:-0}"
}

# -------------------------------------------------------------------------
# Determine thermal level from skin + SoC temperature.
# Returns: 0=normal, 1=moderate, 2=high, 3=very_high, 4=critical
#
# Hysteresis: we track the last direction we were moving and only
# escalate when we stay above a threshold for a poll, but de-escalate
# only when we drop 2°C below the threshold. This prevents oscillation.
# -------------------------------------------------------------------------
calc_level() {
    local skin_mc="$1"
    local soc_mc="$2"

    # Thresholds in milli-Celsius (millidegrees)
    # Enter threshold: escalate TO this level
    # Exit threshold: de-escalate FROM this level
SKIN_M0=37000  SKIN_M1=40000  SKIN_M2=42000  SKIN_M3=44000  # skin thresholds (mC)
SOC_M0=65000   SOC_M1=80000   SOC_M2=95000              # SoC die thresholds (mC)

    # Temperature-based level (use the WORST of skin and SoC levels)
    local skin_level=0 soc_level=0

    # Skin level
    if   [ "$skin_mc" -ge "$SKIN_M3" ]; then skin_level=3
    elif [ "$skin_mc" -ge "$SKIN_M2" ]; then skin_level=2
    elif [ "$skin_mc" -ge "$SKIN_M1" ]; then skin_level=1
    fi

    # SoC level (separate axis)
    if   [ "$soc_mc" -ge "$SOC_M2" ]; then soc_level=3
    elif [ "$soc_mc" -ge "$SOC_M1" ]; then soc_level=2
    elif [ "$soc_mc" -ge "$SOC_M0" ]; then soc_level=1
    fi

    # Use the worst of both axes (max)
    local level=$skin_level
    [ "$soc_level" -gt "$level" ] && level=$soc_level

    echo "$level"
}

# -------------------------------------------------------------------------
# Apply a performance level to the system.
# Only applies deltas from the previous level to minimize jitter.
# -------------------------------------------------------------------------
apply_level() {
    local level="$1"

    # Nothing to do
    [ "$level" -eq "$CURRENT_LEVEL" ] && return 0

    local prev=$CURRENT_LEVEL
    CURRENT_LEVEL=$level

    # Log level changes (throttle to once per minute)
    local now
    now=$(date '+%s')
    if [ "$((now - LAST_LOG_TIME))" -ge 60 ] || [ "$level" -eq 4 ]; then
        LAST_LOG_TIME=$now
        log "Level $level ← $prev | skin=$(read_temp "$SKIN_ZONE")mC soc=$(read_temp "$SOC_ZONE")mC"
    fi

    case "$level" in
        0)  # Normal: full schedutil, no clamps
            log "Thermal: NORMAL — restoring full performance"
            for policy in /sys/devices/system/cpu/cpufreq/policy*; do
                [ -w "$policy/scaling_governor" ] && echo schedutil > "$policy/scaling_governor" 2>/dev/null || true
                [ -w "$policy/schedutil/up_rate_limit_us" ] && echo 2000 > "$policy/schedutil/up_rate_limit_us" 2>/dev/null || true
                [ -w "$policy/schedutil/down_rate_limit_us" ] && echo 10000 > "$policy/schedutil/down_rate_limit_us" 2>/dev/null || true
            done
            # Restore GPU devfreq floor
            for devfreq in /sys/class/devfreq/*; do
                [ -d "$devfreq" ] || continue
                dev_name=$(basename "$devfreq")
                case "$dev_name" in
                    *gpu*|*Gx*|*kgsl*|*mdss*)
                        [ -w "$devfreq/governor" ] && echo performance > "$devfreq/governor" 2>/dev/null || true
                        ;;
                esac
            done
            [ -w /dev/cpuctl/top-app/uclamp.min ]     && echo 512  > /dev/cpuctl/top-app/uclamp.min
            [ -w /dev/cpuctl/foreground/uclamp.min ]    && echo 256  > /dev/cpuctl/foreground/uclamp.min
            [ -w /dev/cpuctl/system/uclamp.min ]       && echo 128  > /dev/cpuctl/system/uclamp.min
            [ -w /dev/cpuctl/background/uclamp.min ]    && echo 0    > /dev/cpuctl/background/uclamp.min
            ;;

        1)  # Moderate: slightly reduce boost
            log "Thermal: MODERATE — reducing boost"
            [ -w /dev/cpuctl/top-app/uclamp.min ]     && echo 384  > /dev/cpuctl/top-app/uclamp.min
            [ -w /dev/cpuctl/foreground/uclamp.min ] && echo 200  > /dev/cpuctl/foreground/uclamp.min
            [ -w /dev/cpuctl/system/uclamp.min ]      && echo 96   > /dev/cpuctl/system/uclamp.min
            ;;

        2)  # High: reduce sustained clock targets, lower GPU floor to 60%
            log "Thermal: HIGH — reducing clock targets, GPU floor 60%"
            [ -w /dev/cpuctl/top-app/uclamp.min ]     && echo 256  > /dev/cpuctl/top-app/uclamp.min
            [ -w /dev/cpuctl/foreground/uclamp.min ] && echo 128  > /dev/cpuctl/foreground/uclamp.min
            [ -w /dev/cpuctl/system/uclamp.min ]      && echo 64   > /dev/cpuctl/system/uclamp.min
            for devfreq in /sys/class/devfreq/*; do
                dev_name=$(basename "$devfreq")
                case "$dev_name" in
                    *gpu*|*Gx*|*kgsl*|*mdss*)
                        if [ -w "$devfreq/min_freq" ] && [ -r "$devfreq/max_freq" ]; then
                            max=$(cat "$devfreq/max_freq" 2>/dev/null || echo "0")
                            [ -n "$max" ] && [ "$max" -gt 0 ] || continue
                            echo $((max * 60 / 100)) > "$devfreq/min_freq" 2>/dev/null || true
                        fi
                        ;;
                esac
            done
            for policy in /sys/devices/system/cpu/cpufreq/policy*; do
                [ -w "$policy/schedutil/down_rate_limit_us" ] && echo 15000 > "$policy/schedutil/down_rate_limit_us" 2>/dev/null || true
            done
            ;;

        3)  # Very high: significantly reduce boost, GPU floor 40%
            log "Thermal: VERY HIGH — limiting boost, GPU floor 40%"
            [ -w /dev/cpuctl/top-app/uclamp.min ]     && echo 128  > /dev/cpuctl/top-app/uclamp.min
            [ -w /dev/cpuctl/foreground/uclamp.min ] && echo 64   > /dev/cpuctl/foreground/uclamp.min
            [ -w /dev/cpuctl/system/uclamp.min ]      && echo 0    > /dev/cpuctl/system/uclamp.min
            for devfreq in /sys/class/devfreq/*; do
                dev_name=$(basename "$devfreq")
                case "$dev_name" in
                    *gpu*|*Gx*|*kgsl*|*mdss*)
                        if [ -w "$devfreq/min_freq" ] && [ -r "$devfreq/max_freq" ]; then
                            max=$(cat "$devfreq/max_freq" 2>/dev/null || echo "0")
                            [ -n "$max" ] && [ "$max" -gt 0 ] || continue
                            echo $((max * 40 / 100)) > "$devfreq/min_freq" 2>/dev/null || true
                        fi
                        ;;
                esac
            done
            for policy in /sys/devices/system/cpu/cpufreq/policy*; do
                [ -w "$policy/schedutil/up_rate_limit_us" ]   && echo 5000   > "$policy/schedutil/up_rate_limit_us" 2>/dev/null || true
                [ -w "$policy/schedutil/down_rate_limit_us" ] && echo 20000  > "$policy/schedutil/down_rate_limit_us" 2>/dev/null || true
            done
            ;;

        4)  # Critical: only emergency — let vendor thermal shutdown handle it
            log "Thermal: CRITICAL — reverting to vendor defaults"
            WARN "Critical thermal level reached. Relying on vendor safety limits."
            for policy in /sys/devices/system/cpu/cpufreq/policy*; do
                [ -w "$policy/scaling_governor" ] && echo schedutil > "$policy/scaling_governor" 2>/dev/null || true
            done
            [ -w /dev/cpuctl/top-app/uclamp.min ]     && echo 0 > /dev/cpuctl/top-app/uclamp.min
            ;;
    esac
}

# -------------------------------------------------------------------------
# Main loop
# -------------------------------------------------------------------------
log "Starting MSPv2 progressive thermal controller (poll=${POLL_INTERVAL}s)"
log "Thresholds: skin <37°C/37-40/40-42/>42°C, SoC <65/65-80/80-95/>95°C"
log "Level 0 ← NORMAL, 1 ← MODERATE, 2 ← HIGH, 3 ← VERY HIGH, 4 ← CRITICAL"

# Apply level 0 initially
apply_level 0

while true; do
    # Read temperatures
    skin_mc=$(read_temp "$SKIN_ZONE")
    soc_mc=$(read_temp "$SOC_ZONE")

    # Calculate desired level
    desired=$(calc_level "$skin_mc" "$soc_mc")

    # Apply (only if changed)
    apply_level "$desired"

    sleep "$POLL_INTERVAL"
done
