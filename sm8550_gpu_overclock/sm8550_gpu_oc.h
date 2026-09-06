/* SPDX-License-Identifier: GPL-2.0 */
/*
 * SM8550 GPU Overclock Module
 *
 * Adds synthetic turbo OPPs to the Adreno 740 GPU OPP table so that
 * devfreq's simple_ondemand governor can select frequencies above the
 * stock 767 MHz ceiling.
 *
 * Stock SM8550 GPU frequencies (Adreno 740):
 *   514 MHz (suspend/idle)
 *   575 MHz
 *   681 MHz
 *   767 MHz (max stock)
 *
 * Turbo OPPs added by this module:
 *   820 MHz  (~7% over stock)
 *   875 MHz  (~14% over stock) — safe for most thermals
 *
 * These are synthetic OPPs: they override what the device tree provides,
 * and the GMU/HFI layer maps them to the nearest supported RPMh vote.
 *
 * Requires: CONFIG_PM_OPP=y, CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y
 * Safety:   sysfs knob /sys/module/sm8550_gpu_oc/parameters/oc_enabled
 *           (echo 0 > to disable, echo 1 > to re-enable)
 */

#ifndef __SM8550_GPU_OC_H__
#define __SM8550_GPU_OC_H__

#include <linux/device.h>
#include <linux/devfreq.h>

#define SM8550_GPU_OC_TURBO_820   820000000UL   /* 820 MHz */
#define SM8550_GPU_OC_TURBO_875   875000000UL   /* 875 MHz */

/* sysfs tunables */
extern bool sm8550_gpu_oc_enabled;

/*
 * sm8550_gpu_oc_register - add turbo OPPs to a GPU device
 * @dev: pointer to the GPU platform device
 *
 * Returns 0 on success, negative errno on failure.
 * Idempotent: safe to call even if already registered.
 */
int sm8550_gpu_oc_register(struct device *dev);

/*
 * sm8550_gpu_oc_unregister - remove turbo OPPs from a GPU device
 * @dev: pointer to the GPU platform device
 *
 * Call this on driver remove() to clean up.
 */
void sm8550_gpu_oc_unregister(struct device *dev);

#endif /* __SM8550_GPU_OC_H__ */
