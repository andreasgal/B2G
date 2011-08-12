# To support gonk's build/envsetup.sh
SHELL = bash

.DEFAULT: build

UNAME=$(shell uname)
KERNEL=$(shell cat .selected-kernel)

ifeq ($(UNAME),Darwin)
TOOLCHAIN_HOST=darwin-x86
else
TOOLCHAIN_HOST=linux-x86
endif

TOOLCHAIN_PATH=./glue/gonk/prebuilt/$(TOOLCHAIN_HOST)/toolchain/arm-eabi-4.4.3/bin
KERNEL_PATH=./boot/kernel-android-$(KERNEL)

ifneq ($(UNAME),Darwin)
MAKEFLAGS = -j16
else
MAKEFLAGS =
endif

GONK = $(abspath glue/gonk)

define GONK_CMD # $(call GONK_CMD,cmd)
	cd $(GONK) && \
	. build/envsetup.sh && \
	lunch `cat .config` && \
	$(1)
endef

# Developers can use this to define convenience rules and set global variabls
# XXX for now, this is where to put ANDROID_SDK and ANDROID_NDK macros
-include local.mk

.PHONY: build
build: kernel gonk gecko

ifndef ANDROID_SDK
$(error Sorry, you need to set ANDROID_SDK in your environment to point at the top-level of the SDK install.  For now.)
endif

ifndef ANDROID_NDK
$(error Sorry, you need to set ANDROID_NDK in your environment to point at the top-level of the NDK install.  For now.)
endif

.PHONY: gecko
# XXX Hard-coded for prof-android target.  It would also be nice if
# client.mk understood the |package| target.
gecko:
	@export ANDROID_SDK=$(ANDROID_SDK) && \
	export ANDROID_NDK=$(ANDROID_NDK) && \
	make -C gecko -f client.mk -s $(MAKEFLAGS) && \
	make -C gecko/objdir-prof-android package

.PHONY: gonk
gonk: bootimg-hack geckoapk-hack
	@$(call GONK_CMD,make $(MAKEFLAGS))

.PHONY: kernel
# XXX Hard-coded for nexuss4g target
# XXX Hard-coded for gonk tool support
kernel:
	PATH="$$PATH:$(abspath $(TOOLCHAIN_PATH))" make -C $(KERNEL_PATH) $(MAKEFLAGS) ARCH=arm CROSS_COMPILE=arm-eabi-

.PHONY: clean
clean: clean-gecko clean-gonk clean-kernel

.PHONY: clean-gecko
clean-gecko:
	rm -rf gecko/objdir-prof-android

.PHONY: clean-gonk
clean-gonk:
	@$(call GONK_CMD,make clean)

.PHONY: clean-kernel
clean-kernel:
	@PATH="$$PATH:$(abspath $(TOOLCHAIN_PATH))" make -C $(KERNEL_PATH) ARCH=arm CROSS_COMPILE=arm-eabi- clean

.PHONY: config-galaxy-s2
config-galaxy-s2:
	@echo "galaxy-s2" > .selected-kernel
	@cp -p config/kernel-galaxy-s2 boot/kernel-android-galaxy-s2/.config

.PHONY: config-gecko-gonk
config-gecko-gonk:
	@cp -p config/gecko-prof-gonk gecko/.mozconfig

define INSTALL_NEXUS_S_BLOB # $(call INSTALL_BLOB,vendor,id)
	wget https://dl.google.com/dl/android/aosp/$(1)-crespo4g-grj90-$(2).tgz && \
	tar zxvf $(1)-crespo4g-grj90-$(2).tgz && \
	./extract-$(1)-crespo4g.sh && \
	rm $(1)-crespo4g-grj90-$(2).tgz extract-$(1)-crespo4g.sh
endef

.PHONY: config-nexuss4g
# XXX Hard-coded for nexuss4g target
config-nexuss4g: config-gecko-gonk
	@echo "samsung" > .selected-kernel
	@echo "" > .selected-kernel-config
	@cp -p config/kernel-nexuss4g boot/kernel-android-samsung/.config && \
	cd $(GONK) && \
	echo -n full_crespo4g-eng > .config && \
	$(call INSTALL_NEXUS_S_BLOB,broadcom,c4ec9a38) && \
	$(call INSTALL_NEXUS_S_BLOB,imgtec,a8e2ce86) && \
	$(call INSTALL_NEXUS_S_BLOB,nxp,9abcae18) && \
	$(call INSTALL_NEXUS_S_BLOB,samsung,9474e48f) && \
	$(call GONK_CMD,make signapk && vendor/samsung/crespo4g/reassemble-apks.sh)

.PHONY: flash
# XXX Hard-coded for nexuss4g target
flash: image
	@$(call GONK_CMD,adb reboot bootloader && fastboot flashall -w)

.PHONY: bootimg-hack
bootimg-hack: kernel
	cp -p boot/kernel-android-samsung/arch/arm/boot/zImage $(GONK)/device/samsung/crespo/kernel && \
	cp -p boot/kernel-android-samsung/drivers/net/wireless/bcm4329/bcm4329.ko $(GONK)/device/samsung/crespo/bcm4329.ko

# XXX Hard-coded for nexuss4g target
APP_OUT_DIR := $(GONK)/out/target/product/crespo4g/system/app

$(APP_OUT_DIR):
	mkdir -p $(APP_OUT_DIR)

.PHONY: geckoapk-hack
geckoapk-hack: gecko | $(APP_OUT_DIR)
# XXX disabled for the moment because fennec can't load itself when
# installed as a system app:
#   FATAL EXCEPTION: Thread-10
#   java.lang.UnsatisfiedLinkError: Couldn't load mozutils: findLibrary returned null
#   	at java.lang.Runtime.loadLibrary(Runtime.java:429)
#   	at java.lang.System.loadLibrary(System.java:554)
#   	at org.mozilla.gecko.GeckoAppShell.loadGeckoLibs(GeckoAppShell.java:274#  )
#   	at org.mozilla.gecko.GeckoApp$4.run(GeckoApp.java:249)
#   	at java.lang.Thread.run(Thread.java:1019)
#   Force finishing activity org.mozilla.fennec_unofficial/.App

#	cp -p gecko/objdir-prof-android/dist/fennec-*.apk $(APP_OUT_DIR)/Fennec.apk

.PHONY: install-gecko
install-gecko: gecko
	@adb install -r gecko/objdir-prof-android/dist/fennec-*.apk && \
	adb reboot

.PHONY: image
image: build
	@echo XXX stop overwriting the prebuilt nexuss4g kernel

.PHONY: unlock-bootloader
oem-unlock: gonk
	@$(call GONK_CMD,adb reboot bootloader && fastboot oem unlock)

.PHONY: sync
sync:
	@git submodule sync && \
	git submodule update --init && \
	git pull
