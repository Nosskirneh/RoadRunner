TARGET = iphone:clang:11.2
ifdef DEBUG
	ARCHS = arm64
else
	ARCHS = arm64 arm64e
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KeepPartying
$(TWEAK_NAME)_FILES = Tweak.xm RunningBoard.xm KPCenter.m
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = MediaRemote
$(TWEAK_NAME)_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 runningboardd backboardd"
