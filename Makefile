# To support gonk's build/envsetup.sh
SHELL = bash

GIT ?= git
HG ?= hg

-include local.mk
-include .config.mk

all: build

MAKE_FLAGS ?= -j16
GONK_MAKE_FLAGS ?=

GONK_BASE ?= glue/gonk
FASTBOOT ?= $(abspath $(GONK_BASE)/out/host/linux-x86/bin/fastboot)
HEIMDALL ?= heimdall
TOOLCHAIN_HOST = linux-x86
TOOLCHAIN_PATH ?= $(GONK_BASE)/prebuilt/$(TOOLCHAIN_HOST)/toolchain/arm-eabi-4.4.3/bin/arm-eabi-
KERNEL_TOOLCHAIN_PATH ?= $(GONK_BASE)/prebuilt/$(TOOLCHAIN_HOST)/toolchain/arm-eabi-4.4.3/bin

GAIA_PATH ?= $(abspath gaia)
GECKO_PATH ?= $(abspath gecko)
GONK_PATH = $(abspath $(GONK_BASE))

TEST_DIRS = $(GECKO_PATH)/testing/marionette/client/marionette/tests/unit-tests.ini

# We need adb for config-* targets.  Adb is built by building system
# of gonk that needs a correct product name provided by "GONK_TARGET".
# But, "GONK_TARGET" is not set properly before running any config-*
# target since "GONK" is not defined.  We fallback "GONK_TARGET" to
# generic-eng to build adb for config-* targets.
ifdef GONK
GONK_TARGET ?= full_$(GONK)-eng
else				# fallback to generic for a clean copy.
GONK_TARGET ?= generic-eng
endif

REPO_PATH := $(abspath repo)

glue/gonk-ics/.repo: $(REPO_PATH)
	mkdir -p glue/gonk-ics
	cd glue/gonk-ics && \
	$(REPO_PATH) init -u git://github.com/mozilla-b2g/gonk-ics-manifest.git

.PHONY: gonk-ics-sync
gonk-ics-sync: glue/gonk-ics/.repo
	cd glue/gonk-ics && \
	$(REPO_PATH) sync

# This path includes tools to simulate JDK tools.  Gonk would check
# version of JDK.  These fake tools do nothing but print out version
# number to stop gonk from error.
FAKE_JDK_PATH ?= $(abspath fake-jdk-tools)

define GONK_CMD # $(call GONK_CMD,cmd)
	export USE_CCACHE="yes" && \
	export JAVA_HOME=$(FAKE_JDK_PATH) && \
	export PATH=$(FAKE_JDK_PATH)/bin:$$PATH && \
	cd $(GONK_PATH) && \
	. build/envsetup.sh && \
	lunch $(GONK_TARGET) && \
	$(1)
endef

ANDROID_SDK_PLATFORM ?= android-13
GECKO_CONFIGURE_ARGS ?=

# |make STOP_DEPENDENCY_CHECK=true| to stop dependency checking
STOP_DEPENDENCY_CHECK ?= true

define SUBMODULES
	cat .gitmodules |grep path|awk -- '{print $$3;}'
endef

define DEP_LIST_GIT_FILES
$(GIT) ls-files | xargs -d '\n' stat -c '%n:%Y' --; \
$(GIT) ls-files -o -X .gitignore | xargs -d '\n' stat -c '%n:%Y' --
endef

define DEP_LIST_HG_FILES
$(HG) locate | xargs -d '\n' stat -c '%n:%Y' --
endef

define DEP_LIST_FILES
(if [ -d .git ]; then \
    $(call DEP_LIST_GIT_FILES); \
elif [ -d .hg ]; then \
    $(call DEP_LIST_HG_FILES); \
fi)
endef

# Generate hash code for timestamp and filename of source files
#
# This function is for modules as subdirectories of given directory.
# $(1): the name of subdirectory that you want to hash for.
#
define DEP_HASH_MODULES
	(_pwd=$$PWD; \
	for sdir in $$(($(SUBMODULES))|grep "$(strip $1)"); do \
		cd $$sdir; \
		$(call DEP_LIST_FILES); \
		cd $$_pwd; \
	done 2> /dev/null | sort | md5sum | awk -- '{print $$1;}')
endef

# Generate hash code for timestamp and filename of source files
#
# This function is for the module at given directory.
# $(1): the name of subdirectory that you want to hash for.
#
define DEP_HASH_MODULE
	(_pwd=$$PWD; cd $1; \
	$(call DEP_LIST_FILES) \
		2> /dev/null | sort | md5sum | awk -- '{print $$1;}'; \
	cd $$_pwd)
endef

# Generate hash code for timestamp and filename of source files
#
# $(1): the name of subdirectory that you want to hash for.
#
define DEP_HASH
	(if [ -d $(strip $1)/.git -o -d $(strip $1)/.hg ]; then \
		$(call DEP_HASH_MODULE,$1); \
	else \
		$(call DEP_HASH_MODULES,$(call DEP_REL_PATH,$1)); \
	fi)
endef

define DEP_REL_PATH
$(patsubst ./%,%,$(patsubst /%,%,$(patsubst $(PWD)%,%,$(strip $1))))
endef

ifeq ($(strip $(STOP_DEPENDENCY_CHECK)),false)
# Check hash code of sourc files and run commands for necessary.
#
# $(1): stamp file (where hash code is kept)
# $(2): sub-directory where the module is
# $(3): commands that you want to run if any of source files is updated.
#
define DEP_CHECK
	(echo -n "Checking dependency for $2 ..."; \
	if [ -e "$1" ]; then \
		LAST_HASH="$$(cat $1)"; \
		CUR_HASH=$$($(call DEP_HASH,$2)); \
		if [ "$$LAST_HASH" = "$$CUR_HASH" ]; then \
			echo " (skip)"; \
			exit 0; \
		fi; \
	fi; \
	echo; \
	_dep_check_pwd=$$PWD; \
	($3); \
	cd $$_dep_check_pwd; \
	$(call DEP_HASH,$2) > $1)
endef
else # STOP_DEPENDENCY_CHECK
define DEP_CHECK
($3)
endef
endif # STOP_DEPENDENCY_CHECK

CCACHE ?= $(shell which ccache)
ADB := $(abspath $(GONK_BASE)/out/host/linux-x86/bin/adb)

B2G_PID=$(shell $(ADB) shell toolbox ps | grep "b2g" | awk '{ print $$2; }')
GDBSERVER_PID=$(shell $(ADB) shell toolbox ps | grep "gdbserver" | awk '{ print $$2; }')

.PHONY: build
ifeq (glue/gonk,$(GONK_BASE))
build: gecko-install-hack gaia
	$(MAKE) gonk
else
build: gaia
	$(MAKE) gonk
endif

ifeq (qemu,$(KERNEL))
build: kernel bootimg-hack gaia
endif

KERNEL_DIR = boot/kernel-android-$(KERNEL)
ifeq (glue/gonk,$(GONK_BASE))
GECKO_OBJDIR ?= $(GECKO_PATH)/objdir-prof-gonk
MOZCONFIG = $(abspath config/gecko-prof-gonk)
else
GECKO_OBJDIR ?= $(abspath objdir-gecko)
MOZCONFIG = $(abspath glue/gonk-ics/gonk-misc/default-gecko-config)
endif

GONK_OBJDIR=$(abspath $(GONK_BASE)/out/target/product/$(GONK))

define GECKO_BUILD_CMD
	export MAKE_FLAGS=$(MAKE_FLAGS) && \
	export CONFIGURE_ARGS="$(GECKO_CONFIGURE_ARGS)" && \
	export GONK_PRODUCT="$(GONK)" && \
	export GONK_PATH="$(GONK_PATH)" && \
	export TARGET_TOOLS_PREFIX="$(abspath $(TOOLCHAIN_PATH))" && \
	export MOZCONFIG="$(MOZCONFIG)" && \
	export EXTRA_INCLUDE='$(EXTRA_INCLUDE)' && \
	export GECKO_OBJDIR="$(GECKO_OBJDIR)" && \
	ulimit -n 4096 && \
	$(MAKE) -C $(GECKO_PATH) -f client.mk -s $(MAKE_FLAGS) && \
	$(MAKE) -C $(GECKO_OBJDIR) package
endef

.PHONY: gecko
# XXX Hard-coded for prof-android target.  It would also be nice if
# client.mk understood the |package| target.
gecko:
	@$(call DEP_CHECK,$(GECKO_OBJDIR)/.b2g-build-done,$(GECKO_PATH),\
	$(call GECKO_BUILD_CMD) \
	)

.PHONY: gonk
gonk:
	@$(call DEP_CHECK,$(GONK_PATH)/out/.b2g-build-done,$(GONK_BASE), \
	    $(call GONK_CMD,$(MAKE) $(MAKE_FLAGS) $(GONK_MAKE_FLAGS) \
	           CONFIG_ESD=no \
	           GECKO_PATH=$(GECKO_PATH) \
	           GECKO_OBJDIR=$(GECKO_OBJDIR) ) ;\
	    $(if $(filter qemu,$(KERNEL)), \
		cp $(GONK_PATH)/system/core/rootdir/init.rc.gonk \
		    $(GONK_PATH)/out/target/product/$(GONK)/root/init.rc))

.PHONY: kernel
kernel: kernel-$(KERNEL)

.PHONY: kernel-galaxy-s2
kernel-galaxy-s2:
	@$(call DEP_CHECK,$(KERNEL_PATH)/.b2g-build-done,$(KERNEL_PATH),\
	    $(if $(filter galaxy-s2,$(KERNEL)), \
		(rm -rf boot/initramfs && \
		    cd boot/clockworkmod_galaxys2_initramfs && \
		    $(GIT) checkout-index -a -f --prefix ../initramfs/); \
		PATH="$$PATH:$(abspath $(KERNEL_TOOLCHAIN_PATH))" \
		    $(MAKE) -C $(KERNEL_PATH) $(MAKE_FLAGS) ARCH=arm \
		    CROSS_COMPILE="$(CCACHE) arm-eabi-"; \
		find "$(KERNEL_DIR)" -name "*.ko" | \
		    xargs -I MOD cp MOD "$(PWD)/boot/initramfs/lib/modules"; \
	    ) \
	    PATH="$$PATH:$(abspath $(KERNEL_TOOLCHAIN_PATH))" \
		$(MAKE) -C $(KERNEL_PATH) $(MAKE_FLAGS) ARCH=arm \
		CROSS_COMPILE="$(CCACHE) arm-eabi-"; )

kernel-galaxy-s2-ics:
	(rm -rf boot/initramfs && \
	 cd boot/initramfs-galaxy-s2-ics && \
	 $(GIT) checkout-index -a -f --prefix ../initramfs/); \
	export ARCH=arm && \
	export CROSS_COMPILE="$(CCACHE) $(abspath $(KERNEL_TOOLCHAIN_PATH))/arm-eabi-" && \
	export USE_SEC_FIPS_MODE=true && \
	$(MAKE) -C $(KERNEL_PATH) $(MAKE_FLAGS) u1_defconfig && \
	$(MAKE) -C $(KERNEL_PATH) $(MAKE_FLAGS) CROSS_COMPILE="$$CROSS_COMPILE" CONFIG_INITRAMFS_SOURCE="$(PWD)/boot/initramfs" CONFIG_INITRAMFS_ROOT_UID=squash CONFIG_INITRAMFS_ROOT_GID=squash && \
	mkdir -p boot/initramfs/lib/modules && \
	find "$(KERNEL_DIR)" -name dhd.ko -o -name j4fs.ko -o -name scsi_wait_scan.ko -o -name Si4709_driver.ko | \
	    xargs -I MOD cp MOD "$(PWD)/boot/initramfs/lib/modules" && \
	chmod -R g-w $(PWD)/boot/initramfs && \
	$(MAKE) -C $(KERNEL_PATH) $(MAKE_FLAGS) CROSS_COMPILE="$$CROSS_COMPILE" CONFIG_INITRAMFS_SOURCE="$(PWD)/boot/initramfs" CONFIG_INITRAMFS_ROOT_UID=squash CONFIG_INITRAMFS_ROOT_GID=squash

kernel-qemu:
	PATH="$$PATH:$(abspath $(KERNEL_TOOLCHAIN_PATH))" \
	    $(MAKE) -C $(KERNEL_PATH) $(MAKE_FLAGS) ARCH=arm \
	    CROSS_COMPILE="$(CCACHE) arm-eabi-"
	cp -p boot/kernel-android-qemu/arch/arm/boot/zImage \
		$(GONK_PATH)/device/qemu/kernel

.PHONY: clean
clean: clean-gecko clean-gonk clean-kernel

.PHONY: clean-gecko
clean-gecko:
	rm -rf $(GECKO_OBJDIR)

.PHONY: clean-gonk
clean-gonk:
	@$(call GONK_CMD,$(MAKE) clean)

.PHONY: clean-kernel
clean-kernel:
	@PATH="$$PATH:$(abspath $(TOOLCHAIN_PATH))" $(MAKE) -C $(KERNEL_PATH) ARCH=arm CROSS_COMPILE=arm-eabi- clean
	@rm -f $(KERNEL_PATH)/.b2g-build-done

.PHONY: mrproper
# NB: this is a VERY DANGEROUS command that will BLOW AWAY ALL
# outstanding changes you have.  It's mostly intended for "clean room"
# builds.
mrproper:
	$(GIT) submodule foreach '$(GIT) reset --hard' && \
	$(GIT) submodule foreach '$(GIT) clean -d -f -x' && \
	$(GIT) reset --hard && \
	$(GIT) clean -d -f -x

VENDOR_DIR=$(GONK_PATH)/vendor
APNS_CONF=$(VENDOR_DIR)/apns-conf.xml

$(VENDOR_DIR):
	mkdir -p $(VENDOR_DIR)

$(APNS_CONF): $(VENDOR_DIR)
	wget -O $(APNS_CONF) https://raw.github.com/CyanogenMod/android_vendor_cyanogen/gingerbread/prebuilt/common/etc/apns-conf.xml

.PHONY: config-galaxy-s2
config-galaxy-s2: adb-check-version $(APNS_CONF)
	@echo "KERNEL = galaxy-s2" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-galaxy-s2" >> .config.mk && \
	echo "GONK = galaxys2" >> .config.mk && \
	echo "GONK_BASE = glue/gonk" >> .config.mk && \
	echo "RELEASETOOLS = device/samsung/galaxys2/releasetools" >> .config.mk && \
	export PATH=$$PATH:$$(dirname $(ADB)) && \
	cp -p config/kernel-galaxy-s2 boot/kernel-android-galaxy-s2/.config && \
	cd glue/gonk/device/samsung/galaxys2/ && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

.PHONY: config-galaxy-s2-ics
config-galaxy-s2-ics: gonk-ics-sync adb-check-version
	@echo "KERNEL = galaxy-s2-ics" > .config.mk && \
	echo "KERNEL_PATH = ./boot/kernel-android-galaxy-s2-ics" >> .config.mk && \
	echo "GONK = galaxys2" >> .config.mk && \
	echo "GONK_BASE = glue/gonk-ics" >> .config.mk && \
	echo "RELEASETOOLS = device/samsung/galaxys2/releasetools" >> .config.mk && \
	export PATH=$$PATH:$$(dirname $(ADB)) && \
	cd glue/gonk-ics/device/samsung/galaxys2/ && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

# Hack!  Upstream boot/msm is RO at the moment and forking isn't
# a nice alternative at the moment...
.patches.applied:
	cd boot/msm && \
	$(GIT) apply $(abspath glue/patch)/yaffs_vfs.patch && \
	$(GIT) apply $(abspath glue/patch)/downscale_gpu.patch
	touch $@

.PHONY: config-maguro
config-maguro: .patches.applied adb-check-version $(APNS_CONF)
	@echo "KERNEL = msm" > .config.mk && \
        echo "KERNEL_PATH = ./boot/msm" >> .config.mk && \
	echo "GONK = maguro" >> .config.mk && \
	export PATH=$$PATH:$$(dirname $(ADB)) && \
	cd glue/gonk/device/toro/maguro && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

.PHONY: config-akami
config-akami: .patches.applied adb-check-version $(APNS_CONF)
	@echo "KERNEL = msm" > .config.mk && \
        echo "KERNEL_PATH = ./boot/msm" >> .config.mk && \
	echo "GONK = akami" >> .config.mk && \
	cd glue/gonk/device/toro/akami && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

define INSTALL_BLOBS
	mkdir -p download-$1 && \
	mkdir -p $3 && \
	cd download-$1 && \
	for BLOB in $2 ; do \
	  wget -N https://dl.google.com/dl/android/aosp/$$BLOB && \
	  tar xvfz $$BLOB ; \
	done && \
	for BLOB_SH in extract-*.sh ; do \
		PATH=$(FAKE_JDK_PATH):$$PATH && \
	  BLOB_SH_PATH="$$PWD/$$BLOB_SH" && \
	  VENDOR=`echo $$BLOB_SH | sed -e "s/extract-\([a-zA-Z]*\).*$$/\1/"` && \
		( cd $3 && \
		yes I ACCEPT | $$BLOB_SH_PATH ) ;\
	done
endef

NEXUSS4G_BLOBS := akm-crespo4g-grj90-1bec498a.tgz \
                  broadcom-crespo4g-grj90-c4ec9a38.tgz \
                  imgtec-crespo4g-grj90-a8e2ce86.tgz \
                  nxp-crespo4g-grj90-9abcae18.tgz \
                  samsung-crespo4g-grj90-9474e48f.tgz

.PHONY: blobs-nexuss4g
blobs-nexuss4g:
	$(call INSTALL_BLOBS,nexuss4g,$(NEXUSS4G_BLOBS),$(abspath glue/gonk))
	mkdir -p $(GONK_PATH)/packages/wallpapers/LivePicker
	touch $(GONK_PATH)/packages/wallpapers/LivePicker/android.software.live_wallpaper.xml

NEXUSS_ICS_BLOBS := akm-crespo-iml74k-48d943ee.tgz \
                    broadcom-crespo-iml74k-4b0a7e2a.tgz \
                    imgtec-crespo-iml74k-33420a2f.tgz \
                    nxp-crespo-iml74k-9f2a89d1.tgz \
                    samsung-crespo-iml74k-0dbf413c.tgz

.PHONY: blobs-nexuss-ics
blobs-nexuss-ics:
	$(call INSTALL_BLOBS,nexuss-ics,$(NEXUSS_ICS_BLOBS),$(abspath glue/gonk-ics))

GALAXY_NEXUS_BLOBS := broadcom-maguro-imm76d-4ee51a8d.tgz \
                      imgtec-maguro-imm76d-0f59ea74.tgz \
                      samsung-maguro-imm76d-d16591cf.tgz
.PHONY: blobs-galaxy-nexus
blobs-galaxy-nexus:
	$(call INSTALL_BLOBS,galaxy-nexus,$(GALAXY_NEXUS_BLOBS),$(abspath glue/gonk-ics))

.PHONY: config-nexuss4g
config-nexuss4g: blobs-nexuss4g $(APNS_CONF)
	@echo "KERNEL = samsung" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-samsung" >> .config.mk && \
	echo "GONK = crespo4g" >> .config.mk && \
	cp -p config/kernel-nexuss4g boot/kernel-android-samsung/.config && \
	echo OK

.PHONY: config-nexuss-ics
config-nexuss-ics: blobs-nexuss-ics gonk-ics-sync
	@echo "KERNEL = samsung" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-samsung" >> .config.mk && \
	echo "GONK = crespo" >> .config.mk && \
	echo "GONK_BASE = glue/gonk-ics" >> .config.mk && \
	echo "TOOLCHAIN_PATH = ./toolchains/arm-linux-androideabi-4.4.x/bin/arm-linux-androideabi-" >> .config.mk && \
	echo "EXTRA_INCLUDE = -include $(abspath Unicode.h)" >> .config.mk && \
	echo OK

.PHONY: config-galaxy-nexus
config-galaxy-nexus: blobs-galaxy-nexus gonk-ics-sync
	@echo "KERNEL = samsung" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-samsung" >> .config.mk && \
	echo "GONK = maguro" >> .config.mk && \
	echo "GONK_BASE = glue/gonk-ics" >> .config.mk && \
	echo "TOOLCHAIN_PATH = ./toolchains/arm-linux-androideabi-4.4.x/bin/arm-linux-androideabi-" >> .config.mk && \
	echo "EXTRA_INCLUDE = -include $(abspath Unicode.h)" >> .config.mk && \
	echo OK

.PHONY: config-qemu
config-qemu:
	@echo "KERNEL = qemu" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-qemu" >> .config.mk && \
	echo "GONK = generic" >> .config.mk && \
	echo "GONK_TARGET = generic-eng" >> .config.mk && \
	echo "GONK_MAKE_FLAGS = TARGET_ARCH_VARIANT=armv7-a" >> .config.mk && \
	$(MAKE) -C boot/kernel-android-qemu ARCH=arm goldfish_armv7_defconfig && \
	( [ -e $(GONK_PATH)/device/qemu ] || \
		mkdir $(GONK_PATH)/device/qemu ) && \
	echo OK

.PHONY: config-qemu-ics
config-qemu-ics: gonk-ics-sync
	@echo "KERNEL = qemu-ics" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-qemu" >> .config.mk && \
	echo "GONK = generic" >> .config.mk && \
	echo "GONK_BASE = glue/gonk-ics" >> .config.mk && \
	echo "TOOLCHAIN_PATH = ./toolchains/arm-linux-androideabi-4.4.x/bin/arm-linux-androideabi-" >> .config.mk && \
	echo "EXTRA_INCLUDE = -include $(abspath Unicode.h)" >> .config.mk && \
	echo "GONK_TARGET = generic-eng" >> .config.mk && \
	echo "GONK_MAKE_FLAGS = TARGET_ARCH_VARIANT=armv7-a" >> .config.mk && \
	echo OK

.PHONY: flash
# XXX Using target-specific targets for the time being.  fastboot is
# great, but the sgs2 doesn't support it.  Eventually we should find a
# lowest-common-denominator solution.
flash: flash-$(GONK) update-time

# flash-only targets are the same as flash targets, except that they don't
# depend on building the image.

.PHONY: flash-only
flash-only: flash-only-$(GONK) update-time

.PHONY: flash-crespo
flash-crespo: flash-crespo4g

.PHONY: flash-only-crespo
flash-only-crespo: flash-only-crespo4g

.PHONY: flash-crespo4g
flash-crespo4g: image adb-check-version flash-only-fastboot

.PHONY: flash-only-crespo4g
flash-only-crespo4g: adb-check-version flash-only-fastboot

define FLASH_GALAXYS2_CMD
@echo "Rebooting into download mode..." && $(ADB) reboot download && sleep 20 || \
       echo "Perhaps the device is already in download mode?"
$(HEIMDALL) flash --factoryfs $(GONK_PATH)/out/target/product/galaxys2/system.img
$(FLASH_GALAXYS2_CMD_CHMOD_HACK)
endef

.PHONY: flash-galaxys2
flash-galaxys2: image adb-check-version
	$(FLASH_GALAXYS2_CMD)

.PHONY: flash-only-galaxys2
flash-only-galaxys2: adb-check-version
	$(FLASH_GALAXYS2_CMD)

.PHONY: flash-maguro
flash-maguro: image flash-only-maguro

.PHONY: flash-only-maguro
flash-only-maguro: flash-only-fastboot

.PHONY: flash-akami
flash-akami: image flash-only-akami

.PHONY: flash-only-akami
flash-only-akami: flash-only-fastboot

# Flash devices that use the fastboot protocol.
.PHONY: flash-only-fastboot
flash-only-fastboot:
	@$(call GONK_CMD, \
	$(ADB) reboot bootloader && \
	$(FASTBOOT) devices && \
	$(FASTBOOT) erase cache && \
	$(FASTBOOT) erase userdata && \
	$(FASTBOOT) flash userdata ./out/target/product/$(GONK)/userdata.img && \
	$(FASTBOOT) flashall)

.PHONY: bootimg-hack
bootimg-hack: kernel-$(KERNEL)

OUT_DIR := $(GONK_PATH)/out/target/product/$(GONK)/system
DATA_OUT_DIR := $(GONK_PATH)/out/target/product/$(GONK)/data
APP_OUT_DIR := $(OUT_DIR)/app
GECKO_OUT_DIR := $(GECKO_OBJDIR)/dist/b2g

$(APP_OUT_DIR):
	mkdir -p $(APP_OUT_DIR)

.PHONY: gecko-install-hack
gecko-install-hack: gecko
ifeq ($(GONK_BASE),glue/gonk)
	rm -rf $(OUT_DIR)/b2g
	mkdir -p $(OUT_DIR)
	# Extract the newest tarball in the gecko objdir.
	( cd $(OUT_DIR) && \
	  tar xvfz $$(ls -t $(GECKO_OBJDIR)/dist/b2g-*.tar.gz | head -n1) )
	find $(GONK_PATH)/out -name "system.img" | xargs rm -f
	@$(call GONK_CMD,$(MAKE) $(MAKE_FLAGS) $(GONK_MAKE_FLAGS) systemimage-nodeps)
endif

.PHONY: gaia
gaia:
	GAIA_DOMAIN=$(GAIA_DOMAIN) $(MAKE) -C $(GAIA_PATH) profile
	rm -rf $(DATA_OUT_DIR)/local
	mkdir -p $(DATA_OUT_DIR)/local
	cp -r $(GAIA_PATH)/profile/* $(DATA_OUT_DIR)/local

.PHONY: install-gecko
install-gecko: gecko-install-hack adb-check-version
	$(ADB) remount
	$(ADB) push $(GECKO_OUT_DIR) /system/b2g

.PHONY: install-gecko-only
install-gecko-only:
	$(ADB) remount
	$(ADB) push $(GECKO_OUT_DIR) /system/b2g

# The sad hacks keep piling up...  We can't set this up to be
# installed as part of the data partition because we can't flash that
# on the sgs2.
.PHONY: install-gaia
install-gaia: adb-check-version
	ADB=$(ADB) $(MAKE) -C $(GAIA_PATH) install-gaia

.PHONY: install-gaia-latest
install-gaia-latest: adb-check-version
	cd $(GAIA_PATH) && $(GIT) checkout master && $(GIT) pull origin master
	ADB=$(ADB) $(MAKE) -C $(GAIA_PATH) install-gaia

.PHONY: image
image: build
	@echo XXX stop overwriting the prebuilt nexuss4g kernel

.PHONY: unlock-bootloader
unlock-bootloader: adb-check-version
	@$(call GONK_CMD,$(ADB) reboot bootloader && fastboot oem unlock)

# Kill the b2g process on the device.
.PHONY: kill-b2g
.SECONDEXPANSION:
kill-b2g: adb-check-version
	$(ADB) shell kill $(B2G_PID)

.PHONY: sync
sync:
	$(GIT) pull origin master
	$(GIT) submodule sync
	$(GIT) submodule update --init

PKG_DIR := package

.PHONY: package
package:
	rm -rf $(PKG_DIR)
	mkdir -p $(PKG_DIR)/qemu/bin
	mkdir -p $(PKG_DIR)/gaia
	cp $(GONK_PATH)/out/host/linux-x86/bin/emulator $(PKG_DIR)/qemu/bin
	cp $(GONK_PATH)/out/host/linux-x86/bin/emulator-arm $(PKG_DIR)/qemu/bin
	cp $(GONK_PATH)/out/host/linux-x86/bin/adb $(PKG_DIR)/qemu/bin
	cp boot/kernel-android-qemu/arch/arm/boot/zImage $(PKG_DIR)/qemu
	cp -R $(GONK_PATH)/out/target/product/generic $(PKG_DIR)/qemu
	cp -R $(GAIA_PATH)/tests $(PKG_DIR)/gaia
	cd $(PKG_DIR) && tar -czvf qemu_package.tar.gz qemu gaia

.PHONY: package-qemu-ics
package-qemu-ics:
	rm -rf $(PKG_DIR)
	mkdir -p $(PKG_DIR)/qemu/bin
	mkdir -p $(PKG_DIR)/gaia
	cp package-emu-ics.sh $(PKG_DIR)
	cp $(GONK_PATH)/out/host/linux-x86/bin/emulator $(PKG_DIR)/qemu/bin
	cp $(GONK_PATH)/out/host/linux-x86/bin/emulator-arm $(PKG_DIR)/qemu/bin
	cp $(GONK_PATH)/out/host/linux-x86/bin/adb $(PKG_DIR)/qemu/bin
	cp $(GONK_PATH)/prebuilts/qemu-kernel/arm/kernel-qemu-armv7 $(PKG_DIR)/qemu
	cp -R $(GONK_PATH)/development/tools/emulator/skins $(PKG_DIR)/qemu
	cp -R $(GONK_PATH)/out/target/product/generic $(PKG_DIR)/qemu
	cp -R $(GAIA_PATH)/tests $(PKG_DIR)/gaia
	cd $(PKG_DIR) && tar -czvf qemu_package.tar.gz qemu gaia

# Create a flashable zip for ClockworkMod-Recovery
TARGET_OUT := $(GONK_PATH)/out/target/product/$(GONK)
OTA_TARGET_PACKAGE := update-b2g-$(shell date +%Y%m%d)-$(GONK).zip
.PHONY: otapackage
otapackage:
ifdef RELEASETOOLS
	@echo Package OTAPACKAGE: $(OTA_TARGET_PACKAGE)
	@rm -rf $(TARGET_OUT)/otapackage
	@mkdir -p $(TARGET_OUT)/otapackage/system
	@mkdir -p $(TARGET_OUT)/otapackage/META-INF/com/google/android
	@cp -R $(TARGET_OUT)/system/* $(TARGET_OUT)/otapackage/system/
	@cp $(GONK_PATH)/$(RELEASETOOLS)/update-binary $(TARGET_OUT)/otapackage/META-INF/com/google/android/update-binary
	@cp $(GONK_PATH)/$(RELEASETOOLS)/updater-script $(TARGET_OUT)/otapackage/META-INF/com/google/android/updater-script
	@echo Zipping package...
	@cd $(TARGET_OUT)/otapackage && zip -rq $(TARGET_OUT)/$(OTA_TARGET_PACKAGE) ./
	@echo Package complete: $(OTA_TARGET_PACKAGE)
	@cd $(TARGET_OUT) && md5sum $(OTA_TARGET_PACKAGE)
else
	@echo Path to updater-script not defined. Aborting.
endif

UPDATE_PACKAGE_TARGET ?= b2g-gecko-update.mar
MAR ?= $(GECKO_OBJDIR)/dist/host/bin/mar
MAKE_FULL_UPDATE ?= $(GECKO_PATH)/tools/update-packaging/make_full_update.sh
.PHONY: gecko-full-update
gecko-update-full: gecko
	MAR=$(MAR) $(MAKE_FULL_UPDATE) $(UPDATE_PACKAGE_TARGET) $(GECKO_OUT_DIR)
	sha512sum $(UPDATE_PACKAGE_TARGET)
	ls -l $(UPDATE_PACKAGE_TARGET)

#
# Package up everything needed to build mozilla-central with
# --enable-application=b2g outside of a b2g git clone.
#

# A linux host is needed (well, it's easiest) to build *Gonk* and
# hence the libraries needed by the toolchain, but once built, the
# toolchain itself can be packaged for multiple targets.
TOOLCHAIN_TARGET ?= linux-x86

# List of all dirs that gecko depends on.  These are relative to
# GONK_PATH.
#
# NB: keep this in sync with gecko/configure.in.
#
# XXX: why do we -Ibionic?  There's some dep in there that's not
# exposed through a more specific -I.  Not loading all of bionic
# results in a build error :|.
TOOLCHAIN_DIRS = \
	bionic \
	external/stlport/stlport \
	external/dbus \
	frameworks/base/include \
	frameworks/base/native/include \
	frameworks/base/opengl/include \
	frameworks/base/services/sensorservice \
	hardware/libhardware/include \
	hardware/libhardware_legacy/include \
	ndk/sources/android/cpufeatures \
	ndk/sources/cxx-stl/system/include \
	ndk/sources/cxx-stl/stlport/stlport \
	out/target/product/$(GONK)/obj/lib \
	prebuilt/ndk/android-ndk-r4/platforms/android-8/arch-arm \
	prebuilt/$(TOOLCHAIN_TARGET)/toolchain/arm-eabi-4.4.3 \
	system/core/include

# Toolchain versions are numbered consecutively. Toolchain version
# should be bumped whenever a new toolchain is generated
TOOLCHAIN_VERSION := 1
TOOLCHAIN_PKG_DIR := gonk-toolchain-$(TOOLCHAIN_VERSION)
.PHONY: package-toolchain
package-toolchain: gonk
	@rm -rf $(TOOLCHAIN_PKG_DIR); \
	mkdir $(TOOLCHAIN_PKG_DIR); \
	$(GIT) rev-parse HEAD > $(TOOLCHAIN_PKG_DIR)/b2g-commit-sha1.txt; \
	$(foreach d,$(TOOLCHAIN_DIRS),\
	  mkdir -p $(TOOLCHAIN_PKG_DIR)/$(d); \
	  cp -r $(GONK_PATH)/$(d)/* $(TOOLCHAIN_PKG_DIR)/$(d); \
	) \
	tar -cjvf $(TOOLCHAIN_PKG_DIR).tar.bz2 $(TOOLCHAIN_PKG_DIR); \
	rm -rf $(TOOLCHAIN_PKG_DIR)

$(ADB):
	@$(call GONK_CMD,$(MAKE) adb)

.PHONY: adb
adb: $(ADB)

# Make sure running right version of adb server.
#
# Adb will write some noise to stdout while running server of
# different version.  It make rules that depend on output of adb going
# wrong.  adb start-server before doing anything can prevent it.  adb
# start-server will kill current adb server and start a new instance
# if version numbers are not matched.
.PHONY: adb-check-version
adb-check-version: $(ADB)
	$(ADB) start-server

.PHONY: test
test:
	cd $(GECKO_PATH)/testing/marionette/client/marionette && \
	sh venv_test.sh `which python` --emulator --homedir=$(abspath .) --type=b2g $(TEST_DIRS)

GDB_PORT=22576
GDBINIT=/tmp/b2g.gdbinit.$(shell whoami)
GDB=$(abspath toolchains/arm-linux-androideabi-4.6.3/linux-x86/bin/arm-linux-androideabi-gdb)
B2G_BIN=/system/b2g/b2g

.PHONY: forward-gdb-port
forward-gdb-port: adb-check-version
	$(ADB) forward tcp:$(GDB_PORT) tcp:$(GDB_PORT)

.PHONY: kill-gdb-server
kill-gdb-server:
	if [ -n "$(GDBSERVER_PID)" ]; then $(ADB) shell kill $(GDBSERVER_PID); fi

.PHONY: attach-gdb-server
attach-gdb-server: adb-check-version forward-gdb-port kill-gdb-server
	$(ADB) shell gdbserver :$(GDB_PORT) --attach $(B2G_PID) &
	sleep 1

.PHONY: gdb-init-file
SYMDIR=$(GONK_OBJDIR)/symbols
gdb-init-file:
	echo "set solib-absolute-prefix $(SYMDIR)" > $(GDBINIT)
	echo "set solib-search-path $(GECKO_OBJDIR)/dist/bin:$(GECKO_OBJDIR)/dist/lib:$(SYMDIR)/system/lib:$(SYMDIR)/system/lib/hw:$(SYMDIR)/system/lib/egl:$(and $(ANDROIDFS_DIR),$(ANDROIDFS_DIR)/symbols/system/lib:$(ANDROIDFS_DIR)/symbols/system/lib/hw:$(ANDROIDFS_DIR)/symbols/system/lib/egl)" >> $(GDBINIT)
	echo "target extended-remote :$(GDB_PORT)" >> $(GDBINIT)

.PHONY: attach-gdb
attach-gdb: attach-gdb-server gdb-init-file
	$(GDB) -x $(GDBINIT) $(GECKO_OBJDIR)/dist/bin/b2g

.PHONY: disable-auto-restart
disable-auto-restart: adb-check-version kill-b2g
	$(ADB) shell stop b2g

.PHONY: restore-auto-restart
restore-auto-restart: adb-check-version
	$(ADB) shell start b2g

.PHONY: run-gdb-server
run-gdb-server: adb-check-version forward-gdb-port kill-gdb-server disable-auto-restart
	$(ADB) shell LD_LIBRARY_PATH=/system/b2g gdbserver --multi :$(GDB_PORT) $(B2G_BIN) &
	sleep 1

.PHONY: run-gdb
run-gdb: run-gdb-server gdb-init-file
	$(GDB) -x $(GDBINIT) $(GECKO_OBJDIR)/dist/bin/b2g

PERF_B2G_SYMFS = /tmp/b2g_symfs_$(GONK)
RECORD_DURATION ?= 10

define PERF_REPORT # $(call PERF_REPORT,flags)
	$(ADB) shell perf record $(1) -o /data/local/perf.data sleep $(RECORD_DURATION)
	$(ADB) pull /data/local/perf.data .
	if [ "$(GONK)" == "galaxys2" ]; then \
	  perf report --symfs=$(PERF_B2G_SYMFS) --vmlinux=/vmlinux ; \
	else \
	  perf report --symfs=$(PERF_B2G_SYMFS) --kallsyms=$(PERF_B2G_SYMFS)/kallsyms ; \
	fi
endef

.PHONY: perf-create-symfs
perf-create-symfs:
	@if [ ! -d $(PERF_B2G_SYMFS) ]; then \
	  echo "Creating direcotry $(PERF_B2G_SYMFS) for symbols..." ; \
	  mkdir $(PERF_B2G_SYMFS) ; \
	  cp -pr $(GONK_OBJDIR)/system $(PERF_B2G_SYMFS)/system ; \
	  cp -pr $(GONK_OBJDIR)/symbols/system/. $(PERF_B2G_SYMFS)/system/. ; \
	  if [ "$(GONK)" == "galaxys2" ]; then \
	    cp -pr $(KERNEL_DIR)/vmlinux $(PERF_B2G_SYMFS)/. ; \
	  else \
	    $(ADB) pull /proc/kallsyms $(PERF_B2G_SYMFS)/. ; \
	  fi ; \
	  cp -p $(GECKO_OBJDIR)/dist/lib/*.so $(PERF_B2G_SYMFS)/system/b2g/. ; \
	  cp -p $(GECKO_OBJDIR)/dist/bin/b2g $(PERF_B2G_SYMFS)/system/b2g/. ; \
	fi

.PHONY: perf-clean-symfs
perf-clean-symfs:
	@echo "Removing directory for symbols..."
	@rm -rf $(PERF_B2G_SYMFS)

.PHONY: perf-top
perf-top:
	$(ADB) shell perf top

.PHONY: perf-top-b2g
perf-top-b2g:
	$(ADB) shell perf top -p $(B2G_PID)

.PHONY: perf-report
perf-report: perf-create-symfs
	$(call PERF_REPORT,-a)

.PHONY: perf-report-b2g
perf-report-b2g: perf-create-symfs
	$(call PERF_REPORT,-p $(B2G_PID))

.PHONY: perf-report-callgraph
perf-report-callgraph: perf-create-symfs
	$(call PERF_REPORT,-a -g)

.PHONY: perf-report-callgraph-b2g
perf-report-callgraph-b2g: perf-create-symfs
	$(call PERF_REPORT,-p $(B2G_PID) -g)


SYMBOLS_DIR := $(GONK_PATH)/out/target/product/$(GONK)/symbols
KERNEL_OBJ := $(GONK_PATH)/out/target/product/$(GONK)/obj/KERNEL_OBJ
.PHONY: op_setup op_start op_stop op_status op_shutdown op_pull op_show
op_setup:
	@$(ADB) wait-for-device
	@if [ "$(GONK)" == "galaxys2" ]; then \
	  $(ADB) shell opcontrol --setup; \
	  $(ADB) shell opcontrol --vmlinux=$(PWD)/$(KERNEL_DIR)/vmlinux; \
	  $(ADB) shell opcontrol --kernel-range=0x`$(ADB) shell cat /proc/kallsyms | grep ' _text' | cut -c 1-8`,0x`$(ADB) shell cat /proc/kallsyms | grep ' _etext' | cut -c 1-8`; \
	  $(ADB) shell opcontrol --event=CPU_CYCLES & \
	else \
	  $(ADB) shell opcontrol --vmlinux=$(PWD)/$(KERNEL_DIR)/vmlinux; \
	  $(ADB) shell opcontrol --kernel-range=0x`$(ADB) shell cat /proc/kallsyms | grep ' _text' | cut -c 1-8`,0x`$(ADB) shell cat /proc/kallsyms | grep ' _etext' | cut -c 1-8`;\
	  $(ADB) shell opcontrol --timer &\
	fi ; 
op_start:
	@echo "Start Profiling ..."
	@echo -e "You can use \033[31m\"make op_status\"\033[0m to check profiling status, \033[31m\"make op_stop\"\033[0m to stop profiling"
	@$(ADB) shell opcontrol --start
op_stop:
	@echo "Stop Profiling ..."
	@echo -e "You can use \033[31m\"make op_pull\"\033[0m to pull oprofile samples"
	@$(ADB) shell opcontrol --stop
	@$(ADB) shell opcontrol --dump
op_status:
	@$(ADB) shell opcontrol --status
op_reset:
	@$(ADB) shell opcontrol --reset
op_shutdown:
	@$(ADB) shell opcontrol --shutdown
op_pull:
	@echo "Pulling profiling log ..."
	@echo -e "You can use \033[31m\"make op_show\"\033[0m to list profiling result"
	@rm -rf oprofile
	@mkdir oprofile
	@$(ADB) pull /data/oprofile $(PWD)/oprofile/
	@cp -pr $(SYMBOLS_DIR) $(PWD)/oprofile/symbols
	@cp -pr $(GECKO_OBJDIR)/dist/b2g $(PWD)/oprofile/symbols
	@cp -p $(GECKO_OBJDIR)/dist/bin/b2g $(PWD)/oprofile/symbols/b2g/
	@cp -p $(GECKO_OBJDIR)/dist/lib/*.so $(PWD)/oprofile/symbols/b2g/
op_show:
	@echo "Processing profiling samples ..." 
	@echo -e "The profiling result is saved in your \033[31moprofile/oprofile.log\033[0m" 
	@touch $(PWD)/oprofile/oprofile.log    
	@opreport --session-dir=oprofile -p $(PWD)/oprofile/symbols -l
	@opreport --session-dir=oprofile -p $(PWD)/oprofile/symbols -l -o $(PWD)/oprofile/oprofile.log 2>/dev/null

TIMEZONE ?= $(shell date +%Z%:::z|tr +- -+)

.PHONY: update-time
update-time: adb
	@echo "|make update-time TIMEZONE=<zone>| to set timezone"
	$(ADB) wait-for-device
	$(ADB) shell toolbox date `date +%s`
	$(ADB) shell setprop persist.sys.timezone $(TIMEZONE)

VALGRIND_DIR=$(abspath $(GONK_BASE)/prebuilt/android-arm/valgrind)
.PHONY: install-valgrind
install-valgrind: disable-auto-restart
	$(ADB) remount
	$(ADB) push $(VALGRIND_DIR) /data/local/valgrind
	$(ADB) push $(GONK_OBJDIR)/symbols/system/bin/linker /system/bin/.
	$(ADB) push $(GONK_OBJDIR)/symbols/system/lib/libc.so /system/lib/.
	$(ADB) push $(GECKO_OBJDIR)/dist/lib/libxul.so /data/local/.
	$(ADB) shell rm /system/b2g/libxul.so
	$(ADB) shell ln -s /data/local/libxul.so /system/b2g/libxul.so

.PHONY: uninstall-valgrind
uninstall-valgrind: restore-auto-restart
	$(ADB) remount
	$(ADB) push $(GONK_OBJDIR)/system/bin/linker /system/bin/.
	$(ADB) push $(GONK_OBJDIR)/system/lib/libc.so /system/lib/.
	$(ADB) push $(GECKO_OBJDIR)/dist/b2g/libxul.so /system/b2g/.
	$(ADB) shell rm /data/local/libxul.so
	$(ADB) shell rm -rf /data/local/valgrind
