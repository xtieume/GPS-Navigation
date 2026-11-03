include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = GPSNav
GPSNav_FILES = main.m TileMapView.m MapController.m ListSheet.m LogSheet.m ../Shared/Log.m
GPSNav_FRAMEWORKS = UIKit MapKit CoreLocation Metal Security
GPSNav_CFLAGS = -fobjc-arc
GPSNav_CODESIGN_FLAGS = -Sentitlements.plist
GPSNav_INSTALL_PATH = /Applications
include $(THEOS_MAKE_PATH)/application.mk
