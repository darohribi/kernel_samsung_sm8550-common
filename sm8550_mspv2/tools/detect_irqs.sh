#!/bin/bash
# SM8550 MSPv2 - tools/detect_irqs.sh
# Discover per-device IRQ numbers from /proc/interrupts and assign
# per-device affinity. NO global f0 rule.
#
# Delimiter: → (never appears in device names or IRQ masks)
# Format per entry: "device-pattern→affinity-mask"
#
# Affinity masks (hex):
#   01 = CPU0 only
#   10 = CPU1 only
#   30 = CPU0 + CPU1
#   0f = CPU0-3 (LITTLE cluster)
#   f0 = CPU4-7 (big cluster)
#   ff = all CPUs
#
# Strategy:
#   touch / input       → LITTLE cluster (low latency, power efficient)
#   display / GPU       → big cluster (compute intensive)
#   storage (UFS/SD)    → LITTLE cluster (not latency critical)
#   network (Wi-Fi)    → mixed (variable workload)
#   system IRQs         → CPU0 (lowest priority, avoids disturbing cores)
#
# Do NOT hard-code CPU numbers. These masks route IRQs to clusters
# based on workload characteristics, not specific CPU numbers.

# shellcheck disable=SC2034  # MSPV2_POLICY_COUNT exported for cross-script use
set -euo pipefail

# Per-device affinity map.
# Format: "device-pattern→affinity-mask"
# Multiple patterns can be separated by | (bash pattern matching).
MSPV2_IRQ_MAP=(
    # Input: low latency, keep on LITTLE cluster
    "touch→0f"
    "touchscreen→0f"
    "sec_touch→0f"
    "fingerprint→0f"
    "keypad→0f"

    # Display / GPU: compute-intensive, route to big cluster
    "mdp→f0"
    "dpu→f0"
    "dsi→f0"
    "sde→f0"
    "gpu→f0"
    "kgsl→f0"
    "mdss→f0"

    # Storage: not latency-critical, LITTLE cluster
    "ufshcd→0f"
    "sdhci→0f"
    "mmc→0f"
    "nvme→0f"

    # Network: variable workload, use both big cores
    "wifi→30"
    "wlan→30"
    "bt→30"
    "hci→30"

    # USB: moderate latency, LITTLE cluster
    "usb→0f"
    "xhci→0f"
    "dwc3→0f"

    # System IRQs (SMP, RPC, etc.): keep off app cores
    "smp2p→01"
    "glink→01"
    "scm→01"
    "gic→01"
    "arch_timer→01"
)

# Discover all available cpufreq policies and their CPU mappings.
# Exports: MSPV2_POLICY_MAP ( associative array: policy→cpus )
#          MSPV2_POLICY_COUNT
mspv2_detect_policies() {
    declare -gA MSPV2_POLICY_MAP
    MSPV2_POLICY_MAP=()
    local count=0

    for policy_dir in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$policy_dir" ] || continue
        local cpus
        cpus=$(cat "$policy_dir/related_cpus" 2>/dev/null || echo "")
        [ -n "$cpus" ] || continue
        local policy
        policy=$(basename "$policy_dir")
        MSPV2_POLICY_MAP["$policy"]="$cpus"
        count=$((count + 1))
    done
    declare -g MSPV2_POLICY_COUNT=$count
}

mspv2_detect_irqs() {
    [ -r /proc/interrupts ] || return 0

    # Detect policies once
    mspv2_detect_policies

    # Discover IRQ→device mappings from /proc/interrupts
    local irq name
    local entry pattern mask

    # Read /proc/interrupts (skip header line)
    while IFS= read -r line; do
        # IRQ number is the first field (drop the trailing colon)
        irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
        [ -z "$irq" ] && continue

        # Device name is the last non-numeric, non-CPU-list field
        name=$(echo "$line" | awk '{
            for (i = 1; i <= NF; i++) {
                # Skip the IRQ number and CPU count fields
                if ($i ~ /^[0-9]+$/ && i <= 2) continue
                # Skip the CPU list (comma/space separated numbers)
                if ($i ~ /^[0-9,\s]+$/ && i <= 4) continue
                last = $i
            }
            print last
        }' 2>/dev/null)
        [ -z "$name" ] && continue

        # Match against our affinity map
        for entry in "${MSPV2_IRQ_MAP[@]}"; do
            # Split on → delimiter
            pattern="${entry%%→*}"
            mask="${entry##*→}"

            # Skip entries with malformed delimiters
            [ -z "$pattern" ] || [ -z "$mask" ] && continue
            [ "$pattern" = "$entry" ] && continue  # no delimiter found

            # Check if device name contains the pattern (bash glob match)
            if [[ "$name" == *"$pattern"* ]]; then
                affinity_file="/proc/irq/$irq/smp_affinity"
                if [ -w "$affinity_file" ]; then
                    echo "$mask" > "$affinity_file" 2>/dev/null || true
                fi
                break
            fi
        done
    done < <(tail -n +2 /proc/interrupts)
}
