# SPDX-License-Identifier: GPL-2.0
#
# Out-of-tree build for sm8550_gpu_oc standalone kernel module
#
# Usage (from kernel source root):
#   make -C /path/to/android-kernel M=$(pwd) \
#        ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 modules
#
# Requires:
#   ARCH=arm64
#   LLVM=1  (Clang)
#   KDIR    (path to kernel source with SM8550 defconfig built)
#

obj-m := sm8550_gpu_oc.o
sm8550_gpu_oc-objs := sm8550_gpu_oc_entry.o

ccflags-y := \
	-I$(src)/.. \
	-I$(src)/../adreno \
	-DMODULE

.PHONY: all clean

all:
	@echo "sm8550_gpu_oc: use 'make -C $KDIR M=$(PWD) modules'"
	@echo "Example: make -C /path/to/kernel LLVM=1 ARCH=arm64 M=$(PWD) modules"

clean:
	rm -f *.o *.ko *.mod *.mod.c *.order *.symvers .*.cmd .cache.mk
