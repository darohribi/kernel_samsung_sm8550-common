#!/bin/bash
# SM8550 MSPv2 - tools/detect_soc.sh
# Discover the SoC topology. Do NOT hard-code "CPU4 = X3".

set -euo pipefail

# These globals are filled in by mspv2_detect_soc.
# shellcheck disable=SC2034
MSPV2_POLICIES=()
MSPV2_BIG_POLICY=""
# shellcheck disable=SC2034
MSPV2_LITTLE_POLICIES=()

# mspv2_detect_soc - read cpufreq policies and identify clusters.
mspv2_detect_soc() {
    MSPV2_POLICIES=()
    MSPV2_LITTLE_POLICIES=()

    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$policy" ] || continue
        name=$(basename "$policy")
        MSPV2_POLICIES+=("$name")

        # read capacity and max freq
        related=$(cat "$policy/related_cpus" 2>/dev/null | tr ' ' '\n' | sort -n | head -1 || echo "")
        max_freq=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo 0)
        if [ -n "$related" ] && [ "$max_freq" -gt 0 ]; then
            echo "$name max=$max_freq first_cpu=$related"
        fi
    done

    # Big cluster = highest cpuinfo_max_freq
    if [ ${#MSPV2_POLICIES[@]} -gt 0 ]; then
        MSPV2_BIG_POLICY=$(for p in "${MSPV2_POLICIES[@]}"; do
            freq=$(cat "/sys/devices/system/cpu/cpufreq/$p/cpuinfo_max_freq" 2>/dev/null || echo 0)
            echo "$freq $p"
        done | sort -rn | head -1 | awk '{print $2}')
    fi

    # Little clusters = everything else
    for p in "${MSPV2_POLICIES[@]}"; do
        if [ "$p" != "$MSPV2_BIG_POLICY" ]; then
            MSPV2_LITTLE_POLICIES+=("$p")
        fi
    done
}
