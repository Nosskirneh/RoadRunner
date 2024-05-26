TARGET = iphone:clang:11.2

ifdef 64
	ARCHS = arm64
else ifdef 64E
	ARCHS = arm64e
else
	ARCHS = arm64 arm64e
endif

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = RoadRunnerPrefs
$(BUNDLE_NAME)_FILES = RRRootListController.m $(wildcard *.xm) $(wildcard *.m) ../SettingsKeys.m TwitterStuff/Prompt.m
$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles
$(BUNDLE_NAME)_FRAMEWORKS = UIKit
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/preferences.plist$(ECHO_END)
