LOCAL_PATH := $(call my-dir)


# files that live under /system/etc/...

copy_from := \
   etc/init.qcom.bt.sh \
   etc/init.qcom.post_boot.sh \

copy_to := $(addprefix $(TARGET_OUT)/,$(copy_from))
copy_from := $(addprefix $(LOCAL_PATH)/,$(copy_from))

$(copy_to) : PRIVATE_MODULE := system_etcdir
$(copy_to) : $(TARGET_OUT)/% : $(LOCAL_PATH)/% | $(ACP)
	$(transform-prebuilt-to-target)

ALL_PREBUILT += $(copy_to)

# files that live under /...
file := $(TARGET_ROOT_OUT)/init.rc
$(file) : $(LOCAL_PATH)/rootdir/init.rc | $(ACP)
	$(transform-prebuilt-to-target)
ALL_PREBUILT += $(file)
$(INSTALLED_RAMDISK_TARGET): $(file)

file := $(TARGET_ROOT_OUT)/init.qcom.rc
$(file) : $(LOCAL_PATH)/rootdir/init.qcom.rc | $(ACP)
	$(transform-prebuilt-to-target)
ALL_PREBUILT += $(file)
$(INSTALLED_RAMDISK_TARGET): $(file)

file := $(TARGET_ROOT_OUT)/ueventd.rc
$(file) : $(LOCAL_PATH)/rootdir/ueventd.rc | $(ACP)
	$(transform-prebuilt-to-target)
ALL_PREBUILT += $(file)
$(INSTALLED_RAMDISK_TARGET): $(file)


# kernel stuff...

ifeq ($(KERNEL_DEFCONFIG),)
    # TODO:  Use ../../config/msm7627a_sku1-perf_defconfig
    KERNEL_DEFCONFIG := msm7627a_sku3-perf_defconfig
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
