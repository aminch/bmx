#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SRC_DIR/tools/lib/build_paths.sh"

RPI_FIRMWARE_BOOT_DIR="$SRC_DIR/third_party/raspberrypi-firmware/boot"
PI4_BOOT_DIR="$RPI_FIRMWARE_BOOT_DIR/pi4"
KERNEL_DIR="${BMC64_KERNEL_DIR:-$(bmc64_vice310_image_dir pi4)}"
STAGE_DIR="$(bmc64_stage_dir pi4)"
BUILD_PROFILE="${BMC64_BUILD_PROFILE:-release}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--profile release|debug] [--debug-uart] [--kernel-dir DIR] [--stage-dir DIR]

Options:
  --profile      stage boot config profile (default: ${BMC64_BUILD_PROFILE:-release})
  --debug-uart   alias for --profile debug
  --kernel-dir   override kernel image input directory (default: $KERNEL_DIR)
  --stage-dir    override the output directory (default: $STAGE_DIR)
EOF
}

while (($# > 0)); do
  case "$1" in
    --profile)
      if [ -z "${2:-}" ]; then
        echo "--profile requires release or debug" >&2
        exit 1
      fi
      BUILD_PROFILE="$2"
      shift 2
      ;;
    --debug-uart)
      BUILD_PROFILE=debug
      shift
      ;;
    --stage-dir)
      if [ -z "${2:-}" ]; then
        echo "--stage-dir requires a directory" >&2
        exit 1
      fi
      STAGE_DIR="$2"
      shift 2
      ;;
    --kernel-dir)
      if [ -z "${2:-}" ]; then
        echo "--kernel-dir requires a directory" >&2
        exit 1
      fi
      KERNEL_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unexpected argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$BUILD_PROFILE" in
  release|debug) ;;
  *)
    echo "unsupported build profile: $BUILD_PROFILE" >&2
    usage >&2
    exit 1
    ;;
esac

require_boot_file() {
  local src="$1"

  if [ ! -f "$src" ]; then
    echo "Missing staged Raspberry Pi boot file: $src" >&2
    echo "Refresh third_party/raspberrypi-firmware/boot before staging." >&2
    exit 1
  fi
}

copy_boot_file() {
  local src="$1"
  local dest="$2"

  require_boot_file "$src"
  mkdir -p "$(dirname "$STAGE_DIR/$dest")"
  cp "$src" "$STAGE_DIR/$dest"
}

stage_user_dirs() {
  local top machine

  for top in disks tapes carts snapshots; do
    for machine in C64 C128 VIC20 PLUS4 PET; do
      mkdir -p "$STAGE_DIR/$top/$machine"
    done
  done

  mkdir -p "$STAGE_DIR/phonebooks"
}

stage_vice_runtime_files() {
  local vice_data="$SRC_DIR/third_party/vice-3.10/data"
  local file
  local missing_roms=()

  copy_runtime_file() {
    local src="$vice_data/$1"
    local dest="$STAGE_DIR/$2"

    if [ ! -f "$src" ]; then
      echo "Missing VICE runtime file: $src" >&2
      exit 1
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  }

  copy_rom_file() {
    local src="$vice_data/$1"
    local dest="$STAGE_DIR/$2"

    if [ ! -f "$src" ]; then
      missing_roms+=("$2")
      return
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  }

  # Keep the staged machine ROMs intentionally small. C128 VICE ROM validation
  # is patched to check only the currently selected MachineType, so the national
  # C128 ROM variants are not needed for the default international C128
  # configuration. Stage all VICE 3.10 drive ROMs so every selectable drive
  # model can use hardware-level emulation when its ROM is available.
  for file in \
    C64/basic-901226-01.bin:c64/basic-901226-01.bin \
    C64/kernal-901227-03.bin:c64/kernal-901227-03.bin \
    C64/chargen-901225-01.bin:c64/chargen-901225-01.bin \
    C128/basiclo-318018-04.bin:c128/basiclo-318018-04.bin \
    C128/basichi-318019-04.bin:c128/basichi-318019-04.bin \
    C128/basic64-901226-01.bin:c128/basic64-901226-01.bin \
    C128/kernal64-901227-03.bin:c128/kernal64-901227-03.bin \
    C128/kernal-318020-05.bin:c128/kernal-318020-05.bin \
    C128/chargen-390059-01.bin:c128/chargen-390059-01.bin \
    VIC20/basic-901486-01.bin:vic20/basic-901486-01.bin \
    VIC20/chargen-901460-03.bin:vic20/chargen-901460-03.bin \
    VIC20/kernal.901486-06.bin:vic20/kernal.901486-06.bin \
    VIC20/kernal.901486-07.bin:vic20/kernal.901486-07.bin \
    PLUS4/basic-318006-01.bin:plus4/basic-318006-01.bin \
    PLUS4/3plus1-317053-01.bin:plus4/3plus1-317053-01.bin \
    PLUS4/3plus1-317054-01.bin:plus4/3plus1-317054-01.bin \
    PLUS4/kernal-318004-05.bin:plus4/kernal-318004-05.bin \
    PLUS4/kernal-318005-05.bin:plus4/kernal-318005-05.bin \
    PET/basic-4.901465-23-20-21.bin:pet/basic-4.901465-23-20-21.bin \
    PET/characters-2.901447-10.bin:pet/characters-2.901447-10.bin \
    PET/kernal-4.901465-22.bin:pet/kernal-4.901465-22.bin \
    PET/edit-4-80-b-50Hz.901474-04_.bin:pet/edit-4-80-b-50Hz.901474-04_.bin \
    DRIVES/dos1001-901887+8-01.bin:drives/dos1001-901887+8-01.bin \
    DRIVES/dos1540-325302+3-01.bin:drives/dos1540-325302+3-01.bin \
    DRIVES/dos1541-325302-01+901229-05.bin:drives/dos1541-325302-01+901229-05.bin \
    DRIVES/dos1541ii-251968-03.bin:drives/dos1541ii-251968-03.bin \
    DRIVES/dos1551-318008-01.bin:drives/dos1551-318008-01.bin \
    DRIVES/dos1570-315090-01.bin:drives/dos1570-315090-01.bin \
    DRIVES/dos1571-310654-05.bin:drives/dos1571-310654-05.bin \
    DRIVES/dos1571cr-318047-01.bin:drives/dos1571cr-318047-01.bin \
    DRIVES/dos1581-318045-02.bin:drives/dos1581-318045-02.bin \
    DRIVES/dos2031-901484-03+05.bin:drives/dos2031-901484-03+05.bin \
    DRIVES/dos2040-901468-06+07.bin:drives/dos2040-901468-06+07.bin \
    DRIVES/dos3040-901468-11-13.bin:drives/dos3040-901468-11-13.bin \
    DRIVES/dos4040-901468-14-16.bin:drives/dos4040-901468-14-16.bin \
    DRIVES/dos9000-300516+7-revC.bin:drives/dos9000-300516+7-revC.bin; do
    copy_rom_file "${file%%:*}" "${file##*:}"
  done

  for file in \
    C64/gtk3_pos.vkm:c64/gtk3_pos.vkm \
    C64/gtk3_pos_de.vkm:c64/gtk3_pos_de.vkm \
    C128/gtk3_pos.vkm:c128/gtk3_pos.vkm \
    C128/gtk3_pos_de.vkm:c128/gtk3_pos_de.vkm \
    VIC20/gtk3_pos.vkm:vic20/gtk3_pos.vkm \
    VIC20/gtk3_pos_de.vkm:vic20/gtk3_pos_de.vkm \
    PLUS4/gtk3_pos.vkm:plus4/gtk3_pos.vkm \
    PLUS4/gtk3_pos_de.vkm:plus4/gtk3_pos_de.vkm \
    PET/gtk3_pos.vkm:pet/gtk3_pos.vkm \
    PET/gtk3_bude_pos.vkm:pet/gtk3_bude_pos.vkm \
    PET/gtk3_buuk_pos_de.vkm:pet/gtk3_buuk_pos_de.vkm \
    PET/gtk3_buuk_pos.vkm:pet/gtk3_buuk_pos.vkm \
    PET/gtk3_bude_pos_de.vkm:pet/gtk3_bude_pos_de.vkm; do
    copy_runtime_file "${file%%:*}" "${file##*:}"
  done

  # VICE 3.10 ships revisioned ROM filenames. Keep the staged runtime on
  # those upstream names and avoid historical short-name aliases.
  copy_if_present "$STAGE_DIR/pet/characters-2.901447-10.bin" "$STAGE_DIR/pet/CHARGEN"

  if [ "${#missing_roms[@]}" -gt 0 ]; then
    {
      echo "Missing ROM files were not staged."
      echo
      echo "Copy these files to the staged SD card tree before booting:"
      printf '  %s\n' "${missing_roms[@]}"
      echo
      echo "Each machine directory also contains ROMS.txt with the required machine ROMs."
    } > "$STAGE_DIR/MISSING-ROMS.txt"

    echo "Skipped ${#missing_roms[@]} missing ROM file(s); see $STAGE_DIR/MISSING-ROMS.txt" >&2
  fi

  stage_user_dirs
}

copy_if_present() {
  local src="$1"
  local dest="$2"

  if [ -f "$src" ] && [ ! -f "$dest" ]; then
    cp "$src" "$dest"
  fi
}

stage_vice310_raspi_keymaps() {
  local dir
  local machine

  for machine in c64 c128 vic20 plus4 pet; do
    mkdir -p "$STAGE_DIR/$machine"
    copy_if_present "$SRC_DIR/tools/keymaps/raspi/$machine/rpi_pos.vkm" "$STAGE_DIR/$machine/rpi_pos.vkm"
    copy_if_present "$SRC_DIR/tools/keymaps/raspi/$machine/rpi_pos_de.vkm" "$STAGE_DIR/$machine/rpi_pos_de.vkm"
    copy_if_present "$SRC_DIR/tools/keymaps/raspi/$machine/rpi_maxi_pos.vkm" "$STAGE_DIR/$machine/rpi_maxi_pos.vkm"
  done
  copy_if_present "$SRC_DIR/tools/keymaps/raspi/c64/rpi_petsciiboard_sym.vkm" \
    "$STAGE_DIR/c64/rpi_petsciiboard_sym.vkm"

  for dir in "$STAGE_DIR"/c64 "$STAGE_DIR"/c128 "$STAGE_DIR"/vic20 "$STAGE_DIR"/plus4 "$STAGE_DIR"/pet; do
    [ -d "$dir" ] || continue
    copy_if_present "$dir/gtk3_pos.vkm" "$dir/raspi_pos.vkm"
  done

  copy_if_present "$STAGE_DIR/c64/gtk3_pos_de.vkm" "$STAGE_DIR/c64/rpi_pos_de.vkm"
  "$SRC_DIR/tools/keymaps/generate_raspi_keymaps.py" --repo "$SRC_DIR" --output "$STAGE_DIR"

  for dir in "$STAGE_DIR"/c64 "$STAGE_DIR"/c128 "$STAGE_DIR"/vic20 "$STAGE_DIR"/plus4 "$STAGE_DIR"/pet; do
    [ -d "$dir" ] || continue
    copy_if_present "$dir/rpi_pos_de.vkm" "$dir/raspi_pos_de.vkm"
  done

  rm -f "$STAGE_DIR"/c64/rpi_sym.vkm \
    "$STAGE_DIR"/c128/rpi_sym.vkm \
    "$STAGE_DIR"/vic20/rpi_sym.vkm \
    "$STAGE_DIR"/plus4/rpi_sym.vkm \
    "$STAGE_DIR"/pet/rpi_buus_sym.vkm \
    "$STAGE_DIR"/pet/rpi_grus_sym.vkm
}

stage_wlan_firmware() {
  local firmware_dir="$SRC_DIR/third_party/raspberrypi-firmware/wlan"
  local required=(
    brcmfmac43430-sdio.bin
    brcmfmac43430-sdio.clm_blob
    brcmfmac43430-sdio.txt
    brcmfmac43436-sdio.bin
    brcmfmac43436-sdio.clm_blob
    brcmfmac43436-sdio.txt
    brcmfmac43436s-sdio.bin
    brcmfmac43436s-sdio.txt
    brcmfmac43455-sdio.bin
    brcmfmac43455-sdio.clm_blob
    brcmfmac43455-sdio.raspberrypi,5-model-b.bin
    brcmfmac43455-sdio.raspberrypi,5-model-b.clm_blob
    brcmfmac43455-sdio.raspberrypi,5-model-b.txt
    brcmfmac43455-sdio.txt
    brcmfmac43456-sdio.bin
    brcmfmac43456-sdio.clm_blob
    brcmfmac43456-sdio.txt
  )
  local file

  for file in "${required[@]}"; do
    if [ ! -f "$firmware_dir/$file" ]; then
      echo "Missing WLAN firmware file: $firmware_dir/$file" >&2
      echo "Refresh third_party/raspberrypi-firmware/wlan before staging." >&2
      exit 1
    fi
  done

  mkdir -p "$STAGE_DIR/firmware"
  cp "$firmware_dir"/brcmfmac*.bin "$STAGE_DIR/firmware/"
  cp "$firmware_dir"/brcmfmac*.txt "$STAGE_DIR/firmware/"
  cp "$firmware_dir"/brcmfmac*.clm_blob "$STAGE_DIR/firmware/" 2>/dev/null || true
}

stage_modem_audio() {
  mkdir -p "$STAGE_DIR/modem"
  cp "$SRC_DIR/sdcard/modem/hayes_dial.wav" \
    "$SRC_DIR/sdcard/modem/hayes_short_connect.wav" \
    "$SRC_DIR/sdcard/modem/hayes_long_connect.wav" \
    "$STAGE_DIR/modem/"
}

stage_utils_disks() {
  "$SRC_DIR/tools/build_utils_disks.sh" "$STAGE_DIR"
}

stage_licenses() {
  mkdir -p "$STAGE_DIR/licenses"

  cp "$SRC_DIR/sdcard/licenses/bmx.txt" "$STAGE_DIR/licenses/bmx.txt"
  cp "$SRC_DIR/third_party/vice-3.10/COPYING" "$STAGE_DIR/licenses/vice.txt"
  cp "$SRC_DIR/sdcard/licenses/circle.txt" "$STAGE_DIR/licenses/circle.txt"
  cp "$SRC_DIR/sdcard/licenses/tcpser.txt" "$STAGE_DIR/licenses/tcpser.txt"
  cp "$SRC_DIR/utils-disk/LICENCE.ccgms" "$STAGE_DIR/licenses/ccgms.txt"
  cp "$SRC_DIR/THIRD_PARTY_SOURCES.md" "$STAGE_DIR/licenses/third_party_sources.txt"

  if [ -f "$RPI_FIRMWARE_BOOT_DIR/LICENCE.broadcom" ]; then
    cp "$RPI_FIRMWARE_BOOT_DIR/LICENCE.broadcom" "$STAGE_DIR/licenses/broadcom.txt"
  else
    cp "$SRC_DIR/sdcard/licenses/broadcom.txt" "$STAGE_DIR/licenses/broadcom.txt"
  fi
  if [ -f "$RPI_FIRMWARE_BOOT_DIR/COPYING.linux" ]; then
    cp "$RPI_FIRMWARE_BOOT_DIR/COPYING.linux" "$STAGE_DIR/licenses/linux.txt"
  else
    cp "$SRC_DIR/sdcard/licenses/linux.txt" "$STAGE_DIR/licenses/linux.txt"
  fi

}

stage_pi4_hdmi_defaults() {
  local config="$STAGE_DIR/config.txt"
  local tmp="$config.tmp"

  awk '
    /^disable_overscan=1$/ && !seen_hotplug {
      print
      print "hdmi_force_hotplug:0=1"
      print "hdmi_ignore_hotplug:1=1"
      seen_hotplug = 1
      next
    }
    /^hdmi_mode=19$/ && !seen_hdmi0 {
      print
      print "hdmi_group:0=1"
      print "hdmi_mode:0=19"
      print "hdmi_drive:0=2"
      print "hdmi_force_edid_audio:0=1"
      seen_hdmi0 = 1
      next
    }
    { print }
    END {
      if (!seen_hotplug) {
        print "hdmi_force_hotplug:0=1"
        print "hdmi_ignore_hotplug:1=1"
      }
      if (!seen_hdmi0) {
        print "hdmi_group:0=1"
        print "hdmi_mode:0=19"
        print "hdmi_drive:0=2"
        print "hdmi_force_edid_audio:0=1"
      }
    }
  ' "$config" > "$tmp"
  mv "$tmp" "$config"
}

stage_kernels() {
  local suffix

  if [ ! -f "$KERNEL_DIR/kernel7l.img" ]; then
    echo "Missing $KERNEL_DIR/kernel7l.img; run tools/pi4/build_pi4.sh first or pass --kernel-dir." >&2
    exit 1
  fi

  cp "$KERNEL_DIR/kernel7l.img" "$STAGE_DIR/"
  for suffix in c64 c128 vic20 plus4 pet; do
    if [ ! -f "$KERNEL_DIR/kernel7l.img.$suffix" ]; then
      echo "Missing $KERNEL_DIR/kernel7l.img.$suffix; run tools/pi4/build_pi4.sh first or pass --kernel-dir." >&2
      exit 1
    fi
    cp "$KERNEL_DIR/kernel7l.img.$suffix" "$STAGE_DIR/"
  done
}

mkdir -p "$STAGE_DIR/overlays"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/overlays"

cp -a "$SRC_DIR/sdcard/." "$STAGE_DIR/"
stage_pi4_hdmi_defaults
stage_kernels
stage_vice_runtime_files
stage_vice310_raspi_keymaps
stage_wlan_firmware
stage_modem_audio
stage_utils_disks

sed -i '1 s/pi5kms=[^ ]* *//g' "$STAGE_DIR/cmdline.txt"

copy_boot_file "$PI4_BOOT_DIR/start4.elf" "start4.elf"
copy_boot_file "$PI4_BOOT_DIR/fixup4.dat" "fixup4.dat"
copy_boot_file "$PI4_BOOT_DIR/bcm2711-rpi-4-b.dtb" "bcm2711-rpi-4-b.dtb"
copy_boot_file "$PI4_BOOT_DIR/bcm2711-rpi-400.dtb" "bcm2711-rpi-400.dtb"
copy_boot_file "$PI4_BOOT_DIR/bcm2711-rpi-cm4.dtb" "bcm2711-rpi-cm4.dtb"
copy_boot_file "$PI4_BOOT_DIR/armstub7-rpi4.bin" "armstub7-rpi4.bin"
stage_licenses

if [ "$BUILD_PROFILE" = debug ]; then
  if ! grep -q '^enable_uart=1$' "$STAGE_DIR/config.txt"; then
    cat >> "$STAGE_DIR/config.txt" <<'EOF'

enable_uart=1
init_uart_baud=115200
EOF
  fi

  if ! grep -q '^init_uart_baud=' "$STAGE_DIR/config.txt"; then
    echo "init_uart_baud=115200" >> "$STAGE_DIR/config.txt"
  fi

  if ! grep -q '^init_uart_clock=' "$STAGE_DIR/config.txt"; then
    echo "init_uart_clock=48000000" >> "$STAGE_DIR/config.txt"
  fi

  if ! grep -q 'enable_serial=' "$STAGE_DIR/cmdline.txt"; then
    sed -i '1 s/$/ enable_serial=1/' "$STAGE_DIR/cmdline.txt"
  fi

fi

cat >> "$STAGE_DIR/config.txt" <<'EOF'

arm_64bit=0
initial_turbo=0

[pi4]
kernel=kernel7l.img
armstub=armstub7-rpi4.bin
max_framebuffers=2

[cm4]
otg_mode=1
EOF

cat > "$STAGE_DIR/PI4-README.txt" <<'EOF'
This staging directory is a single FAT boot partition for the experimental Pi 4 port.

Contents:
- kernel7l.img
- kernel7l.img.c64
- kernel7l.img.c128
- kernel7l.img.vic20
- kernel7l.img.plus4
- kernel7l.img.pet
- BMC64 sdcard files
- Raspberry Pi 4 firmware files, DTBs and Circle armstub7-rpi4.bin

Pi 4-specific notes:
- 32-bit Circle build for BCM2711 (kernel7l.img)
- config.txt forces arm_64bit=0 and loads armstub7-rpi4.bin
- legacy VC4/DispmanX display path remains enabled
- HDMI audio uses the Circle sound backend
- C64, C128, VIC20, Plus4 and PET VICE kernels/runtime files are staged
EOF

cat > "$STAGE_DIR/BUILD-PROFILE.txt" <<EOF
Build profile: $BUILD_PROFILE

release:
- no staged UART diagnostics
- no second-stage firmware UART logging

debug:
- enables staged UART diagnostics
- leaves second-stage firmware UART logging disabled to avoid noisy serial loss
- enables BMC64 serial logging through enable_serial=1
- leaves networking disabled by default; enable it from the BMX Network menu
EOF

if [ "$BUILD_PROFILE" = debug ]; then
  cat > "$STAGE_DIR/UART-DEBUG.txt" <<'EOF'
UART debug enabled for Pi 4 / Pi 400 staging.

What this enables from the SD card:
- enable_uart=1
- init_uart_baud=115200
- init_uart_clock=48000000
- enable_serial=1
- networking remains off unless enabled from the BMX Network menu

Wiring for a 3.3V USB-TTL adapter:
- Pi pin 6  -> GND
- Pi pin 8  -> adapter RX
- Pi pin 10 -> adapter TX (optional for log capture only)

Serial settings:
- 115200 baud
- 8 data bits
- no parity
- 1 stop bit

Note:
- Second-stage firmware UART logging is intentionally disabled here. It is very
  noisy and can corrupt or interleave the kernel and VICE boot profiling output.
- Early EEPROM bootloader UART output still requires BOOT_UART=1
  in the Pi 4 / Pi 400 EEPROM bootloader configuration.
EOF
fi
