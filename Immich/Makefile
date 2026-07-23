.PHONY: all clean


APP_NAME     := Immich14
DISPLAY_NAME := Immich 14
BUNDLE_ID    := com.lns.immich-ios-14
APP_VERSION  := $(shell cat ../VERSION)

IPHONEOS_DEPLOYMENT_TARGET := 14.0
export IPHONEOS_DEPLOYMENT_TARGET

THEOS ?= ~/theos
CC    := $(THEOS)/toolchain/linux/iphone/bin/clang
LDID  := $(THEOS)/toolchain/linux/iphone/bin/ldid

SDKROOT := $(firstword $(wildcard $(THEOS)/sdks/iPhoneOS14.*.sdk) $(wildcard $(THEOS)/sdks/iPhoneOS1[5-9].*.sdk) $(wildcard $(THEOS)/sdks/iPhoneOS*.sdk))

ifeq ($(shell test -e ../.git && echo yes),yes)
COMMIT_HASH := $(shell git rev-parse --short HEAD 2>/dev/null)
else
COMMIT_HASH :=
endif

LIBS := -lobjc -lsqlite3 -lc++
FRAMEWORKS := \
	-framework UIKit \
	-framework Foundation \
	-framework CoreGraphics \
	-framework CoreText \
	-framework QuartzCore \
	-framework CoreImage \
	-framework ImageIO \
	-framework Photos \
	-framework PhotosUI \
	-framework AVFoundation \
	-framework AVKit \
	-framework Security \
	-framework SystemConfiguration \
	-framework Network \
	-framework CoreServices

CFLAGS := -Wno-deprecated-declarations -Wno-nullability-completeness -Werror \
	-target arm64-apple-ios$(IPHONEOS_DEPLOYMENT_TARGET) \
	-fobjc-arc -fconstant-cfstrings -isysroot $(SDKROOT) \
	-DAPP_VERSION_STRING=\"$(APP_VERSION)\" -DAPP_COMMIT_HASH=\"$(COMMIT_HASH)\"
LDFLAGS := -target arm64-apple-ios$(IPHONEOS_DEPLOYMENT_TARGET) \
	-isysroot $(SDKROOT) $(LIBS) $(FRAMEWORKS) -Wl,-dead_strip_dylibs

ifneq ($(RELEASE),1)
CFLAGS += -DDEBUG -g
endif

ifeq ($(APPSTORE),1)
CFLAGS      += -DIM_TROLLSTORE=0 -DIM_APPSTORE=1
ENTITLEMENTS := ../Immich-appstore.entitlements
else
CFLAGS      += -DIM_TROLLSTORE=1
ENTITLEMENTS := ../Immich.entitlements
endif

APP_DIR := build/Payload/$(APP_NAME).app
BIN     := $(APP_DIR)/$(APP_NAME)

SOURCES := $(wildcard *.m *.c */*.m */*.c)
OBJECTS := $(addprefix build/objects/,$(addsuffix .o,$(SOURCES)))

all: build/$(APP_NAME).ipa

$(OBJECTS): build/objects/%.o: %
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@

$(BIN): $(OBJECTS) $(ENTITLEMENTS)
	@mkdir -p $(@D)
	$(CC) $(LDFLAGS) $(filter %.o,$^) -o $@
	$(LDID) -S$(ENTITLEMENTS) $@

$(APP_DIR)/Info.plist: Info.plist ../VERSION
	@mkdir -p $(@D)
	sed 's/$$(APP_VERSION)/$(APP_VERSION)/g;s/$$(BUNDLE_ID)/$(BUNDLE_ID)/g;s/$$(DISPLAY_NAME)/$(DISPLAY_NAME)/g;s/$$(APP_NAME)/$(APP_NAME)/g;s/$$(COMMIT_HASH)/$(COMMIT_HASH)/g' Info.plist > $@

build/$(APP_NAME).ipa: $(BIN) $(APP_DIR)/Info.plist
	cd build && rm -f $(APP_NAME).ipa && zip -qr $(APP_NAME).ipa Payload
	@echo "Built build/$(APP_NAME).ipa (install + sign via TrollStore)"

clean:
	rm -rf build/
