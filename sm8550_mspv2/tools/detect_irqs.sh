#!/bin/bash
# SM8550 MSPv2 - tools/detect_irqs.sh
# Discover per-device IRQ numbers from /proc/interrupts and assign
# per-device affinity. NO global f0 rule.

set -euo pipefail

# Per-device affinity map. Adjust as needed; the file is data, not policy.
# Format: device-pattern : affinity-mask (in hex, f = CPUs 0-3, f0 = CPUs 4-7)
MSPV2_IRQ_MAP=(
    "touch:|40"
    "input:|40"
    "tsens|0f"
    "mdp|0f0"
    "dpu|0f0"
    "gpu|0f0"
    "kgsl|0f0"
    "ufshcd|0f"
    "sdhci|0f"
    "wifi|wlan|30"
    "wlan|30"
    "usb|0f"
    "xhci|0f"
    "smp2p|01"
    "glink|01"
    "scm|01"
)

mspv2_detect_irqs() {
    [ -r /proc/interrupts ] || return 0
    while read -r line; do
        irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
        [ -z "$irq" ] && continue
        # device name is the last non-numeric field
        name=$(echo "$line" | awk '{
            for (i=1; i<=NF; i++) {
                if ($i ~ /^[0-9,\s]+$/) continue
                last = $i
            }
            print last
        }')
        [ -z "$name" ] && continue

        for entry in "${MSPV2_IRQ_MAP[@]}"; do
            pattern="${entry%%:*}"
            affinity="${entry##*:}"
            if [[ "$name" == *"$pattern"* ]]; then
                affinity_file="/proc/irq/$irq/smp_affinity"
                [ -w "$affinity_file" ] && echo "$affinity" > "$affinity_file" 2>/dev/null || true
                break
            fi
        done
    done < <(tail -n +2 /proc/interrupts)
}
