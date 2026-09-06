#!/bin/bash
# SM8550 MSPv2 - tools/detect_policies.sh
# Discover cpufreq policies. Wrapper kept for compatibility with v1 callers.

set -euo pipefail

MSPV2_CPUS=()

mspv2_detect_policies() {
    MSPV2_CPUS=()
    for cpu in /sys/devices/system/cpu/cpu*; do
        [ -d "$cpu" ] || continue
        [ -d "$cpu/cpufreq" ] || continue
        name=$(basename "$cpu")
        MSPV2_CPUS+=("$name")
    done
}
