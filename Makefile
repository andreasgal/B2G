# To support gonk's build/envsetup.sh
SHELL = bash

.PHONY: all build* check-sdk clean* config* flash image sync
.DEFAULT: build

PARALLELISM = 16
GONK = glue/gonk

define GONK_CMD # $(call GONK_CMD,cmd)
	@cd $(GONK) && \
	. build/envsetup.sh && \
	lunch `cat .config` && \
	$(1)
endef

build: build-kernel build-gonk build-gecko

check-sdk:
	@if [ -z "$$ANDROID_SDK" ]; then \
		echo 'Sorry, you need to set ANDROID_SDK in your environment to point at the top-level of the SDK install.  For now.'; exit 1; \
	fi
	@if [ -z "$$ANDROID_NDK" ]; then \
		echo 'Sorry, you need to set ANDROID_NDK in your environment to point at the top-level of the NDK install.  For now.'; exit 1; \
	fi

build-gecko: check-sdk
	@make -C gecko -f client.mk -s -j$(PARALLELISM)

build-gonk:
	@$(call GONK_CMD,make -j$(PARALLELISM))

# XXX Hard-coded for nexuss4g target
# XXX Hard-coded for gonk tool support
build-kernel:
	@PATH="$$PATH:$(abspath ./glue/gonk/prebuilt/linux-x86/toolchain/arm-eabi-4.4.3/bin)" make -C boot/kernel-android-samsung -j$(PARALLELISM) ARCH=arm CROSS_COMPILE=arm-eabi-

clean: clean-gecko clean-gonk clean-kernel

clean-gecko:
	rm -rf gecko/objdir-prof-android

clean-gonk:
	@$(call GONK_CMD,make clean)

clean-kernel:
	@PATH="$$PATH:$(abspath ./glue/gonk/prebuilt/linux-x86/toolchain/arm-eabi-4.4.3/bin)" make -C boot/kernel-android-samsung ARCH=arm CROSS_COMPILE=arm-eabi- clean

config-gecko-gonk:
	@cp -p config/gecko-prof-gonk gecko/.mozconfig

# XXX Hard-coded for nexuss4g target
config-nexuss4g: config-gecko-gonk
	@cp -p config/kernel-nexuss4g boot/kernel-android-samsung/.config && \
	echo -n full_crespo4g-eng > $(GONK)/.config

# XXX Hard-coded for nexuss4g target
flash: image
	@$(call GONK_CMD,fastboot flashall -w)

image: build
	@echo NYI

sync:
	@git submodule sync && \
	git submodule update --init && \
	git pull
