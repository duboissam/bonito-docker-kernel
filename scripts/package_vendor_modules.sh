#!/usr/bin/env bash
set -Eeuo pipefail

DEVICE="${1:-}"
KERNEL_OUT="${2:-}"
DEST="${3:-}"
if [[ -z "$DEVICE" || -z "$KERNEL_OUT" || -z "$DEST" ]]; then
  echo "Usage: $0 <device> /path/to/kernel/out-docker /path/to/vendor-modules" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/load_device_config.sh
source "$SCRIPT_DIR/load_device_config.sh"
load_device_config "$DEVICE"

KERNEL_OUT="$(cd "$KERNEL_OUT" && pwd)"
rm -rf "$DEST"
mkdir -p "$DEST"

strip_tool="${STRIP_TOOL:-}"
if [[ -z "$strip_tool" ]]; then
  for candidate in llvm-strip aarch64-linux-gnu-strip; do
    if command -v "$candidate" >/dev/null 2>&1; then
      strip_tool="$candidate"
      break
    fi
  done
fi

if [[ -z "$strip_tool" ]]; then
  echo "ERROR: llvm-strip or aarch64-linux-gnu-strip is required to package phone-sized modules" >&2
  exit 1
fi

for entry in "${MODULE_SPECS[@]}"; do
  module="${entry%%:*}"
  rel="${entry#*:}"
  src="$KERNEL_OUT/$rel"
  if [[ ! -f "$src" ]]; then
    echo "ERROR: missing built module $src" >&2
    exit 1
  fi
  cp "$src" "$DEST/$module"
  "$strip_tool" --strip-unneeded "$DEST/$module"
done

: > "$DEST/modules.dep"
for module in "${MODULE_ORDER[@]}"; do
  echo "/vendor/lib/modules/$module:" >> "$DEST/modules.dep"
done

cat > "$DEST/modules.softdep" <<'EOF'
# Explicit load order is handled by the runtime installer.
EOF

cat > "$DEST/modules.alias" <<'EOF'
# Runtime installer loads modules explicitly.
EOF

printf '%s\n' "${MODULE_ORDER[@]}" > "$DEST/modules.load"
cat > "$DEST/device.env" <<EOF
DEVICE_ID=$DEVICE_ID
DEVICE_LABEL=$DEVICE_LABEL
DEFCONFIG=$DEFCONFIG
KERNEL_REPO=$KERNEL_REPO
EOF

find "$DEST" -type f -print | sort
