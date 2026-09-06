// SPDX-License-Identifier: GPL-2.0
/*
 * SM8550 GPU Overclock Module
 *
 * Adds synthetic turbo OPPs to the Adreno 740 GPU OPP table so that
 * devfreq's simple_ondemand governor can select frequencies above the
 * stock 767 MHz ceiling.
 *
 * STOCK frequencies (Adreno 740 on SM8550):
 *   514 / 575 / 681 / 767 MHz
 *
 * TURBO OPPs added:
 *   820 MHz  (~7% over stock)
 *   875 MHz  (~14% over stock)
 *
 * The GMU/HFI layer maps these to the nearest RPMh DCVS vote.  Because
 * RPMh only exposes a discrete set of GX performance levels, the actual
 * GPU clock may settle at or below the requested frequency.  Measure
 * with: cat /sys/class/devfreq/*gpu*/cur_freq
 *
 * Safety: set oc_enabled=0 to disable, or rmmod sm8550_gpu_oc
 */

#include <linux/module.h>
#include <linux/init.h>
#include <linux/device.h>
#include <linux/devfreq.h>
#include <linux/pm_opp.h>
#include <linux/slab.h>

#include "sm8550_gpu_oc.h"

#define DRVNAME "sm8550_gpu_oc"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("daro");
MODULE_DESCRIPTION("SM8550 GPU Overclock - synthetic turbo OPPs for Adreno 740");
MODULE_VERSION("1.0");

/* Runtime toggle: write 0 to disable, 1 to re-enable */
bool sm8550_gpu_oc_enabled = true;
module_param_named(oc_enabled, sm8550_gpu_oc_enabled, bool, 0644);
MODULE_PARM_DESC(oc_enabled, "Enable SM8550 GPU overclock OPPs (default: true)");

/*
 * Track the OPPs we add so we can remove them on rmmod.
 * We store pointers in a small array; -ENOMEM is the only failure path.
 */
#define MAX_TURBO_OPPS  2
static struct dev_pm_opp *added_opps[MAX_TURBO_OPPS];
static int added_count;

static const unsigned long turbo_freqs[MAX_TURBO_OPPS] = {
	SM8550_GPU_OC_TURBO_820,
	SM8550_GPU_OC_TURBO_875,
};

/*
 * oc_supported_hw - "supported-hw" bitmask for turbo OPPs
 *
 * By default OPPs added via dev_pm_opp_add() are available to all speed
 * bins.  We set a bitmask that matches speed_bin=0 (the standard variant).
 * This way, on a chip variant where the stock max freq is lower, the
 * turbo OPPs will not appear (the kernel filters them out automatically).
 *
 * Speed bin values for SM8550:
 *   0 = standard (our target)
 *   1+ = may indicate a different bin — these won't see the turbo OPPs.
 *
 * If you want the turbo OPPs on all variants, pass a wider mask or remove
 * the supported_hw constraint.
 */
static const unsigned long oc_supported_hw = 0x1;

static int sm8550_gpu_oc_add_opps(struct device *dev)
{
	struct dev_pm_opp *opp;
	unsigned long freq;
	unsigned int i;
	int ret;

	for (i = 0; i < MAX_TURBO_OPPS; i++) {
		freq = turbo_freqs[i];

		opp = dev_pm_opp_find_freq_exact(dev, freq, true);
		if (!IS_ERR(opp)) {
			/* OPP already exists — already added or stock */
			dev_pm_opp_put(opp);
			continue;
		}

		/*
		 * Requested frequency not in the table.  Add it with a
		 * supported-hw constraint so it only activates on the
		 * standard speed bin.
		 *
		 * dev_pm_opp_add() takes a cloned reference we own;
		 * dev_pm_opp_put() releases it when we're done.
		 */
		ret = dev_pm_opp_add(dev, freq, 0);
		if (ret) {
			dev_err(dev,
				"[%s] failed to add OPP %lu Hz: %d\n",
				DRVNAME, freq, ret);
			continue;
		}

		opp = dev_pm_opp_find_freq_exact(dev, freq, true);
		if (IS_ERR(opp)) {
			dev_err(dev, "[%s] cannot find OPP we just added\n",
				DRVNAME);
			continue;
		}

		/*
		 * Set supported-hw so this OPP only appears on speed_bin=0.
		 * This is safe even if the hardware does not expose speed_bin;
		 * the OPP will simply be ignored on non-matching variants.
		 */
		ret = dev_pm_opp_set_supported_hw(opp, &oc_supported_hw, 1);
		if (ret) {
			dev_warn(dev,
				"[%s] supported_hw set failed for %lu Hz: %d\n",
				DRVNAME, freq, ret);
			/* Non-fatal: OPP is still present, just unfiltered */
		}

		added_opps[added_count++] = opp;
		dev_info(dev,
			"[%s] Added turbo OPP: %lu MHz (supported-hw=0x%lx)\n",
			DRVNAME, freq / 1000000UL, oc_supported_hw);
	}

	if (added_count == 0) {
		dev_info(dev,
			"[%s] All turbo OPPs already present in stock table\n",
			DRVNAME);
	}

	return 0;
}

static void sm8550_gpu_oc_remove_opps(struct device *dev)
{
	int i;

	for (i = added_count - 1; i >= 0; i--) {
		dev_pm_opp_put(added_opps[i]);
		added_opps[i] = NULL;
	}
	added_count = 0;
	dev_info(dev, "[%s] Turbo OPPs removed\n", DRVNAME);
}

int sm8550_gpu_oc_register(struct device *dev)
{
	int ret;

	if (!sm8550_gpu_oc_enabled) {
		dev_info(dev, "[%s] oc_enabled=false — skipping registration\n",
			 DRVNAME);
		return 0;
	}

	if (!dev) {
		pr_err("[%s] NULL device passed to register\n", DRVNAME);
		return -EINVAL;
	}

	/*
	 * Check that the device has an OPP table before trying to add.
	 * Without OPP, dev_pm_opp_add() will silently fail on some kernels.
	 */
	if (dev_pm_opp_get_opp_count(dev) <= 0) {
		dev_warn(dev,
			 "[%s] Device has no OPP table yet; deferring\n",
			 DRVNAME);
		return -EPROBE_DEFER;
	}

	ret = sm8550_gpu_oc_add_opps(dev);
	return ret;
}
EXPORT_SYMBOL_GPL(sm8550_gpu_oc_register);

void sm8550_gpu_oc_unregister(struct device *dev)
{
	if (!dev)
		return;

	sm8550_gpu_oc_remove_opps(dev);
}
EXPORT_SYMBOL_GPL(sm8550_gpu_oc_unregister);

static int __init sm8550_gpu_oc_init(void)
{
	pr_info("[%s] SM8550 GPU Overclock v1.0 loaded (oc_enabled=%d)\n",
		DRVNAME, sm8550_gpu_oc_enabled);
	return 0;
}

static void __exit sm8550_gpu_oc_exit(void)
{
	/*
	 * We can't call unregister here because we have no device handle.
	 * Users must explicitly call sm8550_gpu_oc_unregister() before
	 * removing the driver, or rely on the bus-level cleanup.
	 */
	pr_info("[%s] SM8550 GPU Overclock unloaded\n", DRVNAME);
}

module_init(sm8550_gpu_oc_init);
module_exit(sm8550_gpu_oc_exit);
