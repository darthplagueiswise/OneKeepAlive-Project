# THEOS-style makefile (optional, if you prefer Theos locally)
# Requires THEOS toolchain set up; not used by GitHub Actions above.
FINALPACKAGE=1
TARGET := iphone:clang:latest:12.0
ARCHS := arm64 arm64e
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OneKeepAlive
OneKeepAlive_FILES = OneKeepAlive.m
OneKeepAlive_CFLAGS = -fobjc-arc -fmodules
OneKeepAlive_FRAMEWORKS = Foundation UIKit AVFoundation AudioToolbox
# Ensure the install_name is where you place the dylib in the IPA:
# (Theos handles this via standard @rpath; we prefer explicit path.)
OneKeepAlive_LDFLAGS += -Wl,-install_name,@executable_path/Frameworks/OneKeepAlive.dylib

include $(THEOS_MAKE_PATH)/tweak.mk
