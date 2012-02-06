# To support gonk's build/envsetup.sh
SHELL = bash

-include local.mk
-include .config.mk

.DEFAULT: build

MAKE_FLAGS ?= -j16
GONK_MAKE_FLAGS ?=

FASTBOOT ?= $(abspath glue/gonk/out/host/linux-x86/bin/fastboot)
HEIMDALL ?= heimdall
TOOLCHAIN_HOST = linux-x86
TOOLCHAIN_PATH = ./glue/gonk/prebuilt/$(TOOLCHAIN_HOST)/toolchain/arm-eabi-4.4.3/bin

GONK_PATH = $(abspath glue/gonk)

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

GECKO_PATH ?= $(abspath gecko)

ANDROID_SDK_PLATFORM ?= android-13
GECKO_CONFIGURE_ARGS ?=

# |make STOP_DEPENDENCY_CHECK=true| to stop dependency checking
STOP_DEPENDENCY_CHECK ?= true

define SUBMODULES
	cat .gitmodules |grep path|awk -- '{print $$3;}'
endef

define DEP_LIST_GIT_FILES
git ls-files | xargs -d '\n' stat -c '%n:%Y' --; \
git ls-files -o -X .gitignore | xargs -d '\n' stat -c '%n:%Y' --
endef

define DEP_LIST_HG_FILES
hg locate | xargs -d '\n' stat -c '%n:%Y' --
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

.PHONY: build
build: gecko gecko-install-hack gonk

ifeq (qemu,$(KERNEL))
build: kernel bootimg-hack
endif

KERNEL_DIR = boot/kernel-android-$(KERNEL)
GECKO_OBJDIR = $(GECKO_PATH)/objdir-prof-gonk

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
		PATH="$$PATH:$(abspath $(TOOLCHAIN_PATH))" \
		    $(MAKE) -C $(KERNEL_PATH) $(MAKE_FLAGS) ARCH=arm \
		    CROSS_COMPILE="$(CCACHE) arm-eabi-" modules; \
		(rm -rf boot/initramfs && \
		    cd boot/clockworkmod_galaxys2_initramfs && \
		    git checkout-index -a -f --prefix ../initramfs/); \
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
	git submodule foreach 'git clean -dfx' && \
	git submodule foreach 'git reset --hard' && \
	git clean -dfx && \
	git reset --hard

.PHONY: config-galaxy-s2
config-galaxy-s2: config-gecko adb-check-version
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
config-maguro: config-gecko adb-check-version
	@echo "KERNEL = msm" > .config.mk && \
        echo "KERNEL_PATH = ./boot/msm" >> .config.mk && \
	echo "GONK = maguro" >> .config.mk && \
	export PATH=$$PATH:$$(dirname $(ADB)) && \
	cd $(GONK_PATH)/device/toro/maguro && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

.PHONY: config-akami
config-akami: config-gecko
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

%.tgz:
	wget https://dl.google.com/dl/android/aosp/$@

NEXUS_S_BUILD = grj90
extract-broadcom-crespo4g.sh: broadcom-crespo4g-$(NEXUS_S_BUILD)-c4ec9a38.tgz
	tar zxvf $< && ./$@
extract-imgtec-crespo4g.sh: imgtec-crespo4g-$(NEXUS_S_BUILD)-a8e2ce86.tgz
	tar zxvf $< && ./$@
extract-nxp-crespo4g.sh: nxp-crespo4g-$(NEXUS_S_BUILD)-9abcae18.tgz
	tar zxvf $< && ./$@
extract-samsung-crespo4g.sh: samsung-crespo4g-$(NEXUS_S_BUILD)-9474e48f.tgz
	tar zxvf $< && ./$@

.PHONY: blobs-nexuss4g
blobs-nexuss4g: extract-broadcom-crespo4g.sh extract-imgtec-crespo4g.sh extract-nxp-crespo4g.sh extract-samsung-crespo4g.sh

.PHONY: config-nexuss4g
config-nexuss4g: blobs-nexuss4g config-gecko
	@echo "KERNEL = samsung" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-samsung" >> .config.mk && \
	echo "GONK = crespo4g" >> .config.mk && \
	cp -p config/kernel-nexuss4g boot/kernel-android-samsung/.config && \
	$(MAKE) -C $(CURDIR) nexuss4g-postconfig

.PHONY: nexuss4g-postconfig
nexuss4g-postconfig:
	$(call GONK_CMD,$(MAKE) signapk && vendor/samsung/crespo4g/reassemble-apks.sh)

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
	adb reboot bootloader && \
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
	@$(call GONK_CMD,make $(MAKE_FLAGS) $(GONK_MAKE_FLAGS) systemimage-nodeps)

.PHONY: gaia-hack
gaia-hack: gaia
	rm -rf $(OUT_DIR)/home
	mkdir -p $(OUT_DIR)/home
	cp -r gaia/* $(OUT_DIR)/home
	rm -rf $(OUT_DIR)/b2g/defaults/profile
	mkdir -p $(OUT_DIR)/b2g/defaults
	cp -r gaia/profile $(OUT_DIR)/b2g/defaults

.PHONY: install-gecko
install-gecko: gecko-install-hack adb-check-version
	@$(ADB) shell mount -o remount,rw /system && \
	$(ADB) push $(OUT_DIR)/b2g /system/b2g

# The sad hacks keep piling up...  We can't set this up to be
# installed as part of the data partition because we can't flash that
# on the sgs2.
PROFILE := $$($(ADB) shell ls -d /data/b2g/mozilla/*.default | tr -d '\r')
PROFILE_DATA := gaia/profile
.PHONY: install-gaia
install-gaia: adb-check-version
	@for file in $$(ls $(PROFILE_DATA)); \
	do \
		data=$${file##*/}; \
		echo Copying $$data; \
		$(ADB) shell rm -r $(PROFILE)/$$data; \
		$(ADB) push gaia/profile/$$data $(PROFILE)/$$data; \
	done
	@for i in $$(ls gaia); do $(ADB) push gaia/$$i /data/local/$$i; done

.PHONY: image
image: build
	@echo XXX stop overwriting the prebuilt nexuss4g kernel

.PHONY: unlock-bootloader
unlock-bootloader: adb-check-version
	@$(call GONK_CMD,$(ADB) reboot bootloader && fastboot oem unlock)

# Kill the b2g process on the device.
.PHONY: kill-b2g
kill-b2g: adb-check-version
	$(ADB) shell killall b2g

.PHONY: sync
sync:
	git pull origin master
	git submodule sync
	git submodule update --init

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
	cp -R gaia/tests $(PKG_DIR)/gaia
	cd $(PKG_DIR) && tar -czvf qemu_package.tar.gz qemu gaia

$(ADB):
	@$(call GONK_CMD,make adb)

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
