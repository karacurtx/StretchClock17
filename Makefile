TARGET := iphone:clang:latest:17.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := StretchClock17
StretchClock17_FILES := Tweak.xm
StretchClock17_FRAMEWORKS := UIKit Foundation QuartzCore CoreGraphics
StretchClock17_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
