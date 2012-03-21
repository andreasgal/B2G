include device/toro/maguro/BoardConfig.mk
BOARD_BOOTIMAGE_PARTITION_SIZE := 0x00A00000
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 0x00A00000
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 167772160   # 0x0A000000
BOARD_USERDATAIMAGE_PARTITION_SIZE := 536870912 # #0x20000000     # 512 MB fake size and should be decided by LK
BOARD_CACHEIMAGE_PARTITION_SIZE := 67108864
BOARD_PERSISTIMAGE_PARTITION_SIZE := 4121440

TARGET_USERIMAGES_USE_EXT4 := 

TARGET_BOOTLOADER_BOARD_NAME := MSM7627A_SKU3
QCOM_TARGET_PRODUCT := msm7627a_sku3

# Support to build images for 2K NAND page
#BOARD_SUPPORTS_2KNAND_PAGE := true
BOARD_KERNEL_PAGESIZE := 2048
BOARD_KERNEL_SPARESIZE := 64
BOARD_NAND_PAGE_SIZE := $(BOARD_KERNEL_PAGESIZE)

# Maguro blobs expect the following property values. Sneak them into
# /build.prop so that the defaults added to /system/build.prop by the
# build system are ignored (easier than messing around with the core
# build system at the moment.)
#
# TODO: This should eventually be fixed properly by renaming device/
#       directories...
#
ADDITIONAL_DEFAULT_PROPERTIES :=  \
   ro.product.model=msm7627a_sku1 \
   ro.product.brand=qcom \
   ro.product.name=msm7627a_sku1 \
   ro.product.device=msm7627a_sku1 \
   ro.product.board=msm7627a_sku1 \
   ro.build.product=msm7627a_sku1 \
