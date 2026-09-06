// SPDX-License-Identifier: GPL-2.0
/*
 * sm8550_gpu_oc_entry.c
 *
 * Out-of-tree entry point for sm8550_gpu_oc kernel module.
 * The core OC logic is in sm8550_gpu_oc.c.
 *
 * Build:
 *   make -C /path/to/android-kernel M=$(pwd) LLVM=1 ARCH=arm64 modules
 */

#include "sm8550_gpu_oc.c"
