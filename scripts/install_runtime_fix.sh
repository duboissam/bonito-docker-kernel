#!/usr/bin/env bash
set -Eeuo pipefail

DEVICE="${1:-}"
MODULE_DIR="${2:-}"
if [[ -z "$DEVICE" || -z "$MODULE_DIR" || ! -d "$MODULE_DIR" ]]; then
  echo "Usage: $0 <device> /path/to/vendor-modules" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/load_device_config.sh
source "$SCRIPT_DIR/load_device_config.sh"
load_device_config "$DEVICE"

required=(device.env modules.alias modules.dep modules.softdep modules.load)
required+=("${MODULE_ORDER[@]}")
for f in "${required[@]}"; do
  [[ -f "$MODULE_DIR/$f" ]] || { echo "ERROR: missing $MODULE_DIR/$f" >&2; exit 1; }
done

package_device="$(sed -n 's/^DEVICE_ID=//p' "$MODULE_DIR/device.env" | tail -1)"
if [[ "$package_device" != "$DEVICE_ID" ]]; then
  echo "ERROR: module package is for '$package_device', but installer was run for '$DEVICE_ID'" >&2
  exit 1
fi

adb wait-for-device >/dev/null
adb root >/dev/null 2>&1 || true
adb wait-for-device >/dev/null

phone_device="$(adb shell getprop ro.product.device | tr -d '\r')"
ok=0
for allowed in "${ANDROID_DEVICES[@]}"; do
  [[ "$phone_device" == "$allowed" ]] && ok=1
done
if [[ "$ok" != 1 ]]; then
  echo "ERROR: connected device is '$phone_device', expected one of: ${ANDROID_DEVICES[*]}" >&2
  exit 1
fi

remote_base="/data/local/tmp/${DEVICE_ID}-docker"
remote_modules="$remote_base/vendor-modules"
remote_log="$remote_base/modules.log"
remote_release="$remote_base/kernel.release"
remote_version_token="$remote_base/kernel.version-token"

module_order_string="${MODULE_ORDER[*]}"

adb shell "mkdir -p '$remote_modules' /data/adb/service.d /data/adb/post-fs-data.d"
adb push "$MODULE_DIR"/. "$remote_modules"/ >/dev/null
adb shell "uname -r > '$remote_release'"
adb shell "printf '%s\n' '$KBUILD_HOST' > '$remote_version_token'"

adb shell "cat > '$remote_base/modules.sh'" <<EOF
#!/system/bin/sh
LOG=$remote_log
DOCKER=$remote_modules
TARGET=/vendor/lib/modules
KERNEL_RELEASE_FILE=$remote_release
KERNEL_VERSION_TOKEN_FILE=$remote_version_token
PATH=/system/bin:/vendor/bin:/product/bin:/system/xbin
MODULE_ORDER="$module_order_string"
{
  echo "--- \$(date) ---"
  uname -a
  expected_release="\$(cat "\$KERNEL_RELEASE_FILE" 2>/dev/null)"
  current_release="\$(uname -r)"
  echo "expected_kernel=\$expected_release current_kernel=\$current_release"
  if [ -n "\$expected_release" ] && [ "\$current_release" != "\$expected_release" ]; then
    echo "kernel mismatch; not binding Docker modules"
    exit 0
  fi
  expected_token="\$(cat "\$KERNEL_VERSION_TOKEN_FILE" 2>/dev/null)"
  current_version="\$(cat /proc/version 2>/dev/null)"
  echo "expected_version_token=\$expected_token current_version=\$current_version"
  if [ -n "\$expected_token" ] && ! echo "\$current_version" | grep -q "\$expected_token"; then
    echo "kernel build token mismatch; not binding Docker modules"
    exit 0
  fi
  if [ -d "\$DOCKER" ] && [ -d "\$TARGET" ]; then
    chown root:root "\$DOCKER"/* 2>/dev/null
    chmod 0644 "\$DOCKER"/* 2>/dev/null
    mount -o bind "\$DOCKER" "\$TARGET" 2>/dev/null || true
    mount | grep " \$TARGET " || true
  fi
  for m in \$MODULE_ORDER; do
    if [ -f "\$DOCKER/\$m" ]; then
      insmod "\$DOCKER/\$m" 2>&1 || true
    fi
  done
  echo "--- media route check \$(date) ---"
  dumpsys media_router 2>&1 | grep -E "selected route id:|provider info has no routes|ROUTE_ID_BUILTIN_SPEAKER" || true
  if dumpsys media_router 2>/dev/null | grep -q "<provider info has no routes>"; then
    echo "--- restarting framework for media routes \$(date) ---"
    stop
    sleep 5
    start
  else
    echo "--- media routes already valid \$(date) ---"
  fi
  svc wifi enable 2>/dev/null || true
  ls -l "\$TARGET" 2>/dev/null || true
  lsmod 2>/dev/null || cat /proc/modules 2>/dev/null || true
} >> "\$LOG" 2>&1
EOF

adb shell "cat > '$remote_base/route-fix.sh'" <<EOF
#!/system/bin/sh
PATH=/system/bin:/vendor/bin:/product/bin:/system/xbin
while [ "\$(getprop sys.boot_completed)" != "1" ]; do
  sleep 2
done
/system/bin/sh "$remote_base/modules.sh"
EOF

adb shell "cat > '/data/adb/service.d/10-${DEVICE_ID}-modules.sh'" <<EOF
#!/system/bin/sh
PATH=/system/bin:/vendor/bin:/product/bin:/system/xbin
nohup /system/bin/sh "$remote_base/route-fix.sh" >/dev/null 2>&1 &
EOF

adb shell "cat > '/data/adb/post-fs-data.d/00-${DEVICE_ID}-modules.sh'" <<EOF
#!/system/bin/sh
PATH=/system/bin:/vendor/bin:/product/bin:/system/xbin
/system/bin/sh "$remote_base/modules.sh"
EOF

adb shell "
  chown root:root '$remote_base/modules.sh' '$remote_base/route-fix.sh' '/data/adb/service.d/10-${DEVICE_ID}-modules.sh' '/data/adb/post-fs-data.d/00-${DEVICE_ID}-modules.sh'
  chmod 755 '$remote_base/modules.sh' '$remote_base/route-fix.sh' '/data/adb/service.d/10-${DEVICE_ID}-modules.sh' '/data/adb/post-fs-data.d/00-${DEVICE_ID}-modules.sh'
  chown root:root '$remote_modules'/*
  chmod 644 '$remote_modules'/*
  ls -l '/data/adb/service.d/10-${DEVICE_ID}-modules.sh' '/data/adb/post-fs-data.d/00-${DEVICE_ID}-modules.sh' '$remote_base/modules.sh'
"

echo "Installed $DEVICE_ID runtime module and MediaRouter recovery scripts."
echo "Reboot, then verify: adb shell dumpsys media_router | grep ROUTE_ID_BUILTIN_SPEAKER"
