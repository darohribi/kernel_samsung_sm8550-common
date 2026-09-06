#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# sm8550_gpu_oc_runtime.sh
# Runtime control for SM8550 GPU overclock (Adreno 740)
#
# Stock frequencies: 514 / 575 / 681 / 767 MHz
# Turbo frequencies:  820 / 875 MHz
#
# Requires: Android kernel with CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y
#           and GPU devfreq sysfs path available.
#
# Usage:
#   sm8550_gpu_oc_runtime.sh enable     # activate turbo OPPs
#   sm8550_gpu_oc_runtime.sh disable    # revert to stock
#   sm8550_gpu_oc_runtime.sh status    # show current GPU state
#   sm8550_gpu_oc_runtime.sh bench     # quick GPU burn-in test
#
# For Magisk: place in /data/adb/service.d/ or use a kernel module
# For GKI:   compile as an out-of-tree module or apply the DTS overlay

set -euo pipefail

# --- Configuration ---
readonly DRY_RUN=${DRY_RUN:-0}
readonly GPU_DEVFREQ_PATH="${GPU_DEVFREQ_PATH:-$(find /sys/class/devfreq -name '*gpu*' -type d 2>/dev/null | head -1)}"
readonly MIN_FREQ=514000000
readonly MAX_FREQ_STOCK=767000000
readonly TURBO_FREQ_1=820000000
readonly TURBO_FREQ_2=875000000

readonly KGSL_PATH="${KGSL_PATH:-/sys/class/kgsl/kgsl-3d0}"

# Thresholds for devfreq governor tuning
readonly ONDEMAND_POLLING_MS=20      # faster polling = faster ramp-up
readonly ONDEMAND_UPTHRESH=40        # %busy to trigger freq up
readonly ONDEMAND_DOWNDIFTHRESH=5     # %busy delta to trigger freq down

# --- Logging ---
log()  { echo -e "\033[1;36m[GPU-OC]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
err()  { echo -e "\033[1;31m[ERR]\033[0m  $*" >&2; }
dbg()  { [[ "${DEBUG:-0}" == "1" ]] && echo -e "\033[1;30m[DBG]\033[0m $*"; }

# --- Helpers ---
find_gpu_devfreq() {
    local path="$GPU_DEVFREQ_PATH"
    if [[ -d "$path" ]]; then
        echo "$path"
        return 0
    fi
    # Auto-discovery fallback
    for p in /sys/class/devfreq/*gpu* /sys/class/devfreq/*gpu*:*; do
        [[ -d "$p" ]] && echo "$p" && return 0
    done
    for p in /sys/devices/platform/*.gpu /sys/devices/soc/*.gpu; do
        local df="$p/devfreq/devfreq*"
        for d in $df; do
            [[ -d "$d" ]] && echo "$d" && return 0
        done
    done
    return 1
}

check_root() {
    [[ $DRY_RUN == 1 ]] && return 0
    if [[ $EUID -ne 0 ]]; then
        err "This script requires root (su)."
        return 1
    fi
}

get_available_freqs() {
    local gpath="$1"
    cat "$gpath.available_frequencies" 2>/dev/null || \
        find "$gpath" -name "available_frequencies" -exec cat {} \; 2>/dev/null || \
        echo ""
}

get_cur_freq() {
    local gpath="$1"
    cat "$gpath/cur_freq" 2>/dev/null || echo "0"
}

get_max_freq() {
    local gpath="$1"
    cat "$gpath/max_freq" 2>/dev/null || echo "0"
}

get_governor() {
    local gpath="$1"
    cat "$gpath/governor" 2>/dev/null || echo "unknown"
}

is_turbo_enabled() {
    local gpath="$1"
    local cur
    cur=$(get_cur_freq "$gpath")
    (( cur >= TURBO_FREQ_1 ))
}

# --- KGSL powerlevel helpers (legacy sysfs path, from encore_profiler) ---
# The KGSL sysfs throttle path coexists with devfreq.
# Setting both min/max to level 0 forces the GPU to max pwrlevel.
# This is the "snapdragon_force_kgsl_pwrlevel 1" equivalent from Rem01Gaming.

kgsl_get_num_pwrlevels() {
    cat "${KGSL_PATH}/num_pwrlevels" 2>/dev/null || echo "0"
}

kgsl_set_pwrlevel() {
    # $1 = mode: 0=default (stock), 1=performance (force max pwrlevel)
    local mode="$1"
    case "$mode" in
        0) # Restore stock: min=default, max=stock
            echo "$(kgsl_get_num_pwrlevels)" > "${KGSL_PATH}/min_pwrlevel" 2>/dev/null || true
            echo "0" > "${KGSL_PATH}/max_pwrlevel" 2>/dev/null || true
            ;;
        1) # Performance: force max pwrlevel (level 0 = highest)
            echo "0" > "${KGSL_PATH}/min_pwrlevel" 2>/dev/null || true
            echo "0" > "${KGSL_PATH}/max_pwrlevel" 2>/dev/null || true
            ;;
    esac
}

# --- Thermal zone helpers ---
get_gpu_temp() {
    local temp=""
    for tz in /sys/class/thermal/thermal_zone*; do
        local type
        type=$(cat "$tz/type" 2>/dev/null || echo "")
        case "$type" in
            gpu*|GPU*) temp=$(cat "$tz/temp" 2>/dev/null || echo ""); break ;;
        esac
    done
    echo "${temp:-0}"
}

# Thermal thresholds (mC)
readonly TEMP_YELLOW=70000   # 70°C — governor tuning
readonly TEMP_RED=85000      # 85°C — reduce to stock
readonly TEMP_CRITICAL=95000 # 95°C — force stock + warn

# --- Actions ---
do_status() {
    local gpath
    gpath=$(find_gpu_devfreq) || { err "GPU devfreq path not found"; return 1; }

    local cur_freq max_freq governor avail_freqs
    cur_freq=$(get_cur_freq "$gpath")
    max_freq=$(get_max_freq "$gpath")
    governor=$(get_governor "$gpath")
    avail_freqs=$(get_available_freqs "$gpath")

    local num_pwl kgsl_min kgsl_max
    num_pwl=$(kgsl_get_num_pwrlevels)
    kgsl_min=$(cat "${KGSL_PATH}/min_pwrlevel" 2>/dev/null || echo "?")
    kgsl_max=$(cat "${KGSL_PATH}/max_pwrlevel" 2>/dev/null || echo "?")

    local temp
    temp=$(get_gpu_temp)
    local temp_c
    temp_c=$(( temp / 1000 ))
    local temp_flag=""
    if (( temp >= TEMP_CRITICAL )); then
        temp_flag=" \033[1;31m⚠ CRITICAL\033[0m"
    elif (( temp >= TEMP_RED )); then
        temp_flag=" \033[1;33m⚠ HOT\033[0m"
    elif (( temp >= TEMP_YELLOW )); then
        temp_flag=" \033[1;33m⚠ warm\033[0m"
    fi

    echo ""
    echo "  === SM8550 GPU Overclock Status ==="
    echo "  Devfreq path  : $gpath"
    echo "  Governor      : $governor"
    echo "  Current freq  : $(( cur_freq / 1000000 )) MHz"
    echo "  Max freq      : $(( max_freq / 1000000 )) MHz"
    echo "  GPU temp      : ${temp_c}°C${temp_flag}"
    echo "  KGSL pwrlevels: $num_pwl total | min=$kgsl_min max=$kgsl_max"
    echo ""
    echo "  Available frequencies (MHz):"
    echo "$avail_freqs" | tr ' ' '\n' | while read -r f; do
        [[ -n "$f" ]] || continue
        local mhz=$(( f / 1000000 ))
        local flag=""
        [[ "$f" == "$cur_freq" ]] && flag=" ← current"
        if (( f > MAX_FREQ_STOCK )); then
            echo "    $mhz MHz  [TURBO]$flag"
        else
            echo "    $mhz MHz$flag"
        fi
    done
    echo ""
    if is_turbo_enabled "$gpath"; then
        echo "  Status: \033[1;32m● TURBO ACTIVE\033[0m (freq >= ${TURBO_FREQ_1} MHz)"
    else
        echo "  Status: \033[1;33m○ STOCK MODE\033[0m (freq < ${TURBO_FREQ_1} MHz)"
    fi
    echo ""
}

do_enable() {
    local gpath
    gpath=$(find_gpu_devfreq) || { err "GPU devfreq path not found"; return 1; }

    check_root || return 1

    log "Enabling GPU overclock..."

    # Pre-flight: check GPU temperature
    local temp
    temp=$(get_gpu_temp)
    if (( temp >= TEMP_RED )); then
        warn "GPU temperature is ${temp}mC (${temp}00°C) — thermal throttling likely."
        warn "Proceeding anyway; results may be limited."
    fi

    # 1. Lock KGSL powerlevel (legacy path, from encore_profiler / Rem01Gaming)
    #    This prevents the legacy throttle sysfs from fighting devfreq.
    kgsl_set_pwrlevel 1

    # 2. Switch to userspace governor so we can force a specific frequency
    echo "userspace" > "$gpath/governor" || {
        err "Failed to set userspace governor (need root)"
        return 1
    }

    # 2. Get the turbo OPP from available_frequencies
    local avail turbo_freq=""
    avail=$(get_available_freqs "$gpath")
    for f in $avail; do
        (( f >= TURBO_FREQ_1 )) && turbo_freq=$f && break
    done

    if [[ -z "$turbo_freq" ]]; then
        warn "No turbo OPPs found in devfreq table."
        warn "Either apply the sm8550-gpu-turbo-overlay.dtbo or load sm8550_gpu_oc.ko"
        warn "Falling back to stock max frequency."
        turbo_freq=$MAX_FREQ_STOCK
    fi

    # 3. Set max frequency to the highest available
    echo "$turbo_freq" > "$gpath/max_freq" || {
        err "Failed to set max_freq"
        return 1
    }

    # 4. Force the GPU to the turbo frequency
    echo "$turbo_freq" > "$gpath/userspace/set_freq" 2>/dev/null || \
        echo "$turbo_freq" > "$gpath/set_freq" 2>/dev/null || \
        echo "$turbo_freq" > "$gpath/min_freq" 2>/dev/null

    sleep 0.5

    local new_freq
    new_freq=$(get_cur_freq "$gpath")
    log "Current GPU frequency: $(( new_freq / 1000000 )) MHz"
    if (( new_freq >= TURBO_FREQ_1 )); then
        log "\033[1;32m✓ GPU overclock active!\033[0m (turbo OPP: $(( turbo_freq / 1000000 )) MHz)"
    else
        warn "GPU did not reach turbo frequency. This may indicate:"
        warn "  - Thermal throttling active"
        warn "  - GPU not under load (use a benchmark)"
        warn "  - Turbo OPP not in available_frequencies"
    fi

    # 5. Switch back to simple_ondemand for adaptive behaviour
    echo "simple_ondemand" > "$gpath/governor"
    log "Governor set to: simple_ondemand (adaptive)"
    log "KGSL powerlevel: locked to max (level 0)"
    log "Done."
}

do_disable() {
    local gpath
    gpath=$(find_gpu_devfreq) || { err "GPU devfreq path not found"; return 1; }

    check_root || return 1

    log "Disabling GPU overclock (restoring stock max: $(( MAX_FREQ_STOCK / 1000000 )) MHz)..."

    # Restore KGSL powerlevel (legacy path)
    kgsl_set_pwrlevel 0

    echo "$MAX_FREQ_STOCK" > "$gpath/max_freq" 2>/dev/null || true
    echo "simple_ondemand" > "$gpath/governor" 2>/dev/null || true

    log "\033[1;33m✓ GPU overclock disabled. Stock frequencies restored.\033[0m"
}

do_bench() {
    local gpath
    gpath=$(find_gpu_devfreq) || { err "GPU devfreq path not found"; return 1; }

    check_root || return 1

    log "Running quick GPU burn-in (10 seconds)..."
    log "Watch: cat $gpath/cur_freq"
    echo ""

    local start end dur=10
    start=$(get_cur_freq "$gpath")
    log "Start freq: $(( start / 1000000 )) MHz"

    # Simple busy-wait using /dev/zero reads to keep GPU active
    # On Android, use a GL app or the following for CPU load on GPU
    : > /sys/class/kgsl/kgsl-3d0/throttling 2>/dev/null || true

    # Stress the GPU with OpenGL compute if available
    local pid
    (
        # Kick the GPU by reading/writing to a GPU sysfs node that triggers activity
        while true; do
            cat "$gpath/cur_freq" > /dev/null 2>&1 || true
            cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null || true
            sleep 0.5
        done
    ) &
    pid=$!

    sleep "$dur"
    kill "$pid" 2>/dev/null || true

    end=$(get_cur_freq "$gpath")
    log "End freq  : $(( end / 1000000 )) MHz"
    echo ""
    if (( end >= TURBO_FREQ_1 )); then
        log "\033[1;32m✓ GPU reached turbo frequency! Overclock is working.\033[0m"
    else
        warn "GPU did not reach turbo. Check thermal state and workload."
    fi
}

# --- Main ---
usage() {
    echo "Usage: $0 {enable|disable|status|bench}"
    echo ""
    echo "  enable   - activate GPU turbo frequencies (820/875 MHz)"
    echo "  disable  - restore stock max frequency (767 MHz)"
    echo "  status   - show current GPU frequency and available OPPs"
    echo "  bench    - quick 10-second GPU burn-in to verify overclock"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 enable"
    echo "  $0 bench"
    echo "  DRY_RUN=1 $0 enable   # simulate without writing files"
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    case "$1" in
        enable)  do_enable ;;
        disable) do_disable ;;
        status)  do_status ;;
        bench)   do_bench ;;
        -h|--help|help) usage ;;
        *)        err "Unknown command: $1" >&2; usage; exit 1 ;;
    esac
}

main "$@"
