# SM8550 Maximum Sustainable Performance v2 (MSPv2)
#
# This directory replaces the v1 sm8550_ultra_perf_runtime.sh approach
# with a layered, progressive-thermal, per-cgroup UCLAMP design.
#
# ## Architecture
#
#     common
#       ↓
#     performance profile
#       ↓
#     gaming / benchmark profile
#       ↓
#     thermal controller (progressive response)
#
# ## Key design decisions (vs v1)
#
# - Thermal framework stays ENABLED. We never disable /sys/module/thermal.
# - Per-cgroup UCLAMP, never global minimum=1024.
# - Schedutil rate limits 1-3 ms up / 8-15 ms down.
# - No force_clk_on / force_bus_on permanently; only during burst.
# - Per-device IRQ affinity discovered from /proc/interrupts.
# - No global "all IRQs on CPUs 4-7" rule.
# - Skin temperature is the primary user-experience constraint.
#
# ## Layout
#
#   kernel/
#     config.fragment    - Kconfig additions for v2 (conservative)
#     sysctl.conf        - VM, dirty ratios, swappiness (measured, not extreme)
#   runtime/
#     common.sh          - One-time boot setup, detect SoC
#     performance.sh     - Daily-use profile
#     gaming.sh          - High-burst + low-latency profile (temporary)
#     benchmark.sh       - Maximum sustained for benchmarking only
#     thermal.sh         - Progressive thermal controller
#   tools/
#     detect_soc.sh      - Discover cluster topology
#     detect_policies.sh - Discover cpufreq policies
#     detect_irqs.sh     - Discover per-device IRQ numbers
#     benchmark.sh       - Quick performance sanity check
#
# ## Usage
#
#   /data/adb/modules/sm8550_mspv2/runtime/common.sh         # boot-time
#   /data/adb/modules/sm8550_mspv2/runtime/performance.sh    # daily
#   /data/adb/modules/sm8550_mspv2/runtime/gaming.sh         # game start
#   /data/adb/modules/sm8550_mspv2/runtime/benchmark.sh      # bench mode
#   /data/adb/modules/sm8550_mspv2/runtime/thermal.sh &     # always-on
#
# ## Goals
#
# - maximum sustainable performance
# - minimum frame / input latency
# - controlled thermal pressure
# - no unnecessary background work
#
# Not: maximum power consumption.
