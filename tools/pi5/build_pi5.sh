#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STAGE_ARGS=()
BUILD_PROFILE="${BMC64_BUILD_PROFILE:-release}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--profile release|debug] [--debug-uart] [--stage-dir DIR]

Builds Pi5/Pi500 VICE 3.10 kernels and stages a boot tree.

Options:
  --profile      staging boot config profile (default: release)
  --debug-uart   alias for --profile debug
  --stage-dir    override the output staging directory
EOF
}

while (($# > 0)); do
  case "$1" in
    --profile)
      if [ -z "${2:-}" ]; then
        echo "--profile requires release or debug" >&2
        exit 1
      fi
      case "$2" in
        release|debug) ;;
        *)
          echo "--profile requires release or debug" >&2
          exit 1
          ;;
      esac
      BUILD_PROFILE="$2"
      STAGE_ARGS+=("--profile" "$2")
      shift 2
      ;;
    --debug-uart)
      BUILD_PROFILE=debug
      STAGE_ARGS+=("--profile" "debug")
      shift
      ;;
    --stage-dir)
      if [ -z "${2:-}" ]; then
        echo "--stage-dir requires a directory" >&2
        exit 1
      fi
      STAGE_ARGS+=("--stage-dir" "$2")
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

cat <<'EOF'
Building Pi5/Pi500 VICE 3.10 kernels.

Currently wired VICE 3.10 machines: C64, C128, VIC20, Plus/4, PET.
EOF

. "$SRC_DIR/tools/pi5/vice310_build_common.sh"

export BMC64_BUILD_PROFILE="$BUILD_PROFILE"
build_vice310_machines c64 c128 vic20 plus4 pet
"$SRC_DIR/tools/pi5/stage_pi5_sd.sh" "${STAGE_ARGS[@]}"
