THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:16.5:16.0

INSTALL_TARGET_PROCESSES = Instagram

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IGDemo
IGDemo_FILES = Tweak.xm
IGDemo_CFLAGS = -fobjc-arc
IGDemo_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
