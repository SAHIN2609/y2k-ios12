//
//  Makefile — Theos build for a jailbroken iOS 12 device.
//
//  The .deb installs /Applications/y2k.app. No dylib is injected: the app is
//  built as a self-contained bundle and (optionally) signed with ldid so the
//  kernel accepts it. On a jailbroken device with AppSync Unified or the
//  default permissive amfi settings this is enough; otherwise sign with your
//  own certificate.
//

TARGET := iphone:clang:latest:12.0
ARCHS := arm64
INSTALL_TARGET_PROCESSES = y2k

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = y2k

y2k_FILES := $(shell find Y2K -name '*.swift')
y2k_FRAMEWORKS := Foundation UIKit CoreImage CoreGraphics Photos Metal
y2k_PRIVATE_FRAMEWORKS :=
y2k_CFLAGS := -fobjc-arc
y2k_SWIFTFLAGS := -swift-version 5
y2k_CODESIGN_FLAGS := -S Y2K/Support/y2k.entitlements
y2k_INFOPLIST := Y2K/Support/Info.plist
y2k_RESOURCE_DIRS := Resources
y2k_RESOURCE_FILES := $(wildcard Resources/*.ttf Resources/*.otf Resources/*.cube)

include $(THEOS_MAKE_PATH)/application.mk

# Bundle resources next to the binary, preserving subfolders (LUTs, Stickers,
# .lproj, AppIcon).
after-y2k-stage::
	@echo ">> staging resources"
	@mkdir -p $(THEOS_STAGING_DIR)/Applications/y2k.app
	@cp -R Resources/LUTs $(THEOS_STAGING_DIR)/Applications/y2k.app/ 2>/dev/null || true
	@cp -R Resources/Stickers $(THEOS_STAGING_DIR)/Applications/y2k.app/ 2>/dev/null || true
	@cp -R Resources/AppIcon $(THEOS_STAGING_DIR)/Applications/y2k.app/ 2>/dev/null || true
	@for d in Resources/*.lproj; do cp -R "$$d" $(THEOS_STAGING_DIR)/Applications/y2k.app/ ; done
	@cp Resources/*.ttf Resources/*.otf $(THEOS_STAGING_DIR)/Applications/y2k.app/ 2>/dev/null || true
	@ldid -S Y2K/Support/y2k.entitlements $(THEOS_STAGING_DIR)/Applications/y2k.app/y2k 2>/dev/null \
		|| $(THEOS)/toolchain/*/bin/ldid -S Y2K/Support/y2k.entitlements $(THEOS_STAGING_DIR)/Applications/y2k.app/y2k 2>/dev/null || true

after-y2k-install::
	@echo ">> y2k installed to /Applications/y2k.app"
