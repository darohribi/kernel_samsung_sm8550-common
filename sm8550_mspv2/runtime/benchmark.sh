#!/bin/bash
# SM8550 MSPv2 - benchmark.sh
# Maximum sustained for short benchmarks only.
# Heaviest profile. Caller is responsible for reverting with restore.sh.
#
# WARNING: This locks clocks to maximum, disables most idle states,
# and significantly reduces thermal efficiency. Not for daily use.
# A true "sustained" benchmark mode should measure AFTER thermal
# steady-state, not lock everything to maximum.

set -euo pipefail
log() { echo "[mspv2-benchmark] $*"; }
WARN() { echo "[mspv2-benchmark] WARNING: $*" >&2; }

# Capture current state for restore
# shellcheck source=../tools/capture_state.sh
. "$(dirname "${BASH_SOURCE[0]}")/../tools/capture_state.sh"

WARN "Benchmark mode: maximum clocks, thermal headroom reduced."
WARN "Do NOT use for daily operation. Revert immediately after benchmarks."

# -------------------------------------------------------------------------
# UCLAMP - everything clamped high
# -------------------------------------------------------------------------
[ -w /dev/cpuctl/foreground/uclamp.min ] && echo 768 > /dev/cpuctl/foreground/uclamp.min
[ -w /dev/cpuctl/top-app/uclamp.min ]     && echo 1024 > /dev/cpuctl/top-app/uclamp.min
[ -w /dev/cpuctl/background/uclamp.min ]  && echo 256 > /dev/cpuctl/background/uclamp.min

# -------------------------------------------------------------------------
# schedutil - maximum ramp speed
# -------------------------------------------------------------------------
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    gov="$policy/schedutil"
    [ -d "$gov" ] || continue
    [ -w "$gov/up_rate_limit_us" ]   && echo 500 > "$gov/up_rate_limit_us"
    [ -w "$gov/down_rate_limit_us" ] && echo 20000 > "$gov/down_rate_limit_us"
done

# -------------------------------------------------------------------------
# CPU frequency - lock to max (uses state capture for restore)
# -------------------------------------------------------------------------
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -w "$policy/scaling_governor" ] && echo performance > "$policy/scaling_governor" 2>/dev/null || true
    [ -w "$policy/scaling_min_freq" ] && cat "$policy/cpuinfo_max_freq" > "$policy/scaling_min_freq" 2>/dev/null || true
    [ -w "$policy/scaling_max_freq" ] && cat "$policy/cpuinfo_max_freq" > "$policy/scaling_max_freq" 2>/dev/null || true
done

# -------------------------------------------------------------------------
# GPU devfreq - performance gov + 80% floor (GPU only)
# -------------------------------------------------------------------------
for devfreq in /sys/class/devfreq/*; do
    [ -d "$devfreq" ] || continue
    dev_name=$(basename "$devfreq")
    case "$dev_name" in
        *gpu*|*Gx*|*mx*|*kgsl*|*mdss*)
            [ -w "$devfreq/governor" ] && echo performance > "$devfreq/governor" 2>/dev/null || true
            if [ -w "$devfreq/min_freq" ] && [ -r "$devfreq/max_freq" ]; then
                max=$(cat "$devfreq/max_freq" 2>/dev/null || echo "")
                if [ -n "$max" ] && [ "$max" -gt 0 ]; then
                    floor=$((max * 80 / 100))
                    echo "$floor" > "$devfreq/min_freq" 2>/dev/null || true
                fi
            fi
            ;;
    esac
done

# -------------------------------------------------------------------------
# cpuidle - disable all non-C0 states (uses state capture for restore)
# -------------------------------------------------------------------------
for state in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
    [ -w "$state/disable" ] || continue
    desc=$(cat "$state/desc" 2>/dev/null || echo "")
    case "$desc" in
        C0*|c0*) ;;  # leave C0 enabled
        *)  echo 1 > "$state/disable" 2>/dev/null || true ;;
    esac
done

log "benchmark profile active. Revert with restore.sh."
