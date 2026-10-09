ARCHS = arm64
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET = iphone:clang:latest:15.0
else
TARGET = iphone:clang:latest:12.0
endif
include $(THEOS)/makefiles/common.mk

TOOL_NAME = vhx-test
vhx-test_FILES = main.m
vhx-test_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra
vhx-test_FRAMEWORKS = Foundation
vhx-test_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
