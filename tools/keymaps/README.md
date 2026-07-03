Keymap Runtime Sources
======================

`raspi/` contains hand-maintained Raspberry Pi keyboard maps that are staged
onto the SD card for the enabled VICE machines.

Keep `sdcard/` for the minimal static boot tree (`config.txt`, `cmdline.txt`,
`machines.txt` and bootstat files). Keymaps live here because some are used as
generator input and should not be mixed with the pre-stage SD-card skeleton.

The staging scripts copy `tools/keymaps/raspi/` into the stage directory and
then copy VICE 3.10 `gtk3_*.vkm` files from `third_party/vice-3.10/data`.
`generate_raspi_keymaps.py` derives the per-machine positional US/DE maps from
the C64 reference maps in `tools/keymaps/raspi/c64/`.
