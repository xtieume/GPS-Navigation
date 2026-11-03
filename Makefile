export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:16.0
include $(THEOS)/makefiles/common.mk
SUBPROJECTS += Tweak App
include $(THEOS_MAKE_PATH)/aggregate.mk
