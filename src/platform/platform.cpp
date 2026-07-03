#include "platform/platform.h"

namespace bmc64 {

namespace {

#if RASPPI == 5
constexpr PlatformDescriptor kPlatform = {
    "pi5",
    5,
    false,
    true,
    "kernel_2712.img",
};
#else
constexpr PlatformDescriptor kPlatform = {
    "pi4",
    4,
    false,
    false,
    "kernel7l.img",
};
#endif

}  // namespace

const PlatformDescriptor &CurrentPlatform() {
  return kPlatform;
}

int VolumePercentToDeviceControl(int percent) {
  return percent;
}

}  // namespace bmc64
