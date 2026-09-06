#!/bin/bash
# SM8550 MSPv2 - tools/detect_policies.sh
# shellcheck disable=SC2034  # exported globals (MSPV2_POLICY_*) used across sourced scripts
# Properly discover cpufreq policies with topology info.
#
# Discovers:
#   - Policy number (e.g., 0, 4, 7)
#   - CPUs in each policy (via related_cpus)
#   - Max/min frequencies
#   - Policy capacity class (LITTLE / prime / big)
#
# This is the canonical source for topology info. detect_soc.sh imports
# from here and adds big-cluster heuristics on top.

set -euo pipefail

# shellcheck source=detect_soc.sh
. "$(dirname "${BASH_SOURCE[0]}")/detect_soc.sh"

# Export discovered policies. Call mspv2_detect_soc() first.
# After calling, these globals are available:
#   MSPV2_POLICIES[@]     - list of all policy numbers
#   MSPV2_LITTLE_POLICIES  - list of LITTLE cluster policies
#   MSPV2_BIG_POLICY      - highest-capacity policy number
#   MSPV2_POLICY_CPUS     - bash associative array: policy → cpu list

# Also expose per-policy frequency info via this associative array.
declare -gA MSPV2_POLICY_FREQ_MAX
declare -gA MSPV2_POLICY_FREQ_MIN

mspv2_enumerate_policies() {
    # Reset all state
    MSPV2_POLICIES=()
    declare -gA MSPV2_POLICY_CPUS
    MSPV2_POLICY_CPUS=()
    MSPV2_POLICY_FREQ_MAX=()
    MSPV2_POLICY_FREQ_MIN=()
    MSPV2_LITTLE_POLICIES=()
    MSPV2_BIG_POLICY=""

    local max_freq_seen=0

    for policy_dir in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$policy_dir" ] || continue

        local policy
        policy=$(basename "$policy_dir")

        # CPU list for this policy
        local cpus freq_max freq_min
        cpus=$(cat "$policy_dir/related_cpus" 2>/dev/null || echo "")
        [ -n "$cpus" ] || continue

        freq_max=$(cat "$policy_dir/cpuinfo_max_freq" 2>/dev/null || echo "0")
        freq_min=$(cat "$policy_dir/cpuinfo_min_freq" 2>/dev/null || echo "0")

        MSPV2_POLICIES+=("$policy")
        MSPV2_POLICY_CPUS["$policy"]="$cpus"
        MSPV2_POLICY_FREQ_MAX["$policy"]="${freq_max:-0}"
        MSPV2_POLICY_FREQ_MIN["$policy"]="${freq_min:-0}"

        # Identify LITTLE cluster: lowest frequency == LITTLE
        if [ "${freq_max:-0}" -lt "$max_freq_seen" ] || [ "$max_freq_seen" -eq 0 ]; then
            max_freq_seen="${freq_max:-0}"
            MSPV2_LITTLE_POLICIES+=("$policy")
        fi

        # Track highest-capacity policy
        if [ "${freq_max:-0}" -gt "${MSPV2_POLICY_FREQ_MAX[$MSPV2_BIG_POLICY]:-0}" ]; then
            MSPV2_BIG_POLICY="$policy"
        fi
    done
}

# Auto-run on source
mspv2_enumerate_policies
