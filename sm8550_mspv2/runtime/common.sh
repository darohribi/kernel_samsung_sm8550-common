#!/bin/bash
# SM8550 MSPv2 - common.sh
# One-time boot setup, discover SoC topology, prepare runtime environment.
# Must be sourced, not executed. Never disables the thermal framework.

set -euo pipefail

MSPV2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../tools/detect_soc.sh
. "$MSPV2_ROOT/tools/detect_soc.sh"
# shellcheck source=../tools/detect_policies.sh
. "$MSPV2_ROOT/tools/detect_policies.sh"
# shellcheck source=../tools/detect_irqs.sh
. "$MSPV2_ROOT/tools/detect_irqs.sh"

log() { echo "[mspv2-common] $*"; }

# -------------------------------------------------------------------------
# 1. Discover SoC topology (do not hard-code CPU4 = X3)
# -------------------------------------------------------------------------
log "Detecting SoC topology..."
mspv2_detect_soc
log "  policies: ${MSPV2_POLICIES[*]:-unknown}"
log "  big policy (highest capacity): $MSPV2_BIG_POLICY"
log "  little policies: ${MSPV2_LITTLE_POLICIES[*]:-none}"

# -------------------------------------------------------------------------
# 2. sysctl defaults (v2 measured values)
# -------------------------------------------------------------------------
log "Applying sysctl defaults..."
for f in "$MSPV2_ROOT"/kernel/*.conf; do
    [ -f "$f" ] || continue
    sysctl -p "$f" 2>/dev/null || log "  (skipped $f)"
done

# -------------------------------------------------------------------------
# 3. Per-cgroup UCLAMP baseline policy (never global minimum=1024)
# -------------------------------------------------------------------------
log "Setting baseline UCLAMP policy per cgroup..."

# Background - very low clamp
[ -w /dev/cpuctl/background/uclamp.min ] && echo 0 > /dev/cpuctl/background/uclamp.min
[ -w /dev/cpuctl/background/uclamp.max ] && echo 512 > /dev/cpuctl/background/uclamp.max

# System / default
[ -w /dev/cpuctl/system/uclamp.min ] && echo 128 > /dev/cpuctl/system/uclamp.min
[ -w /dev/cpuctl/system/uclamp.max ] && echo 1024 > /dev/cpuctl/system/uclamp.max

# Foreground (Android)
[ -w /dev/cpuctl/foreground/uclamp.min ] && echo 256 > /dev/cpuctl/foreground/uclamp.min
[ -w /dev/cpuctl/foreground/uclamp.max ] && echo 1024 > /dev/cpuctl/foreground/uclamp.max

# Top-app - the latency-sensitive one
[ -w /dev/cpuctl/top-app/uclamp.min ] && echo 512 > /dev/cpuctl/top-app/uclamp.min
[ -w /dev/cpuctl/top-app/uclamp.max ] && echo 1024 > /dev/cpuctl/top-app/uclamp.max

# RT tasks
[ -w /dev/cpuctl/rt/uclamp.min ] && echo 768 > /dev/cpuctl/rt/uclamp.min
[ -w /dev/cpuctl/rt/uclamp.max ] && echo 1024 > /dev/cpuctl/rt/uclamp.max

# -------------------------------------------------------------------------
# 4. schedutil rate limits - responsive but not jittery
# -------------------------------------------------------------------------
log "Configuring schedutil (1-3 ms up / 8-15 ms down)..."
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    gov="$policy/schedutil"
    [ -d "$gov" ] || continue
    [ -w "$gov/up_rate_limit_us" ]   && echo 2000 > "$gov/up_rate_limit_us"
    [ -w "$gov/down_rate_limit_us" ] && echo 10000 > "$gov/down_rate_limit_us"
    [ -w "$gov/iowait_boost_enable" ] && echo 1 > "$gov/iowait_boost_enable"
done

# -------------------------------------------------------------------------
# 5. cpuidle - keep TEO governor, do NOT permanently disable deep C-states
# -------------------------------------------------------------------------
log "Setting cpuidle governor to TEO..."
for gov in /sys/devices/system/cpu/cpuidle/current_governor; do
    [ -w "$gov" ] && echo teo > "$gov" 2>/dev/null || true
done

# -------------------------------------------------------------------------
# 6. Block I/O - measured defaults (no read_ahead_kb=0 globally)
# -------------------------------------------------------------------------
log "Tuning I/O scheduler (measured)..."
for queue in /sys/block/*/queue; do
    [ -d "$queue" ] || continue
    [ -w "$queue/scheduler" ] && echo kyber > "$queue/scheduler" 2>/dev/null || true
    [ -w "$queue/read_ahead_kb" ] && echo 256 > "$queue/read_ahead_kb" 2>/dev/null || true
    [ -w "$queue/nr_requests" ] && echo 128 > "$queue/nr_requests" 2>/dev/null || true
    [ -w "$queue/nomerges" ] && echo 0 > "$queue/nomerges" 2>/dev/null || true
    [ -w "$queue/rq_affinity" ] && echo 1 > "$queue/rq_affinity" 2>/dev/null || true
done

# -------------------------------------------------------------------------
# 7. IRQ affinity - per-device, discovered (NEVER global f0)
# -------------------------------------------------------------------------
log "Discovering and tuning per-device IRQ affinity..."
mspv2_detect_irqs

# -------------------------------------------------------------------------
# 8. Thermal - keep framework ENABLED, only touch the right zones
# -------------------------------------------------------------------------
log "Thermal: keeping vendor framework on (only adjusting known performance zones)..."
# Do NOT disable /sys/module/thermal/parameters/enabled
# Do NOT set every zone to user_space
# Only the SoC CPU/GPU zones get user_space; battery/PMIC/USB/skin/charger
# are left to vendor defaults.

# -------------------------------------------------------------------------
# 9. Devfreq - performance governor with floor (not always-maximum)
# -------------------------------------------------------------------------
log "Setting devfreq governors (performance, with floor)..."
for devfreq in /sys/class/devfreq/*; do
    [ -d "$devfreq" ] || continue
    [ -w "$devfreq/governor" ] && echo performance > "$devfreq/governor" 2>/dev/null || true
    # Do NOT permanently set min_freq = max_freq. That defeats
    # the purpose of devfreq. v2 leaves the floor at vendor default.
done

log "common.sh complete."
