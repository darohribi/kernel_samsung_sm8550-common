#!/system/bin/bash
# SM8550 MSPv2 - service.sh
# Boot-time initialization for Magisk/KernelSU module.
# Runs after /data is mounted.
#
# This applies the common.sh baseline and starts the thermal controller.

MODDIR=${0%/*}
LOG_FILE=/data/local/tmp/mspv2.log

# Ensure log directory exists
mkdir -p /data/local/tmp 2>/dev/null

# Verify bash is available
if [ ! -x /system/bin/bash ]; then
    echo "[mspv2-service] ERROR: /system/bin/bash not found or not executable" >> "$LOG_FILE"
    exit 1
fi

# Apply common baseline settings
echo "[mspv2-service] $(date) Starting MSPv2 common.sh..." >> "$LOG_FILE"
/system/bin/bash "$MODDIR/runtime/common.sh" >> "$LOG_FILE" 2>&1

# Start thermal controller in background
# The thermal controller is designed to run continuously.
# It will adjust performance based on skin temperature.
nohup /system/bin/bash "$MODDIR/runtime/thermal.sh" >> "$LOG_FILE" 2>&1 &

echo "[mspv2-service] $(date) MSPv2 started, thermal controller running in background." >> "$LOG_FILE"
