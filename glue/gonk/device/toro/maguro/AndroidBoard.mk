LOCAL_PATH := $(call my-dir)

ifeq ($(KERNEL_DEFCONFIG),)
    # TODO:  Use ../../config/msm7627a_sku1-perf_defconfig
    KERNEL_DEFCONFIG := msm7627a_sku1-perf_defconfig
endif


# Kernel tree doesn't live in the standard Android kernel/ location, so some
# path gymnastics are needed:
KERNELTREE_DIR=../../boot/msm#
KERNELTREE_DIR_REV=../../glue/gonk#
include $(LOCAL_PATH)/AndroidKernel.mk

file := $(LOCAL_PATH)/kernel
ALL_PREBUILT += $(file)
$(file) : $(TARGET_PREBUILT_KERNEL) | $(ACP)
	$(transform-prebuilt-to-target)
