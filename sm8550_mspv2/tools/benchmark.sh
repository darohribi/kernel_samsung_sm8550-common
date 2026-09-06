#!/bin/bash
# SM8550 MSPv2 - tools/benchmark.sh
# Quick performance sanity check. NOT a real benchmark.
# Prints current frequencies, governor, and thermal state.

set -euo pipefail
log() { echo "[mspv2-bench] $*"; }

log "Frequencies:"
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    name=$(basename "$policy")
    min=$(cat "$policy/scaling_min_freq" 2>/dev/null || echo "?")
    cur=$(cat "$policy/scaling_cur_freq" 2>/dev/null || echo "?")
    max=$(cat "$policy/scaling_max_freq" 2>/dev/null || echo "?")
    gov=$(cat "$policy/scaling_governor" 2>/dev/null || echo "?")
    echo "  $name: $cur / $max  governor=$gov"
done

log "Thermal zones:"
for z in /sys/class/thermal/thermal_zone*; do
    [ -d "$z" ] || continue
    type=$(cat "$z/type" 2>/dev/null || echo "?")
    temp=$(cat "$z/temp" 2>/dev/null || echo "?")
    mode=$(cat "$z/mode" 2>/dev/null || echo "?")
    echo "  $(basename "$z") type=$type temp=$temp mode=$mode"
done

log "Devfreq:"
for d in /sys/class/devfreq/*; do
    [ -d "$d" ] || continue
    gov=$(cat "$d/governor" 2>/dev/null || echo "?")
    cur=$(cat "$d/cur_freq" 2>/dev/null || echo "?")
    echo "  $(basename "$d") governor=$gov cur=$cur"
done

log "UCLAMP cgroups:"
for c in /dev/cpuctl/*/uclamp.min; do
    [ -r "$c" ] || continue
    echo "  $c = $(cat $c 2>/dev/null)"
done
