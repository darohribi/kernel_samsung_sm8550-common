#!/bin/bash
# SM8550 MSPv2 - restore.sh
# Revert every temporary change made by gaming.sh / benchmark.sh.
# Uses /tmp/mspv2_state.sh (shell-parseable format) for exact restoration.
#
# State file format (shell variables, easy to source):
#   UCLAMP_PATH="/dev/cpuctl/top-app/uclamp.min"
#   UCLAMP_VAL="768"
#   ...

set -euo pipefail
log() { echo "[mspv2-restore] $*"; }

STATE_FILE="${MSPV2_STATE_FILE:-/tmp/mspv2_state.sh}"

# -------------------------------------------------------------------------
# Restore from captured state file
# -------------------------------------------------------------------------
restore_from_file() {
    if [ ! -f "$STATE_FILE" ]; then
        log "No state file at $STATE_FILE — applying defaults"
        restore_defaults
        return
    fi

    log "Restoring from $STATE_FILE"

    # Source the state file (it's just shell variable assignments)
    # shellcheck disable=SC1090
    . "$STATE_FILE"

    # Restore UCLAMP paths
    local idx=0
    while [ -n "${UCLAMP_PATH[$idx]:-}" ]; do
        local path="${UCLAMP_PATH[$idx]}"
        local val="${UCLAMP_VAL[$idx]:-}"
        [ -n "$path" ] && [ -n "$val" ] && [ -w "$path" ] && echo "$val" > "$path" 2>/dev/null || true
        idx=$((idx + 1))
    done

    # Restore CPU freq paths
    idx=0
    while [ -n "${CPUFQ_PATH[$idx]:-}" ]; do
        local path="${CPUFQ_PATH[$idx]}"
        local val="${CPUFQ_VAL[$idx]:-}"
        [ -n "$path" ] && [ -n "$val" ] && [ -w "$path" ] && echo "$val" > "$path" 2>/dev/null || true
        idx=$((idx + 1))
    done

    # Restore devfreq paths
    idx=0
    while [ -n "${DEVFQ_PATH[$idx]:-}" ]; do
        local path="${DEVFQ_PATH[$idx]}"
        local val="${DEVFQ_VAL[$idx]:-}"
        [ -n "$path" ] && [ -n "$val" ] && [ -w "$path" ] && echo "$val" > "$path" 2>/dev/null || true
        idx=$((idx + 1))
    done

    # Restore cpuidle paths
    idx=0
    while [ -n "${IDLE_PATH[$idx]:-}" ]; do
        local path="${IDLE_PATH[$idx]}"
        local val="${IDLE_VAL[$idx]:-}"
        [ -n "$path" ] && [ -n "$val" ] && [ -w "$path" ] && echo "$val" > "$path" 2>/dev/null || true
        idx=$((idx + 1))
    done

    log "State restoration complete."
}

# -------------------------------------------------------------------------
# Fallback: hardcoded defaults (no state file)
# -------------------------------------------------------------------------
restore_defaults() {
    log "Applying hardcoded defaults..."

    # UCLAMP
    for pair in \
        "/dev/cpuctl/system/uclamp.min:128" \
        "/dev/cpuctl/system/uclamp.max:1024" \
        "/dev/cpuctl/foreground/uclamp.min:256" \
        "/dev/cpuctl/foreground/uclamp.max:1024" \
        "/dev/cpuctl/background/uclamp.min:0" \
        "/dev/cpuctl/background/uclamp.max:512" \
        "/dev/cpuctl/top-app/uclamp.min:512" \
        "/dev/cpuctl/top-app/uclamp.max:1024" \
        "/dev/cpuctl/rt/uclamp.min:768" \
        "/dev/cpuctl/rt/uclamp.max:1024"; do
        local path="${pair%%:*}"
        local val="${pair##*:}"
        [ -w "$path" ] && echo "$val" > "$path" 2>/dev/null || true
    done

    # CPUfreq
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -w "$policy/scaling_governor" ] && echo schedutil > "$policy/scaling_governor" 2>/dev/null || true
        [ -w "$policy/schedutil/up_rate_limit_us" ]   && echo 2000   > "$policy/schedutil/up_rate_limit_us" 2>/dev/null || true
        [ -w "$policy/schedutil/down_rate_limit_us" ] && echo 12000  > "$policy/schedutil/down_rate_limit_us" 2>/dev/null || true
    done

    # cpuidle
    for state in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
        [ -w "$state/disable" ] && echo 0 > "$state/disable" 2>/dev/null || true
    done

    # Block I/O
    for queue in /sys/block/*/queue; do
        [ -w "$queue/scheduler" ]      && echo kyber > "$queue/scheduler" 2>/dev/null || true
        [ -w "$queue/read_ahead_kb" ] && echo 256   > "$queue/read_ahead_kb" 2>/dev/null || true
        [ -w "$queue/nr_requests" ]    && echo 128   > "$queue/nr_requests" 2>/dev/null || true
        [ -w "$queue/nomerges" ]      && echo 0     > "$queue/nomerges" 2>/dev/null || true
    done

    log "Defaults applied."
}

# Main
if [ -f "$STATE_FILE" ]; then
    restore_from_file
    rm -f "$STATE_FILE"
else
    restore_defaults
fi

log "Done."
