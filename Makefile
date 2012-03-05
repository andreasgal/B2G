# To support gonk's build/envsetup.sh
SHELL = bash

GIT ?= git
HG ?= hg

-include local.mk
-include .config.mk

.DEFAULT: build

MAKE_FLAGS ?= -j16
GONK_MAKE_FLAGS ?=

FASTBOOT ?= $(abspath glue/gonk/out/host/linux-x86/bin/fastboot)
HEIMDALL ?= heimdall
TOOLCHAIN_HOST = linux-x86
TOOLCHAIN_PATH = ./glue/gonk/prebuilt/$(TOOLCHAIN_HOST)/toolchain/arm-eabi-4.4.3/bin

GAIA_PATH ?= $(abspath gaia)
GECKO_PATH ?= $(abspath gecko)
GONK_PATH = $(abspath glue/gonk)

TEST_DIRS = $(abspath $(GAIA_PATH)/tests) $(abspath marionette/marionette/tests/unit-tests.ini)

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

# This path includes tools to simulate JDK tools.  Gonk would check
# version of JDK.  These fake tools do nothing but print out version
# number to stop gonk from error.
FAKE_JDK_PATH ?= $(abspath $(GONK_PATH)/device/gonk-build-hack/fake-jdk-tools)

define GONK_CMD # $(call GONK_CMD,cmd)
	cd $(GONK_PATH) && \
	. build/envsetup.sh && \
	lunch $(GONK_TARGET) && \
	export USE_CCACHE="yes" && \
	export PATH=$$PATH:$(FAKE_JDK_PATH) && \
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
ADB := $(abspath glue/gonk/out/host/linux-x86/bin/adb)

B2G_PID=$(shell $(ADB) shell toolbox ps | grep "b2g" | awk '{ print $$2; }')
GDBSERVER_PID=$(shell $(ADB) shell toolbox ps | grep "gdbserver" | awk '{ print $$2; }')

.PHONY: build
build: gecko-install-hack
	$(MAKE) gonk

ifeq (qemu,$(KERNEL))
build: kernel bootimg-hack
endif

KERNEL_DIR = boot/kernel-android-$(KERNEL)
GECKO_OBJDIR = $(GECKO_PATH)/objdir-prof-gonk
GONK_OBJDIR=$(abspath ./glue/gonk/out/target/product/$(GONK))

define GECKO_BUILD_CMD
	export MAKE_FLAGS=$(MAKE_FLAGS) && \
	export CONFIGURE_ARGS="$(GECKO_CONFIGURE_ARGS)" && \
	export GONK_PRODUCT="$(GONK)" && \
	export GONK_PATH="$(GONK_PATH)" && \
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
gonk: gaia-hack
	@$(call DEP_CHECK,$(GONK_PATH)/out/.b2g-build-done,glue/gonk, \
	    $(call GONK_CMD,$(MAKE) $(MAKE_FLAGS) $(GONK_MAKE_FLAGS)) ; \
	    $(if $(filter qemu,$(KERNEL)), \
		cp $(GONK_PATH)/system/core/rootdir/init.rc.gonk \
		    $(GONK_PATH)/out/target/product/$(GONK)/root/init.rc))

.PHONY: kernel
# XXX Hard-coded for nexuss4g target
# XXX Hard-coded for gonk tool support
kernel:
	@$(call DEP_CHECK,$(KERNEL_PATH)/.b2g-build-done,$(KERNEL_PATH),\
	    $(if $(filter galaxy-s2,$(KERNEL)), \
		(rm -rf boot/initramfs && \
		    cd boot/clockworkmod_galaxys2_initramfs && \
		    $(GIT) checkout-index -a -f --prefix ../initramfs/); \
		PATH="$$PATH:$(abspath $(TOOLCHAIN_PATH))" \
		    $(MAKE) -C $(KERNEL_PATH) $(MAKE_FLAGS) ARCH=arm \
		    CROSS_COMPILE="$(CCACHE) arm-eabi-"; \
		find "$(KERNEL_DIR)" -name "*.ko" | \
		    xargs -I MOD cp MOD "$(PWD)/boot/initramfs/lib/modules"; \
	    ) \
	    PATH="$$PATH:$(abspath $(TOOLCHAIN_PATH))" \
		$(MAKE) -C $(KERNEL_PATH) $(MAKE_FLAGS) ARCH=arm \
		CROSS_COMPILE="$(CCACHE) arm-eabi-"; )

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
config-galaxy-s2: config-gecko adb-check-version $(APNS_CONF)
	@echo "KERNEL = galaxy-s2" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-galaxy-s2" >> .config.mk && \
	echo "GONK = galaxys2" >> .config.mk && \
	export PATH=$$PATH:$$(dirname $(ADB)) && \
	cp -p config/kernel-galaxy-s2 boot/kernel-android-galaxy-s2/.config && \
	cd $(GONK_PATH)/device/samsung/galaxys2/ && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

.PHONY: config-maguro
config-maguro: config-gecko adb-check-version $(APNS_CONF)
	@echo "KERNEL = msm" > .config.mk && \
        echo "KERNEL_PATH = ./boot/msm" >> .config.mk && \
	echo "GONK = maguro" >> .config.mk && \
	export PATH=$$PATH:$$(dirname $(ADB)) && \
	cd $(GONK_PATH)/device/toro/maguro && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

# Hack!  Upstream boot/msm is RO at the moment and forking isn't
# a nice alternative at the moment...
.patches.applied:
	cd boot/msm && $(GIT) apply $(abspath glue/patch)/yaffs_vfs.patch
	touch $@

.PHONY: config-akami
config-akami: .patches.applied config-gecko $(APNS_CONF)
	@echo "KERNEL = msm" > .config.mk && \
        echo "KERNEL_PATH = ./boot/msm" >> .config.mk && \
	echo "GONK = akami" >> .config.mk && \
	cd $(GONK_PATH)/device/toro/akami && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

.PHONY: config-gecko
config-gecko:
	@ln -sf $(PWD)/config/gecko-prof-gonk $(GECKO_PATH)/mozconfig

DOWNLOAD_PATH=$(GONK_PATH)/download

%.tgz:
	mkdir -p $(DOWNLOAD_PATH)
	cd $(DOWNLOAD_PATH) && wget https://dl.google.com/dl/android/aosp/$(notdir $@)

NEXUS_S_BUILD = grj90

$(DOWNLOAD_PATH)/extract-broadcom-crespo4g.sh: $(DOWNLOAD_PATH)/broadcom-crespo4g-$(NEXUS_S_BUILD)-c4ec9a38.tgz
	cd $(DOWNLOAD_PATH) && tar zxvf $< && cd $(GONK_PATH) && $@

$(DOWNLOAD_PATH)/extract-imgtec-crespo4g.sh: $(DOWNLOAD_PATH)/imgtec-crespo4g-$(NEXUS_S_BUILD)-a8e2ce86.tgz
	cd $(DOWNLOAD_PATH) && tar zxvf $< && cd $(GONK_PATH) && $@

$(DOWNLOAD_PATH)/extract-nxp-crespo4g.sh: $(DOWNLOAD_PATH)/nxp-crespo4g-$(NEXUS_S_BUILD)-9abcae18.tgz
	cd $(DOWNLOAD_PATH) && tar zxvf $< && cd $(GONK_PATH) && $@

$(DOWNLOAD_PATH)/extract-samsung-crespo4g.sh: $(DOWNLOAD_PATH)/samsung-crespo4g-$(NEXUS_S_BUILD)-9474e48f.tgz
	cd $(DOWNLOAD_PATH) && tar zxvf $< && cd $(GONK_PATH) && $@

$(DOWNLOAD_PATH)/extract-broadcom-crespo.sh: $(DOWNLOAD_PATH)/broadcom-crespo-$(NEXUS_S_BUILD)-fb8eed0c.tgz
	cd $(DOWNLOAD_PATH) && tar zxvf $< && cd $(GONK_PATH) && $@

$(DOWNLOAD_PATH)/extract-imgtec-crespo.sh: $(DOWNLOAD_PATH)/imgtec-crespo-$(NEXUS_S_BUILD)-f03db3d1.tgz
	cd $(DOWNLOAD_PATH) && tar zxvf $< && cd $(GONK_PATH) && $@ && rm -rf $(GONK_PATH)/vendor/imgtec/crespo/overlay

$(DOWNLOAD_PATH)/extract-nxp-crespo.sh: $(DOWNLOAD_PATH)/nxp-crespo-$(NEXUS_S_BUILD)-bcb793da.tgz
	cd $(DOWNLOAD_PATH) && tar zxvf $< && cd $(GONK_PATH) && $@

$(DOWNLOAD_PATH)/extract-samsung-crespo.sh: $(DOWNLOAD_PATH)/samsung-crespo-$(NEXUS_S_BUILD)-c6e00e6a.tgz
	cd $(DOWNLOAD_PATH) && tar zxvf $< && cd $(GONK_PATH) && $@

.PHONY: blobs-nexuss4g
blobs-nexuss4g: $(DOWNLOAD_PATH)/extract-broadcom-crespo4g.sh $(DOWNLOAD_PATH)/extract-imgtec-crespo4g.sh $(DOWNLOAD_PATH)/extract-nxp-crespo4g.sh $(DOWNLOAD_PATH)/extract-samsung-crespo4g.sh

.PHONY: blobs-nexuss
blobs-nexuss: $(DOWNLOAD_PATH)/extract-broadcom-crespo.sh $(DOWNLOAD_PATH)/extract-imgtec-crespo.sh $(DOWNLOAD_PATH)/extract-nxp-crespo.sh $(DOWNLOAD_PATH)/extract-samsung-crespo.sh
	mkdir -p $(GONK_PATH)/packages/wallpapers/LivePicker
	touch $(GONK_PATH)/packages/wallpapers/LivePicker/android.software.live_wallpaper.xml

.PHONY: config-nexuss4g
config-nexuss4g: blobs-nexuss4g config-gecko $(APNS_CONF)
	@echo "KERNEL = samsung" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-samsung" >> .config.mk && \
	echo "GONK = crespo4g" >> .config.mk && \
	cp -p config/kernel-nexuss4g boot/kernel-android-samsung/.config && \
	echo OK

.PHONY: config-nexuss
config-nexuss: blobs-nexuss config-gecko $(APNS_CONF)
	@echo "KERNEL = samsung" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-samsung" >> .config.mk && \
	echo "GONK = crespo" >> .config.mk && \
	cp -p config/kernel-nexuss4g boot/kernel-android-samsung/.config && \
	echo OK

.PHONY: config-qemu
config-qemu: config-gecko
	@echo "KERNEL = qemu" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-qemu" >> .config.mk && \
	echo "GONK = generic" >> .config.mk && \
	echo "GONK_TARGET = generic-eng" >> .config.mk && \
	echo "GONK_MAKE_FLAGS = TARGET_ARCH_VARIANT=armv7-a" >> .config.mk && \
	$(MAKE) -C boot/kernel-android-qemu ARCH=arm goldfish_armv7_defconfig && \
	( [ -e $(GONK_PATH)/device/qemu ] || \
		mkdir $(GONK_PATH)/device/qemu ) && \
	echo OK

.PHONY: flash
# XXX Using target-specific targets for the time being.  fastboot is
# great, but the sgs2 doesn't support it.  Eventually we should find a
# lowest-common-denominator solution.
flash: flash-$(GONK)

# flash-only targets are the same as flash targets, except that they don't
# depend on building the image.

.PHONY: flash-only
flash-only: flash-only-$(GONK)

.PHONY: flash-crespo
flash-crespo: flash-crespo4g

.PHONY: flash-only-crespo
flash-only-crespo: flash-only-crespo4g

.PHONY: flash-crespo4g
flash-crespo4g: image adb-check-version
	@$(call GONK_CMD,$(ADB) reboot bootloader && fastboot flashall -w)

.PHONY: flash-only-crespo4g
flash-only-crespo4g: adb-check-version
	@$(call GONK_CMD,$(ADB) reboot bootloader && fastboot flashall -w)

define FLASH_GALAXYS2_CMD
$(ADB) reboot download 
sleep 20
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
flash-only-maguro: flash-only-toro

.PHONY: flash-akami
flash-akami: image flash-only-akami

.PHONY: flash-only-akami
flash-only-akami: flash-only-toro

.PHONY: flash-only-toro
flash-only-toro:
	@$(call GONK_CMD, \
	$(ADB) reboot bootloader && \
	$(FASTBOOT) devices && \
	$(FASTBOOT) erase userdata && \
	$(FASTBOOT) flash userdata ./out/target/product/$(GONK)/userdata.img && \
	$(FASTBOOT) flashall)

.PHONY: bootimg-hack
bootimg-hack: kernel-$(KERNEL)

.PHONY: kernel-samsung
kernel-samsung:
	cp -p boot/kernel-android-samsung/arch/arm/boot/zImage $(GONK_PATH)/device/samsung/crespo/kernel && \
	cp -p boot/kernel-android-samsung/drivers/net/wireless/bcm4329/bcm4329.ko $(GONK_PATH)/device/samsung/crespo/bcm4329.ko

.PHONY: kernel-qemu
kernel-qemu:
	cp -p boot/kernel-android-qemu/arch/arm/boot/zImage \
		$(GONK_PATH)/device/qemu/kernel

kernel-%:
	@

OUT_DIR := $(GONK_PATH)/out/target/product/$(GONK)/system
DATA_OUT_DIR := $(GONK_PATH)/out/target/product/$(GONK)/data
APP_OUT_DIR := $(OUT_DIR)/app

$(APP_OUT_DIR):
	mkdir -p $(APP_OUT_DIR)

.PHONY: gecko-install-hack
gecko-install-hack: gecko
	rm -rf $(OUT_DIR)/b2g
	mkdir -p $(OUT_DIR)/lib
	# Extract the newest tarball in the gecko objdir.
	( cd $(OUT_DIR) && \
	  tar xvfz $$(ls -t $(GECKO_OBJDIR)/dist/b2g-*.tar.gz | head -n1) )
	find $(GONK_PATH)/out -iname "*.img" | xargs rm -f
	@$(call GONK_CMD,$(MAKE) $(MAKE_FLAGS) $(GONK_MAKE_FLAGS) systemimage-nodeps)

.PHONY: gaia-hack
gaia-hack: gaia
	rm -rf $(OUT_DIR)/home
	mkdir -p $(OUT_DIR)/home
	mkdir -p $(DATA_OUT_DIR)/local
	cp -r $(GAIA_PATH)/* $(DATA_OUT_DIR)/local
	rm -rf $(OUT_DIR)/b2g/defaults/profile
	mkdir -p $(OUT_DIR)/b2g/defaults
	cp -r $(GAIA_PATH)/profile $(OUT_DIR)/b2g/defaults

.PHONY: install-gecko
install-gecko: gecko-install-hack adb-check-version
	$(ADB) remount
	$(ADB) push $(OUT_DIR)/b2g /system/b2g

.PHONY: install-gecko-only
install-gecko-only:
	$(ADB) remount
	$(ADB) push $(OUT_DIR)/b2g /system/b2g

# The sad hacks keep piling up...  We can't set this up to be
# installed as part of the data partition because we can't flash that
# on the sgs2.
PROFILE := $$($(ADB) shell ls -d /data/b2g/mozilla/*.default | tr -d '\r')
PROFILE_DATA := $(GAIA_PATH)/profile
.PHONY: install-gaia
install-gaia: adb-check-version
	@for file in $$(ls $(PROFILE_DATA)); \
	do \
		data=$${file##*/}; \
		echo Copying $$data; \
		$(ADB) shell rm -r $(PROFILE)/$$data; \
		$(ADB) push $(GAIA_PATH)/profile/$$data $(PROFILE)/$$data; \
	done
	@for i in $$(ls $(GAIA_PATH)); do $(ADB) push $(GAIA_PATH)/$$i /data/local/$$i; done

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
	frameworks/base/include \
	frameworks/base/native/include \
	frameworks/base/opengl/include \
	frameworks/base/services/sensorservice \
	hardware/libhardware/include \
	hardware/libhardware_legacy/include \
	ndk/sources/cxx-stl/system/include \
	ndk/sources/cxx-stl/stlport/stlport \
	out/target/product/$(GONK)/obj/lib \
	prebuilt/ndk/android-ndk-r4/platforms/android-8/arch-arm \
	prebuilt/$(TOOLCHAIN_TARGET)/toolchain/arm-eabi-4.4.3 \
	system/core/include

# Toolchain versions are numbered consecutively.
TOOLCHAIN_VERSION := 0
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
	cd marionette/marionette && \
	sh venv_test.sh `which python` --emulator --homedir=$(abspath .) --type=b2g $(TEST_DIRS)

GDB_PORT=22576
GDBINIT=/tmp/b2g.gdbinit.$(shell whoami)
GDB=$(abspath glue/gonk/prebuilt/linux-x86/tegra-gdb/arm-eabi-gdb)
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
	echo "target remote :$(GDB_PORT)" >> $(GDBINIT)

.PHONY: attach-gdb
attach-gdb: attach-gdb-server gdb-init-file
	$(GDB) -x $(GDBINIT) $(GECKO_OBJDIR)/dist/bin/b2g

.PHONY: disable-auto-restart
disable-auto-restart: adb-check-version kill-b2g
	$(ADB) remount
	$(ADB) shell mv $(B2G_BIN) $(B2G_BIN).d

.PHONY: restore-auto-restart
restore-auto-restart: adb-check-version
	$(ADB) remount
	$(ADB) shell mv $(B2G_BIN).d $(B2G_BIN)

.PHONY: run-gdb-server
run-gdb-server: adb-check-version forward-gdb-port kill-gdb-server disable-auto-restart
	$(ADB) shell gdbserver :$(GDB_PORT) $(B2G_BIN).d &
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


HOME_DIR = $(shell pwd)
SYMBOLS_DIR := $(GONK_PATH)/out/target/product/$(GONK)/symbols
KERNEL_OBJ := $(GONK_PATH)/out/target/product/$(GONK)/obj/KERNEL_OBJ
.PHONY: op_setup op_start op_stop op_status op_shutdown op_pull op_show
op_setup:
	@$(ADB) remount /system	
	@echo "opcontrol --setup" > opsetup
	@if [ "$(GONK)" == "galaxys2" ]; then \
          echo "opcontrol --vmlinux=$(HOME_DIR)/$(KERNEL_DIR)/vmlinux --kernel-range=0x`$(ADB) shell cat /proc/kallsyms | grep ' _text' | cut -c 1-8`,0x`$(ADB) shell cat /proc/kallsyms | grep ' _etext' | cut -c 1-8` --event=CPU_CYCLES" >> opsetup ; \
	else \
          echo "opcontrol --vmlinux=$(KERNEL_OBJ)/vmlinux --kernel-range=0x`$(ADB) shell cat /proc/kallsyms | grep ' _text' | cut -c 1-8`,0x`$(ADB) shell cat /proc/kallsyms | grep ' _etext' | cut -c 1-8` --timer" > opsetup; \
	fi ; 	
	@$(ADB) push opsetup /system/xbin
	@$(ADB) shell chmod 755 /system/xbin/opsetup
	@echo "#! /bin/bash" > oppull
	@echo "rm -rf oprofile" >> oppull
	@echo "mkdir oprofile" >> oppull
	@echo "$(ADB) pull /data/oprofile $(HOME_DIR)/oprofile/" >> oppull
	@chmod +x oppull
	@$(ADB) shell opsetup > /dev/null 2>&1 &
op_start:
	@echo "Start Profiling ..."
	@echo -e "You can use \033[31m\"make op_status\"\033[0m to check profiling status, \033[31m\"make op_stop\"\033[0m to stop profiling"
	@$(ADB) shell opcontrol --start
op_stop:
	@echo "Stop Profiling ..."
	@echo -e "You can use \033[31m\"make op_pull\"\033[0m to pull oprofile samples"
	@$(ADB) shell opcontrol --stop
op_status:
	@$(ADB) shell opcontrol --status
op_shutdown:
	@$(ADB) shell opcontrol --shutdown
op_pull:
	@echo "Pulling profiling log ..."
	@echo -e "You can use \033[31m\"make op_show\"\033[0m to list profiling result"
	@./oppull
	@cp -pr $(SYMBOLS_DIR) $(HOME_DIR)/oprofile/symbols
	@cp -pr $(GECKO_OBJDIR)/dist/b2g $(HOME_DIR)/oprofile/symbols
	@cp -p $(GECKO_OBJDIR)/dist/bin/b2g $(HOME_DIR)/oprofile/symbols/b2g/
	@cp -p $(GECKO_OBJDIR)/dist/lib/*.so $(HOME_DIR)/oprofile/symbols/b2g/
op_show:
	@echo "Processing profiling samples ..." 
	@echo -e "The profiling result is saved in your \033[31moprofile/oprofile.log\033[0m" 
	@touch $(HOME_DIR)/oprofile/oprofile.log    
	@opreport --session-dir=oprofile -p $(HOME_DIR)/oprofile/symbols -l
	@opreport --session-dir=oprofile -p $(HOME_DIR)/oprofile/symbols -l -o $(HOME_DIR)/oprofile/oprofile.log 2>/dev/null

TIMEZONE ?= Europe/Madrid

.PHONY: update-time
update-time: adb
	@echo "|make update-time TIMEZONE=<zone>| to set timezone"
	$(ADB) wait-for-device
	$(ADB) shell toolbox date `date +%s`
	$(ADB) shell setprop persist.sys.timezone $(TIMEZONE)

VALGRIND_DIR=$(abspath glue/gonk/prebuilt/android-arm/valgrind)
.PHONY: install-valgrind
install-valgrind: disable-auto-restart
	$(ADB) remount
	$(ADB) push $(VALGRIND_DIR) /data/local/valgrind
	$(ADB) push $(GONK_OBJDIR)/symbols/system/bin/linker /system/bin/.
	$(ADB) push $(GONK_OBJDIR)/symbols/system/lib/libc.so /system/lib/.
	$(ADB) push $(GECKO_OBJDIR)/dist/lib/libxul.so /data/local/.
	$(ADB) shell rm /system/b2g/libxul.so
	$(ADB) shell ln -s /data/local/libxul.so /system/b2g/.

.PHONY: uninstall-valgrind
uninstall-valgrind: restore-auto-restart
	$(ADB) remount
	$(ADB) push $(GONK_OBJDIR)/system/bin/linker /system/bin/.
	$(ADB) push $(GONK_OBJDIR)/system/lib/libc.so /system/lib/.
	$(ADB) push $(GECKO_OBJDIR)/dist/b2g/libxul.so /system/b2g/.
	$(ADB) shell rm /data/local/libxul.so
	$(ADB) shell rm -rf /data/local/valgrind
