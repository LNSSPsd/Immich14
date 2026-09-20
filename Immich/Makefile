.PHONY: all clean publish


APP_NAME     := Immich14
DISPLAY_NAME := Immich 14
BUNDLE_ID    := com.lns.immich-ios-14
APP_VERSION  := $(shell cat ../VERSION)

IPHONEOS_DEPLOYMENT_TARGET := 13.0
export IPHONEOS_DEPLOYMENT_TARGET

THEOS ?= ~/theos

PUBLISH_ROOT ?= /srv/http/files
PUBLISH_DIR  := $(PUBLISH_ROOT)/immich14
LOCAL_IP := $(shell ip addr | sed -n "s/.*inet \([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\)[ \/].*/\1/p" | grep -v '^127\.' | head -1)
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
	-framework CoreMedia \
	-framework Security \
	-framework AuthenticationServices \
	-framework LocalAuthentication \
	-framework SystemConfiguration \
	-framework Network \
	-framework MapKit \
	-framework CoreLocation \
	-framework CoreServices \
	-framework BackgroundTasks

INCLUDE_DIRS := . $(filter-out build/,$(wildcard */))
CFLAGS := -Wno-deprecated-declarations -Wno-nullability-completeness -Werror \
	-target arm64-apple-ios$(IPHONEOS_DEPLOYMENT_TARGET) \
	-fobjc-arc -fconstant-cfstrings -isysroot $(SDKROOT) \
	$(addprefix -I,$(INCLUDE_DIRS)) \
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

SOURCES  := $(wildcard *.m *.c */*.m */*.c)
ASM_SRCS := $(wildcard *.S */*.S)
OBJECTS  := $(addprefix build/objects/,$(addsuffix .o,$(SOURCES))) \
            $(addprefix build/objects/,$(addsuffix .o,$(ASM_SRCS)))

SRC_OBJS := $(addprefix build/objects/,$(addsuffix .o,$(SOURCES)))
ASM_OBJS := $(addprefix build/objects/,$(addsuffix .o,$(ASM_SRCS)))

all: build/$(APP_NAME).ipa

$(SRC_OBJS): build/objects/%.o: %
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

ASFLAGS := -target arm64-apple-ios$(IPHONEOS_DEPLOYMENT_TARGET) -isysroot $(SDKROOT)
$(ASM_OBJS): build/objects/%.o: %
	@mkdir -p $(@D)
	$(CC) $(ASFLAGS) -c $< -o $@

-include $(OBJECTS:.o=.d)

$(BIN): $(OBJECTS) $(ENTITLEMENTS)
	@mkdir -p $(@D)
	$(CC) $(LDFLAGS) $(filter %.o,$^) -o $@
	$(LDID) -S$(ENTITLEMENTS) $@

$(APP_DIR)/Info.plist: Info.plist ../VERSION
	@mkdir -p $(@D)
	sed 's/$$(APP_VERSION)/$(APP_VERSION)/g;s/$$(BUNDLE_ID)/$(BUNDLE_ID)/g;s/$$(DISPLAY_NAME)/$(DISPLAY_NAME)/g;s/$$(APP_NAME)/$(APP_NAME)/g;s/$$(COMMIT_HASH)/$(COMMIT_HASH)/g' Info.plist > $@

ICON_FILES := $(wildcard AppIcon/*.png)
ICON_TARGETS := $(addprefix $(APP_DIR)/,$(notdir $(ICON_FILES)))

$(APP_DIR)/%.png: AppIcon/%.png
	@mkdir -p $(@D)
	ln $< $@

build/$(APP_NAME).ipa: $(BIN) $(APP_DIR)/Info.plist $(ICON_TARGETS)
	cd build && rm -f $(APP_NAME).ipa && zip -qr $(APP_NAME).ipa Payload
	@echo "Built build/$(APP_NAME).ipa (install + sign via TrollStore)"

publish: build/$(APP_NAME).ipa
	@mkdir -p $(PUBLISH_DIR)
	cp build/$(APP_NAME).ipa $(PUBLISH_DIR)/$(APP_NAME).ipa
	@printf '%s\n' \
		'<html><head><meta name=viewport content="width=device-width,initial-scale=1">' \
		'<title>$(DISPLAY_NAME)</title><style>a{font-size:80px}p{font-size:40px}</style></head><body>' \
		'<a href="apple-magnifier://install?url=http%3A%2F%2F$(LOCAL_IP)%2Ffiles%2Fimmich14%2F$(APP_NAME).ipa">Install</a>' \
		'<p>$(DISPLAY_NAME) $(APP_VERSION) ($(COMMIT_HASH))</p>' \
		'<p>Latest Update: $(shell date)</p></body></html>' \
		> $(PUBLISH_DIR)/index.html
	@echo "Published: http://$(LOCAL_IP)/files/immich14/  (tap Install -> TrollStore)"

clean:
	rm -rf build/
