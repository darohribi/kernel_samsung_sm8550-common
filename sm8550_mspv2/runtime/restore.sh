#!/bin/bash
# SM8550 MSPv2 - restore.sh
# Revert every temporary change made by gaming.sh / benchmark.sh.
# Brings the device back to the performance.sh baseline.

set -euo pipefail
log() { echo "[mspv2-restore] $*"; }

# -------------------------------------------------------------------------
# UCLAMP - back to common.sh baseline
# -------------------------------------------------------------------------
[ -w /dev/cpuctl/system/uclamp.min ]    && echo 128 > /dev/cpuctl/system/uclamp.min
[ -w /dev/cpuctl/system/uclamp.max ]    && echo 1024 > /dev/cpuctl/system/uclamp.max
[ -w /dev/cpuctl/foreground/uclamp.min ] && echo 256 > /dev/cpuctl/foreground/uclamp.min
[ -w /dev/cpuctl/foreground/uclamp.max ] && echo 1024 > /dev/cpuctl/foreground/uclamp.max
[ -w /dev/cpuctl/background/uclamp.min ]  && echo 0 > /dev/cpuctl/background/uclamp.min
[ -w /dev/cpuctl/background/uclamp.max ]  && echo 512 > /dev/cpuctl/background/uclamp.max
[ -w /dev/cpuctl/top-app/uclamp.min ]     && echo 512 > /dev/cpuctl/top-app/uclamp.min
[ -w /dev/cpuctl/top-app/uclamp.max ]     && echo 1024 > /dev/cpuctl/top-app/uclamp.max
[ -w /dev/cpuctl/rt/uclamp.min ]          && echo 768 > /dev/cpuctl/rt/uclamp.min
[ -w /dev/cpuctl/rt/uclamp.max ]          && echo 1024 > /dev/cpuctl/rt/uclamp.max

# -------------------------------------------------------------------------
# schedutil - back to performance profile rates
# -------------------------------------------------------------------------
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    gov="$policy/schedutil"
    [ -d "$gov" ] || continue
    [ -w "$gov/up_rate_limit_us" ]   && echo 2000 > "$gov/up_rate_limit_us" 2>/dev/null || true
    [ -w "$gov/down_rate_limit_us" ] && echo 12000 > "$gov/down_rate_limit_us" 2>/dev/null || true
    [ -w "$policy/scaling_governor" ] && echo schedutil > "$policy/scaling_governor" 2>/dev/null || true
done

# -------------------------------------------------------------------------
# cpuidle - re-enable all states
# -------------------------------------------------------------------------
for state in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
    [ -w "$state/disable" ] || continue
    echo 0 > "$state/disable" 2>/dev/null || true
done

# -------------------------------------------------------------------------
# I/O - back to performance defaults
# -------------------------------------------------------------------------
for queue in /sys/block/*/queue; do
    [ -d "$queue" ] || continue
    [ -w "$queue/read_ahead_kb" ] && echo 256 > "$queue/read_ahead_kb" 2>/dev/null || true
    [ -w "$queue/nr_requests" ] && echo 128 > "$queue/nr_requests" 2>/dev/null || true
    [ -w "$queue/nomerges" ] && echo 0 > "$queue/nomerges" 2>/dev/null || true
done

log "Restored to performance baseline."
