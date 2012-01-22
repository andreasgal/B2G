#
# PolicyConfig.mk would be included by build/core/main.mk for FULL_BUILD.
#
# main.mk will try to include frameworks/policies/base/PolicyConfig.mk
# if it is there.  PolicyConfig.mk is included right after including
# all module makefiles.  PolicyConfig.mk is supposed to do anything
# that must happen after including all module makefiles.  See, main.mk
# for more information.
#

# The list of modules that should not be built
REMOVE_MODULES := libclearsilver-jni
# All modules with one of these classes are also not built.
REMOVE_CLASSES := APPS JAVA_LIBRARIES

# Make a list of all modules with one of given classes.
#
# $(1): a list of classes.
#
define make-list-of-all-modules-of-classes
$(foreach m, $(ALL_MODULES), $(if $(filter $(1), $(ALL_MODULES.$(m).CLASS)), $(m)))
endef

REMOVE_MODULES := $(REMOVE_MODULES) \
	$(call make-list-of-all-modules-of-classes, $(REMOVE_CLASSES))

REMOVE_TARGETS :=

# Remove a given module from tag lists.
#
# The given module is removed from corresponding tag lists.  The built
# targets of the module are added to REMOVE_TARGETS.  Targets in
# REMOVE_TARGETS are also removed from CHECKED and BUILT list for
# every module later.
#
# $(1): the name of the moulde to remove.
#
define remove-module
$(foreach t,$(ALL_MODULES.$(1).TAGS),
ALL_MODULE_TAGS.$(t) := $(filter-out $(ALL_MODULES.$(1).INSTALLED), \
	$(ALL_MODULE_TAGS.$(t))))
REMOVE_TARGETS := \
	$(REMOVE_TARGETS) \
	$(ALL_MODULES.$(1).BUILT)
ALL_MODULES.$(1).TAGS :=
ALL_MODULES.$(1).CHECKED :=
ALL_MODULES.$(1).BUILT :=
endef

# Remove all modules from tag lists.
$(foreach m, $(REMOVE_MODULES), \
	$(eval $(call remove-module,$(m))))

# Remove built targets from the CHECKED list for every module.
$(foreach mod, $(ALL_MODULES), \
	$(eval ALL_MODULES.$(mod).CHECKED := \
		$(filter-out $(REMOVE_TARGETS), \
			$(ALL_MODULES.$(mod).CHECKED))))

# Remove built targets of removed modules from the BUILT list for every module.
$(foreach mod, $(ALL_MODULES), \
	$(eval ALL_MODULES.$(mod).BUILT := \
		$(filter-out $(REMOVE_TARGETS), \
			$(ALL_MODULES.$(mod).BUILT))))

# Remove removed modules from all products.
$(foreach p, $(ALL_PRODUCTS), \
	$(eval PRODUCTS.$(p).PRODUCT_PACKAGES := \
		$(filter-out $(REMOVE_MODULES), \
			$(PRODUCTS.$(p).PRODUCT_PACKAGES))))
