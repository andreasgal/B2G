# To support gonk's build/envsetup.sh
SHELL = bash

-include .config.mk

.DEFAULT: build

MAKE_FLAGS = -j16

HEIMDALL ?= heimdall
TOOLCHAIN_HOST = linux-x86
TOOLCHAIN_PATH = ./glue/gonk/prebuilt/$(TOOLCHAIN_HOST)/toolchain/arm-eabi-4.4.3/bin
KERNEL_PATH = ./boot/kernel-android-$(KERNEL)

GONK_PATH = $(abspath glue/gonk)
GONK_TARGET = full_$(GONK)-eng

define GONK_CMD # $(call GONK_CMD,cmd)
	cd $(GONK_PATH) && \
	. build/envsetup.sh && \
	lunch $(GONK_TARGET) && \
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
	make -C gecko -f client.mk -s $(MAKE_FLAGS) && \
	make -C gecko/objdir-prof-android package

.PHONY: gonk
gonk: bootimg-hack geckoapk-hack
	@$(call GONK_CMD,make $(MAKE_FLAGS))

.PHONY: kernel
# XXX Hard-coded for nexuss4g target
# XXX Hard-coded for gonk tool support
kernel:
	@PATH="$$PATH:$(abspath $(TOOLCHAIN_PATH))" make -C $(KERNEL_PATH) $(MAKE_FLAGS) ARCH=arm CROSS_COMPILE=arm-eabi-

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
config-galaxy-s2: config-gecko-gonk
	@echo "KERNEL = galaxy-s2" > .config.mk && \
	echo "GONK = galaxys2" >> .config.mk && \
	cp -p config/kernel-galaxy-s2 boot/kernel-android-galaxy-s2/.config && \
	cd $(GONK_PATH)/device/samsung/galaxys2/ && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

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
	@echo "KERNEL = samsung" > .config.mk && \
	echo "GONK = crespo4g" >> .config.mk && \
	cp -p config/kernel-nexuss4g boot/kernel-android-samsung/.config && \
	cd $(GONK_PATH) && \
	$(call INSTALL_NEXUS_S_BLOB,broadcom,c4ec9a38) && \
	$(call INSTALL_NEXUS_S_BLOB,imgtec,a8e2ce86) && \
	$(call INSTALL_NEXUS_S_BLOB,nxp,9abcae18) && \
	$(call INSTALL_NEXUS_S_BLOB,samsung,9474e48f) && \
	make -C $(CURDIR) nexuss4g-postconfig

.PHONY: nexuss4g-postconfig
nexuss4g-postconfig:
	$(call GONK_CMD,make signapk && vendor/samsung/crespo4g/reassemble-apks.sh)

.PHONY: flash
# XXX Using target-specific targets for the time being.  fastboot is
# great, but the sgs2 doesn't support it.  Eventually we should find a
# lowest-common-denominator solution.
flash: flash-$(GONK)

.PHONY: flash-crespo4g
flash-crespo4g: image
	@$(call GONK_CMD,adb reboot bootloader && fastboot flashall -w)

.PHONY: flash-galaxys2
flash-galaxys2: image
	@adb reboot download && \
	sleep 20 && \
	$(HEIMDALL) flash --factoryfs $(GONK_PATH)/out/target/product/galaxys2/system.img

.PHONY: bootimg-hack
bootimg-hack: kernel
ifeq (samsung,$(KERNEL))
	cp -p boot/kernel-android-samsung/arch/arm/boot/zImage $(GONK_PATH)/device/samsung/crespo/kernel && \
	cp -p boot/kernel-android-samsung/drivers/net/wireless/bcm4329/bcm4329.ko $(GONK_PATH)/device/samsung/crespo/bcm4329.ko
endif

# XXX Hard-coded for nexuss4g target
APP_OUT_DIR := $(GONK_PATH)/out/target/product/crespo4g/system/app

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
	@adb install -r gecko/objdir-prof-android/dist/b2g-*.apk && \
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
