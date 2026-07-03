# Pi 5 HDMI Modeset

The Pi 5/Pi 500 stage enables Pi5KMS by default with `pi5kms=1` in
`cmdline.txt`. Pi5KMS switches the real HDMI scanout mode before the framebuffer
is initialized, so the selected BMC HDMI mode is applied on Pi 5-class boards.

If a monitor or capture device does not work with Pi5KMS, set `pi5kms=0` in the
first line of `cmdline.txt` or remove the option. The Pi 5 port then keeps
Circle's firmware-provided HDMI mode and scales the emulator image into that
framebuffer.

When Pi5KMS is enabled, BMX allocates its own 16-bit RGB565 scanout framebuffer
and programs HVS display 0 directly. The normal Circle firmware framebuffer path
is used when `pi5kms=1` is not present or when `pi5kms=0` is set.

The framebuffer API is intentionally kept inside `src/pi5kms`: callers request
a mode, create a framebuffer, attach RGB565 scanout planes to HVS display 0,
write pixels, and flush the framebuffer when the CPU has updated it. BMC64-ng
uses that API instead of managing the KMS buffer, pitch, display-list setup, and
cache synchronization itself.

The scanout API is plane-based so `pi5kms` can stay reusable outside BMX. The
legacy framebuffer helper is a convenience wrapper around a single full-screen
RGB565 plane. Source crops and destination positions are validated centrally.
Scaled single planes are supported through the HVS scaler. Nearest-neighbor
uses the HVS no-interpolation filter, while interpolated output uploads a
Mitchell/Netravali-style PPF kernel derived from the Raspberry Pi VC4 driver.
The current BMX renderer uses this hardware path when exactly one opaque layer
is visible. It falls back to the existing software compositor when multiple
layers, transparent overlays, or menu/status layers are active.

## Runtime Options

| Option | Meaning |
| --- | --- |
| `pi5kms=1` | Enable Pi 5 HDMI modeset. This is the staged Pi5/Pi500 default. |
| `pi5kms=0` | Disable Pi5KMS and use Circle's firmware-provided framebuffer path. |
| `hdmi_group=<n>` | BMC/Raspberry Pi HDMI mode group. Currently `1` for CEA and `2` with mode `87` for custom timings. |
| `hdmi_mode=<n>` | BMC/Raspberry Pi HDMI mode number. |
| `pi5kms_mode=<name>` | Optional named Pi5KMS mode. This overrides `hdmi_group`/`hdmi_mode`. |
| `pi5kms_timings=<values>` | Custom timing values copied from `hdmi_timings`, but comma-separated for `cmdline.txt`. |
| `scaling_params=...` | Existing BMC64 scaling parameters. They are still applied after the HDMI scanout mode is switched. |
| `scaling_params2=...` | Existing second-display scaling parameters, used by C128/PET where applicable. |

Example using the active BMC menu mode:

```text
pi5kms=1 hdmi_group=1 hdmi_mode=19
```

Example forcing a 16:10 mode manually:

```text
pi5kms=1 pi5kms_mode=1280x800@60
```

Example custom timing:

```text
pi5kms=1 hdmi_group=2 hdmi_mode=87 pi5kms_timings=768,0,24,72,96,525,1,3,10,9,0,0,0,60,0,31416828,1
```

The machine switcher keeps `hdmi_group`, `hdmi_mode`, and custom timings in
`cmdline.txt` in sync with the selected entry from `machines.txt`. Existing
manual options such as `pi5kms=1` and `pi5kms_mode=...` are preserved.

## Supported Standard Modes

| BMC option | Mode | Pixel clock | Notes |
| --- | --- | --- | --- |
| `hdmi_group=1 hdmi_mode=4` | 1280x720@60 | 74.25 MHz | CEA 720p60, 16:9 |
| `hdmi_group=1 hdmi_mode=19` | 1280x720@50 | 74.25 MHz | CEA 720p50, 16:9 |
| `hdmi_group=1 hdmi_mode=16` | 1920x1080@60 | 148.5 MHz | CEA 1080p60, 16:9 |
| `hdmi_group=1 hdmi_mode=31` | 1920x1080@50 | 148.5 MHz | CEA 1080p50, 16:9 |

## Supported Named 16:10 Modes

| `pi5kms_mode` | Mode | Pixel clock | Timing source |
| --- | --- | --- | --- |
| `1280x800@60` | 1280x800@59.81 | 83.50 MHz | CVT |
| `1280x800@50` | 1280x800@49.95 | 68.00 MHz | CVT |
| `1920x1200@60` | 1920x1200@59.88 | 193.25 MHz | CVT |
| `1920x1200@50` | 1920x1200@49.93 | 158.25 MHz | CVT |

Monitor OSDs commonly round the CVT modes to 59.9Hz/60Hz or 50Hz.

## `hdmi_timings` Field Layout

The BMC custom modes use the Raspberry Pi `hdmi_timings` layout. In
`machines.txt` the values are space-separated; in `cmdline.txt` they are stored
as comma-separated `pi5kms_timings`.

| Index | Field | Used by Pi5KMS |
| --- | --- | --- |
| 0 | width | yes |
| 1 | hsync polarity | yes |
| 2 | horizontal front porch | yes |
| 3 | horizontal sync width | yes |
| 4 | horizontal back porch | yes |
| 5 | height | yes |
| 6 | vsync polarity | yes |
| 7 | vertical front porch | yes |
| 8 | vertical sync width | yes |
| 9 | vertical back porch | yes |
| 10 | vertical sync offset A | no |
| 11 | vertical sync offset B | no |
| 12 | pixel repetition | no |
| 13 | frame rate hint | no |
| 14 | interlace flag | no |
| 15 | pixel clock | yes |
| 16 | aspect ratio | no |

Pi5KMS currently programs progressive RGB HDMI modes only. Composite entries in
`machines.txt` are not converted to native composite output on Pi 5.

## BMC Custom Timing Table

| Machine | Standard | BMC menu mode | `hdmi_timings` |
| --- | --- | --- | --- |
| VIC20 | NTSC | 768x525@60.285Hz | `768 0 24 72 96 525 1 3 10 9 0 0 0 60 0 31656857 1` |
| VIC20 | PAL | 768x545@50.037Hz | `768 0 24 72 96 545 1 3 2 13 0 0 0 50 0 27043926 1` |
| C64 | NTSC | 768x525@59.827Hz | `768 0 24 72 96 525 1 3 10 9 0 0 0 60 0 31416828 1` |
| C64 | PAL | 768x545@50.125Hz | `768 0 24 72 96 545 1 3 2 13 0 0 0 50 0 27091697 1` |
| C128 | NTSC | 768x525@59.827Hz | `768 0 24 72 96 525 1 3 10 9 0 0 0 60 0 31416828 1` |
| C128 | PAL | 768x545@50.125Hz | `768 0 24 72 96 545 1 3 2 13 0 0 0 50 0 27091697 1` |
| PLUS4 | NTSC | 768x525@59.923Hz | `768 0 24 72 96 525 1 3 10 9 0 0 0 60 0 31467501 1` |
| PLUS4 | PAL | 768x545@49.860Hz | `768 0 24 72 96 545 1 3 2 13 0 0 0 50 0 26948856 1` |
| PET | NTSC | 768x525@60.060Hz | `768 0 24 72 96 525 1 3 10 9 0 0 0 60 0 31538738 1` |
| PET | PAL | 768x545@49.875Hz | `768 0 24 72 96 545 1 3 2 13 0 0 0 50 0 26956913 1` |

## Verified Sweep Result

The standalone sweep in `tools/pi5/modeset-test` was tested on a Raspberry Pi
500 on 2026-05-29. The monitor reported all standard, 16:10, and BMC custom
modes as valid scanout changes. See `tools/pi5/modeset-test/README.md` for the
full sequence and OSD results.
