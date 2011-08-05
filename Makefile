# To support gonk's build/envsetup.sh
SHELL = bash

.DEFAULT: build

PARALLELISM = 16
GONK = $(abspath glue/gonk)

define GONK_CMD # $(call GONK_CMD,cmd)
	cd $(GONK) && \
	. build/envsetup.sh && \
	lunch `cat .config` && \
	$(1)
endef

.PHONY: build
build: kernel gonk gecko

check-sdk:
	@if [ -z "$$ANDROID_SDK" ]; then \
		echo 'Sorry, you need to set ANDROID_SDK in your environment to point at the top-level of the SDK install.  For now.'; exit 1; \
	fi
	@if [ -z "$$ANDROID_NDK" ]; then \
		echo 'Sorry, you need to set ANDROID_NDK in your environment to point at the top-level of the NDK install.  For now.'; exit 1; \
	fi

.PHONY: gecko
gecko: check-sdk
	@make -C gecko -f client.mk -s -j$(PARALLELISM)

.PHONY: gonk
gonk: bootimg-hack
	@$(call GONK_CMD,make -j$(PARALLELISM))

.PHONY: kernel
# XXX Hard-coded for nexuss4g target
# XXX Hard-coded for gonk tool support
kernel:
	@PATH="$$PATH:$(abspath ./glue/gonk/prebuilt/linux-x86/toolchain/arm-eabi-4.4.3/bin)" make -C boot/kernel-android-samsung -j$(PARALLELISM) ARCH=arm CROSS_COMPILE=arm-eabi-

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
	@PATH="$$PATH:$(abspath ./glue/gonk/prebuilt/linux-x86/toolchain/arm-eabi-4.4.3/bin)" make -C boot/kernel-android-samsung ARCH=arm CROSS_COMPILE=arm-eabi- clean

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
	cp boot/kernel-android-samsung/arch/arm/boot/zImage $(GONK)/device/samsung/crespo/kernel && \
	cp boot/kernel-android-samsung/drivers/net/wireless/bcm4329/bcm4329.ko $(GONK)/device/samsung/crespo/bcm4329.ko

.PHONY: image
image: build
	@echo XXX stop overwriting the prebuilt nexuss4g kernel

.PHONY: sync
sync:
	@git submodule sync && \
	git submodule update --init && \
	git pull
