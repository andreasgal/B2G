# This file is here for hacking Android's build system.
# AndroidProducts.mk would be loaded by product.mk and
# product_config.mk, envsetup.mk and config.mk in turn.
# It is loaded after definition of BUILD_XXX variables.
# We can override BUILD_XXX here.
#
GONK_BUILD_HACK:=$(TOPDIR)device/gonk-build-hack

#BUILD_PACKAGE:= $(GONK_BUILD_HACK)/package-noop.mk
#BUILD_JAVA_LIBRARY:= $(GONK_BUILD_HACK)/java_library-noop.mk
#BUILD_STATIC_JAVA_LIBRARY:= $(GONK_BUILD_HACK)/static_java_library-noop.mk
#BUILD_HOST_JAVA_LIBRARY:= $(GONK_BUILD_HACK)/host_java_library-noop.mk
BUILD_DROIDDOC:= $(GONK_BUILD_HACK)/droiddoc-noop.mk

TARGET_NO_RECOVERY := true

#define remove-module
#$(foreach t,$(ALL_MODULES.$(1).TAGS),
#ALL_MODULE_TAGS.$(t) := $(filter-out $(ALL_MODULES.$(1).INSTALLED), \
#			$(ALL_MODULE_TAGS.$(t))))
#ALL_MODULES.$(1).TAGS :=
#ALL_MODULES.$(1).CHECKED :=
#ALL_MODULES.$(1).BUILT :=
#endef

define touch-n-mkdir
$(shell mkdir -p out/target/common/obj/PACKAGING)
$(shell touch -t 197001010000 out/target/common/obj/PACKAGING/$(strip $(1))-timestamp)
endef
$(eval $(call touch-n-mkdir,checkapi-last))
$(eval $(call touch-n-mkdir,checkapi-current))

.IGNORE: out/target/common/obj/PACKAGING/checkapi-last-timestamp
.IGNORE: out/target/common/obj/PACKAGING/checkapi-current-timestamp
