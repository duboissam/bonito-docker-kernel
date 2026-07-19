#!/usr/bin/env bash

load_device_config() {
  local device="${1:-}"
  if [[ -z "$device" ]]; then
    echo "ERROR: device is required" >&2
    return 2
  fi

  local script_dir root
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  root="${GITHUB_WORKSPACE:-$(cd "$script_dir/.." && pwd)}"
  local config="$root/device-configs/$device.env"
  if [[ ! -f "$config" ]]; then
    echo "ERROR: unsupported device '$device'" >&2
    echo "Available device configs:" >&2
    find "$root/device-configs" -maxdepth 1 -name '*.env' -print 2>/dev/null | sed 's#.*/##; s#\.env$##' | sort >&2
    return 1
  fi

  # shellcheck source=/dev/null
  source "$config"

  : "${DEVICE_ID:?missing DEVICE_ID}"
  : "${DEVICE_LABEL:?missing DEVICE_LABEL}"
  : "${KERNEL_REPO:?missing KERNEL_REPO}"
  : "${DEFAULT_KERNEL_REF:?missing DEFAULT_KERNEL_REF}"
  : "${DEFCONFIG:?missing DEFCONFIG}"
  : "${KBUILD_HOST:?missing KBUILD_HOST}"
  [[ "${#ANDROID_DEVICES[@]}" -gt 0 ]] || { echo "ERROR: ANDROID_DEVICES is empty" >&2; return 1; }
  [[ "${#MODULE_ORDER[@]}" -gt 0 ]] || { echo "ERROR: MODULE_ORDER is empty" >&2; return 1; }
  [[ "${#MODULE_SPECS[@]}" -gt 0 ]] || { echo "ERROR: MODULE_SPECS is empty" >&2; return 1; }
}
