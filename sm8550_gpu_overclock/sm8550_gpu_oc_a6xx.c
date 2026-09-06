// SPDX-License-Identifier: GPL-2.0
/*
 * SM8550 GPU Overclock — A6xx integration shim
 *
 * Wires sm8550_gpu_oc into the a6xx_gpu probe path so that turbo OPPs
 * are added before devfreq is initialised.
 *
 * This file is compiled into the MSM DRM module (drivers/gpu/drm/msm/).
 * It calls sm8550_gpu_oc_register() from a6xx GPU probe and
 * sm8550_gpu_oc_unregister() on driver remove.
 *
 * SM8550 uses Adreno 740 (a6xx_rev >= 0x6000100), which is covered by
 * the a6xx_gpu_probe() path.
 */

#include <linux/device.h>
#include <linux/devfreq.h>
#include <linux/pm_opp.h>

#include "../msm_gpu.h"
#include "../adreno/adreno_gpu.h"
#include "../adreno/a6xx_gpu.h"

#include "sm8550_gpu_oc.h"

/*
 * Call this from a6xx_gpu_probe() AFTER adreno_get_pwrlevels() has run
 * (i.e. after the OPP table is populated from device-tree).
 *
 * Because a6xx does not export a probe hook, we use a late devm action
 * that runs after msm_devfreq_init().  Alternatively, the caller can
 * invoke sm8550_gpu_oc_register(&gpu->pdev->dev) directly from their
 * board file or from a6xx_gpu.c.
 */
static void oc_late_init(void *data)
{
	struct device *dev = data;

	/*
	 * At this point dev_pm_opp_of_add_table() has already been called by
	 * adreno_get_pwrlevels(), so the OPP table is populated.  We just add
	 * the synthetic turbo entries on top.
	 */
	sm8550_gpu_oc_register(dev);
}

static void oc_cleanup(void *data)
{
	struct device *dev = data;
	sm8550_gpu_oc_unregister(dev);
}

/**
 * sm8550_gpu_oc_a6xx_attach() — attach overclock module to a GPU device
 * @dev: pointer to the GPU platform device
 *
 * Call this from board-specific code or from the a6xx device-probe path
 * once the OPP table is available.  Safe to call multiple times.
 *
 * Returns 0 on success; negative errno otherwise.
 */
int sm8550_gpu_oc_a6xx_attach(struct device *dev)
{
	int ret;

	ret = devm_add_action_or_reset(dev, oc_late_init, dev);
	if (ret)
		return ret;

	ret = devm_add_action_or_reset(dev, oc_cleanup, dev);
	return ret;
}
EXPORT_SYMBOL_GPL(sm8550_gpu_oc_a6xx_attach);
