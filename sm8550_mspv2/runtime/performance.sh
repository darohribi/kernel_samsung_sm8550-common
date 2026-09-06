#!/bin/bash
# SM8550 MSPv2 - performance.sh
# Daily-use profile: responsive but not maximum-burn.
# Run after common.sh, or on demand via a profile selector.

set -euo pipefail
log() { echo "[mspv2-performance] $*"; }

# -------------------------------------------------------------------------
# UCLAMP: bring foreground/top-app to a higher (but not maximum) floor
# -------------------------------------------------------------------------
[ -w /dev/cpuctl/foreground/uclamp.min ] && echo 384 > /dev/cpuctl/foreground/uclamp.min
[ -w /dev/cpuctl/top-app/uclamp.min ]     && echo 640 > /dev/cpuctl/top-app/uclamp.min

# -------------------------------------------------------------------------
# schedutil - balance responsiveness vs efficiency
# -------------------------------------------------------------------------
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    gov="$policy/schedutil"
    [ -d "$gov" ] || continue
    [ -w "$gov/up_rate_limit_us" ]   && echo 2000 > "$gov/up_rate_limit_us"
    [ -w "$gov/down_rate_limit_us" ] && echo 12000 > "$gov/down_rate_limit_us"
done

# -------------------------------------------------------------------------
# IRQ - top-app-style latency-sensitive devices on the big cluster,
# but distributed. NOT global f0.
# -------------------------------------------------------------------------
[ -d /sys/kernel/irq ] || exit 0
for irq_dir in /sys/kernel/irq/*; do
    [ -d "$irq_dir" ] || continue
    affinity="$irq_dir/smp_affinity"
    [ -w "$affinity" ] || continue
    # Skip; the per-device map is set in common.sh via detect_irqs.sh.
done

# -------------------------------------------------------------------------
# I/O: keep kyber at responsive defaults
# -------------------------------------------------------------------------
for queue in /sys/block/*/queue; do
    [ -d "$queue" ] || continue
    [ -w "$queue/read_ahead_kb" ] && echo 256 > "$queue/read_ahead_kb" 2>/dev/null || true
done

log "performance profile active."
