#!/system/bin/sh
# SM8550 MSPv2 - post-fs-data.sh
# Runs before late-mount. Use for early sysctl changes that need to happen
# before /data is fully mounted.

# Apply sysctl tunables early
SYSCTL_CONF="/data/adb/modules/sm8550_mspv2/sm8550_mspv2/kernel/sysctl.conf"
if [ -f "$SYSCTL_CONF" ]; then
    sysctl -p "$SYSCTL_CONF" 2>/dev/null
fi
