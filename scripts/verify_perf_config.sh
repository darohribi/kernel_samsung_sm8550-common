#!/bin/bash
# SM8550 Maximum Performance - Build-time config verification
# Run after kernel config to verify all options are set
# NOTE: Symbols marked GKI-VENDOR do NOT exist in GKI common tree;
# they are applied via runtime sysfs/property tweaks instead.

set -euo pipefail

echo "=== Verifying SM8550 Performance Config ==="

# Check critical configs
check_config() {
    local config=$1
    local expected=$2
    if grep -q "^${config}=${expected}$" .config; then
        echo "✓ $config=$expected"
    elif grep -q "^# ${config} is not set$" .config && [ "$expected" = "n" ]; then
        echo "✓ $config is not set"
    else
        echo "✗ $config: expected '$expected', got '$(grep "^${config}=" .config || echo "not found")'"
    fi
}

echo ""
echo "--- Scheduler / EAS ---"
check_config "CONFIG_UCLAMP_BUCKETS_COUNT" "20"   # Kconfig max range is 20
check_config "CONFIG_SCHED_THERMAL_PRESSURE" "y"
check_config "CONFIG_ENERGY_MODEL" "y"

echo ""
echo "--- CPUFreq ---"
check_config "CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL" "y"
check_config "CONFIG_CPU_FREQ_GOV_PERFORMANCE" "y"

echo ""
echo "--- CPU Boost / Core Control (GKI-VENDOR: runtime only) ---"
echo "  ℹ CONFIG_QCOM_CPUBOOST: runtime sysfs, not in GKI common"
echo "  ℹ CONFIG_QCOM_CORE_CTL: runtime sysfs, not in GKI common"

echo ""
echo "--- Thermal ---"
check_config "CONFIG_THERMAL_DEFAULT_GOV_USER_SPACE" "y"
check_config "CONFIG_THERMAL_GOV_POWER_ALLOCATOR" "n"

echo ""
echo "--- Memory / ZRAM ---"
check_config "CONFIG_ZRAM_DEF_COMP_ZSTD" "y"
check_config "CONFIG_ZRAM_LRU_WRITEBACK_LIMIT" "4096"
check_config "CONFIG_FRONTSWAP" "y"
check_config "CONFIG_ZSWAP" "y"
check_config "CONFIG_ZSWAP_COMPRESSOR_DEFAULT_ZSTD" "y"

echo ""
echo "--- Transparent Hugepages (GKI boot-safe: MADVISE, not ALWAYS) ---"
check_config "CONFIG_TRANSPARENT_HUGEPAGE" "y"
check_config "CONFIG_TRANSPARENT_HUGEPAGE_MADVISE" "y"
# Note: CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y causes CMA failures on arm64 mobile

echo ""
echo "--- I/O Scheduler (Kyber-only for UFS) ---"
check_config "CONFIG_IOSCHED_BFQ" "n"
check_config "CONFIG_MQ_IOSCHED_KYBER" "y"

echo ""
echo "--- GPU (GKI-VENDOR: not in GKI common) ---"
echo "  ℹ CONFIG_DRM_MSM_PREEMPT: downstream only, not in GKI common"

echo ""
echo "--- RCU ---"
check_config "CONFIG_RCU_BOOST_DELAY" "100"
# Note: RCU_BOOST_PRIO and RCU_NOCB_CPU_DEFAULT_ALL are GKI-VENDOR

echo ""
echo "--- Debug (must be DISABLED for performance) ---"
check_config "CONFIG_DEBUG_KERNEL" "n"
check_config "CONFIG_SCHED_DEBUG" "n"
check_config "CONFIG_SCHEDSTATS" "n"

echo ""
echo "=== Verification Complete ==="
