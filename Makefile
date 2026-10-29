# Build arm64 for the iPhone X target. Avoid arm64e here because the Linux
# cross-toolchain cannot emit the newer iOS 14+ arm64e ABI without extra steps.
ARCHS = arm64
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# Only the unprivileged Preferences bundle is packaged in this baseline.
# The daemon remains a reviewed prototype in Daemon/main.m and is not built or
# installed until its IPC directory handling and native descriptor adapter are
# security-reviewed and tested on the target device.
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
