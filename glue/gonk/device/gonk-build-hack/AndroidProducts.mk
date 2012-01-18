# This file is here for hacking Android's build system.
# AndroidProducts.mk would be loaded by product.mk and
# product_config.mk, envsetup.mk and config.mk in turn.
# It is loaded after definition of BUILD_XXX variables.
# We can override BUILD_XXX here.
#
BUILD_DROIDDOC:= $(BUILD_SYSTEM)/droiddoc-noop.mk
