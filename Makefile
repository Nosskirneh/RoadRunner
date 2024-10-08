TARGET = iphone:clang:11.2
ifdef 64
	ARCHS = arm64
else ifdef 64E
	ARCHS = arm64e
else
	ARCHS = arm64 arm64e
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RoadRunner
$(TWEAK_NAME)_FILES = $(wildcard *.xm) SettingsKeys.m
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = MediaRemote
$(TWEAK_NAME)_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk


ifdef SB_ONLY
after-install::
	install.exec "killall -9 SpringBoard"
else ifdef PREFS_ONLY
after-install::
		install.exec "killall -9 Preferences"
else ifdef RB_ONLY
after-install::
		install.exec "killall -9 runningboardd"
else ifdef APPS_ONLY
after-install::
		install.exec "killall -9 Spotify"
else
after-install::
		install.exec "killall SpringBoard && sleep 1 && killall -9 runningboardd"
endif

SUBPROJECTS += preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
