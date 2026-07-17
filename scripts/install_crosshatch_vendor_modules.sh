#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="${1:-}"
if [[ -z "$MODULE_DIR" || ! -d "$MODULE_DIR" ]]; then
  echo "Usage: $0 /path/to/vendor-modules" >&2
  exit 2
fi

required=(
  modules.alias modules.dep modules.softdep
  pinctrl-wcd.ko snd-soc-cs35l36.ko snd-soc-sdm845-max98927.ko
  snd-soc-sdm845.ko snd-soc-wcd-spi.ko snd-soc-wcd934x.ko
  snd-soc-wcd9xxx.ko wcd-core.ko wcd-dsp-glink.ko wlan.ko
)

for file in "${required[@]}"; do
  if [[ ! -f "$MODULE_DIR/$file" ]]; then
    echo "ERROR: missing $MODULE_DIR/$file" >&2
    exit 1
  fi
done

adb root
adb wait-for-device

serial="$(adb shell getprop ro.serialno | tr -d '\r')"
device="$(adb shell getprop ro.product.device | tr -d '\r')"
if [[ "$device" != "crosshatch" ]]; then
  echo "ERROR: connected device is '$device', expected crosshatch" >&2
  exit 1
fi

stamp="$(date -u +%Y%m%d-%H%M%S)"
backup="/data/local/tmp/vendor-modules-backup-${serial:-crosshatch}-$stamp"
adb shell "mkdir -p '$backup' && cp -a /vendor/lib/modules/. '$backup/'"
echo "Backed up current phone modules to $backup"

if ! adb remount; then
  echo "ERROR: adb remount failed. The phone may need 'adb disable-verity' and a reboot before /vendor can be updated." >&2
  exit 1
fi

adb push "$MODULE_DIR"/. /vendor/lib/modules/
adb shell 'chown root:root /vendor/lib/modules/* && chmod 0644 /vendor/lib/modules/* && sync'
adb shell 'ls -l /vendor/lib/modules'
echo "Installed matched crosshatch vendor modules. Reboot to load them from init."
