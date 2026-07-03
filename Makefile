#
# Makefile for a machine kernel image
#

CIRCLE_STDLIB_HOME ?= third_party/circle-stdlib
CIRCLEHOME ?= $(CIRCLE_STDLIB_HOME)/libs/circle
SRC_DIR ?= src
BUILD_ROOT ?= build
VICE ?= third_party/vice-3.10/src
VICE_ARCH ?= $(VICE)/arch/raspi
VICE_SHARED ?= $(VICE)/arch/shared
VICE_INCLUDE_DIRS ?= \
	$(VICE) \
	$(VICE_ARCH) \
	$(VICE_SHARED) \
	$(VICE_SHARED)/hotkeys \
	$(VICE_SHARED)/hwsiddrv \
	$(VICE_SHARED)/mididrv \
	$(VICE_SHARED)/socketdrv \
	$(VICE_SHARED)/sounddrv \
	$(VICE)/drive \
	$(VICE)/c64 \
	$(VICE)/c64/cart \
	$(VICE)/c64dtv \
	$(VICE)/c128 \
	$(VICE)/c128/cart \
	$(VICE)/vic20 \
	$(VICE)/pet \
	$(VICE)/cbm2 \
	$(VICE)/plus4 \
	$(VICE)/raster \
	$(VICE)/core \
	$(VICE)/core/rtc \
	$(VICE)/crtc \
	$(VICE)/datasette \
	$(VICE)/diskimage \
	$(VICE)/drive/iec \
	$(VICE)/drive/iec128dcr \
	$(VICE)/drive/iec/c64exp \
	$(VICE)/drive/iecieee \
	$(VICE)/drive/ieee \
	$(VICE)/drive/tcbm \
	$(VICE)/fileio \
	$(VICE)/fsdevice \
	$(VICE)/iecbus \
	$(VICE)/monitor \
	$(VICE)/parallel \
	$(VICE)/printerdrv \
	$(VICE)/rs232drv \
	$(VICE)/samplerdrv \
	$(VICE)/serial \
	$(VICE)/sid \
	$(VICE)/tape \
	$(VICE)/userport \
	$(VICE)/vdrive \
	$(VICE)/vicii \
	$(VICE)/vdc \
	$(VICE)/viciisc \
	$(VICE)/video \
	$(VICE)/lib/md5 \
	$(VICE)/lib/p64 \
	$(VICE)/platform \
	$(VICE)/joyport \
	$(VICE)/gfxoutputdrv \
	$(VICE)/tapeport \
	$(VICE)/imagecontents

-include $(CIRCLE_STDLIB_HOME)/Config.mk
-include $(CIRCLEHOME)/Config.mk
NEWLIBDIR ?= $(CIRCLE_STDLIB_INSTALL_DIR)
AARCH ?= 32

BOARD ?= pi4

ifeq ($(BOARD),pi4)
RASPPI := 4
else ifeq ($(BOARD),pi5)
RASPPI := 5
else
$(error Unsupported BOARD '$(BOARD)'; supported boards are pi4 and pi5)
endif

BUILD_BOARD ?= $(if $(BOARD),$(BOARD),raspi$(RASPPI))
BUILD_DIR ?= $(BUILD_ROOT)/$(BUILD_BOARD)/$(MACHINE_CLASS)

ifeq ($(strip $(RASPPI)),4)
ifneq ($(strip $(AARCH)),32)
$(error Pi4 builds currently use 32-bit Circle only)
endif
TARGET_BASENAME ?= kernel7l
C_STANDARD += -Wno-incompatible-pointer-types
else ifeq ($(strip $(RASPPI)),5)
ifneq ($(strip $(AARCH)),64)
$(error Pi5 builds require 64-bit Circle)
endif
TARGET_BASENAME ?= kernel_2712
endif

TARGET ?= $(BUILD_DIR)/$(TARGET_BASENAME)
.DEFAULT_GOAL := $(TARGET).img

BMC64_OBJS = main.o kernel.o viceoptions.o viceapp.o crt_pi_idx.o crt_pi_rgb.o \
             vicesound.o new_io.o errno_stubs.o async_network.o \
             config/runtime_config.o machines/machine_descriptor.o \
             network/network_manager.o \
             platform/platform.o vice_api.o
OBJS = $(addprefix $(BUILD_DIR)/,$(BMC64_OBJS))

OBJS	+= $(BUILD_DIR)/viceemulatorcore.o
ifneq ($(wildcard $(VICE)/blockdev.h),)
OBJS	+= $(BUILD_DIR)/vice_blockdev.o
endif
ifeq ($(RASPPI),5)
ifneq ($(wildcard $(VICE)/arch/shared/sounddrv/libsounddrv.a),)
else ifneq ($(wildcard $(VICE)/arch/shared/sounddrv/soundraspi.o),)
VICELIBS += $(VICE)/arch/shared/sounddrv/soundraspi.o
else
VICELIBS += $(VICE)/sounddrv/soundraspi.o
endif
endif

ifeq ($(RASPPI),5)
OBJS += $(BUILD_DIR)/fbl_pi5.o $(BUILD_DIR)/pi5_kms.o
else
OBJS += $(BUILD_DIR)/fbl.o
endif

$(BUILD_DIR)/pi5_kms.o: $(SRC_DIR)/pi5kms/pi5_kms.cpp | $(BUILD_DIR)
	@echo "  CPP   $@"
	@mkdir -p $(dir $@)
	@$(CPP) $(CPPFLAGS) -c -o $@ $<

$(BUILD_DIR)/pi5_kms.d: $(SRC_DIR)/pi5kms/pi5_kms.cpp | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	@$(CPP) $(CPPFLAGS) -M -MG -MT $(BUILD_DIR)/pi5_kms.o -MT $@ -MF $@ $<

CFLAGS += -I $(SRC_DIR) -I . -I third_party/common -I "$(NEWLIBDIR)/include" -I $(STDDEF_INCPATH) \
          -I $(CIRCLE_STDLIB_HOME)/include \
          -I $(CIRCLE_STDLIB_HOME)/libs/circle-newlib/libgloss/circle \
          -I $(CIRCLEHOME)/addon \
          $(addprefix -I ,$(wildcard $(VICE_INCLUDE_DIRS))) \
          -I $(CIRCLEHOME)/addon/fatfs \
          -DRASPI_COMPILE \
          -D $(MACHINE_CLASS)

ifeq ($(BMC64_BUILD_PROFILE),debug)
CFLAGS += -DBMC64_DEBUG_PROFILE
CPPFLAGS += -DBMC64_DEBUG_PROFILE
endif
ifneq ($(BMC64_RS232_LOG_LEVEL),)
CFLAGS += -DBMC64_RS232_LOG_LEVEL=$(BMC64_RS232_LOG_LEVEL)
CPPFLAGS += -DBMC64_RS232_LOG_LEVEL=$(BMC64_RS232_LOG_LEVEL)
endif
ifneq ($(BMC64_ACIA_LOG_LEVEL),)
CFLAGS += -DBMC64_ACIA_LOG_LEVEL=$(BMC64_ACIA_LOG_LEVEL)
CPPFLAGS += -DBMC64_ACIA_LOG_LEVEL=$(BMC64_ACIA_LOG_LEVEL)
endif
ifneq ($(BMC64_TCP_LOG_LEVEL),)
CFLAGS += -DBMC64_TCP_LOG_LEVEL=$(BMC64_TCP_LOG_LEVEL)
CPPFLAGS += -DBMC64_TCP_LOG_LEVEL=$(BMC64_TCP_LOG_LEVEL)
endif
ifneq ($(BMC64_NET_LOG_LEVEL),)
CFLAGS += -DBMC64_NET_LOG_LEVEL=$(BMC64_NET_LOG_LEVEL)
CPPFLAGS += -DBMC64_NET_LOG_LEVEL=$(BMC64_NET_LOG_LEVEL)
endif

LIBS := $(VICELIBS) \
        third_party/common/libbmc64common.a \
        $(CIRCLEHOME)/addon/wlan/hostap/wpa_supplicant/libwpa_supplicant.a \
        $(CIRCLEHOME)/addon/wlan/libwlan.a \
        $(CIRCLE_STDLIB_LIBS) \
        $(CIRCLEHOME)/addon/linux/liblinuxemu.a \
        $(CIRCLEHOME)/lib/sound/libsound.a

ifeq ($(RASPPI),5)
else
LIBS += $(CIRCLEHOME)/addon/vc4/vchiq/libvchiq.a \
	$(CIRCLEHOME)/addon/vc4/interface/bcm_host/libbcm_host.a \
	$(CIRCLEHOME)/addon/vc4/interface/khronos/libkhrn_client.a \
	$(CIRCLEHOME)/addon/vc4/interface/vcos/libvcos.a \
	$(CIRCLEHOME)/addon/vc4/interface/vmcs_host/libvmcs_host.a
endif

EXTRACLEAN += $(OBJS) $(OBJS:.o=.d) \
              $(TARGET).elf $(TARGET).lst $(TARGET).img $(TARGET).hex $(TARGET).cir $(TARGET).map

$(BUILD_DIR):
	@mkdir -p $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.S | $(BUILD_DIR)
	@echo "  AS    $@"
	@mkdir -p $(dir $@)
	@$(AS) $(AFLAGS) -c -o $@ $<

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	@echo "  CC    $@"
	@mkdir -p $(dir $@)
	@$(CC) $(CFLAGS) $(C_STANDARD) -c -o $@ $<

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp | $(BUILD_DIR)
	@echo "  CPP   $@"
	@mkdir -p $(dir $@)
	@$(CPP) $(CPPFLAGS) -c -o $@ $<

$(BUILD_DIR)/%.d: $(SRC_DIR)/%.S | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	@$(AS) $(AFLAGS) -M -MG -MT $(BUILD_DIR)/$*.o -MT $@ -MF $@ $<

$(BUILD_DIR)/%.d: $(SRC_DIR)/%.c | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	@$(CC) $(CFLAGS) -M -MG -MT $(BUILD_DIR)/$*.o -MT $@ -MF $@ $<

$(BUILD_DIR)/%.d: $(SRC_DIR)/%.cpp | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	@$(CPP) $(CPPFLAGS) -M -MG -MT $(BUILD_DIR)/$*.o -MT $@ -MF $@ $<

include $(CIRCLEHOME)/Rules.mk
