#!/bin/bash
# SM8550 Maximum Performance - Build-time config verification
# Run after kernel config to verify all options are set

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
check_config "CONFIG_SCHED_WALT" "y"
check_config "CONFIG_UCLAMP_BUCKETS_COUNT" "40"
check_config "CONFIG_SCHED_THERMAL_PRESSURE" "y"
check_config "CONFIG_ENERGY_MODEL" "y"

echo ""
echo "--- CPUFreq ---"
check_config "CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL" "y"
check_config "CONFIG_CPU_FREQ_GOV_PERFORMANCE" "y"

echo ""
echo "--- CPU Boost / Core Control ---"
check_config "CONFIG_QCOM_CPUBOOST" "y"
check_config "CONFIG_QCOM_CORE_CTL" "y"

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

echo ""
echo "--- I/O Scheduler ---"
check_config "CONFIG_IOSCHED_BFQ" "n"
check_config "CONFIG_MQ_IOSCHED_KYBER" "y"

echo ""
echo "--- GPU ---"
check_config "CONFIG_DRM_MSM_PREEMPT" "y"

echo ""
echo "--- RCU ---"
check_config "CONFIG_RCU_BOOST_DELAY" "100"
check_config "CONFIG_RCU_BOOST_PRIO" "99"
check_config "CONFIG_RCU_NOCB_CPU_DEFAULT_ALL" "y"

echo ""
echo "--- THP ---"
check_config "CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS" "y"
check_config "CONFIG_TRANSPARENT_HUGEPAGE_MADVISE" "n"

echo ""
echo "--- Debug ---"
check_config "CONFIG_DEBUG_KERNEL" "n"
check_config "CONFIG_SCHED_DEBUG" "n"
check_config "CONFIG_SCHEDSTATS" "n"

echo ""
echo "=== Verification Complete ==="