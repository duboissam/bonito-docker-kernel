#!/usr/bin/env bash
set -Eeuo pipefail

KERNEL_OUT="${1:-}"
DEST="${2:-}"
if [[ -z "$KERNEL_OUT" || -z "$DEST" ]]; then
  echo "Usage: $0 /path/to/kernel/out-docker /path/to/vendor-modules" >&2
  exit 2
fi

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

sources=(
  "wlan.ko:drivers/staging/qcacld-3.0/wlan.ko"
  "wcd-dsp-glink.ko:techpack/audio/ipc/wcd-dsp-glink.ko"
  "pinctrl-wcd.ko:techpack/audio/soc/pinctrl-wcd.ko"
  "wcd-core.ko:techpack/audio/asoc/codecs/wcd-core.ko"
  "snd-soc-cs35l36.ko:techpack/audio/asoc/codecs/snd-soc-cs35l36.ko"
  "snd-soc-wcd934x.ko:techpack/audio/asoc/codecs/wcd934x/snd-soc-wcd934x.ko"
  "snd-soc-wcd-spi.ko:techpack/audio/asoc/codecs/snd-soc-wcd-spi.ko"
  "snd-soc-wcd9xxx.ko:techpack/audio/asoc/codecs/snd-soc-wcd9xxx.ko"
  "snd-soc-sdm845.ko:techpack/audio/asoc/snd-soc-sdm845.ko"
  "snd-soc-sdm845-max98927.ko:techpack/audio/asoc/snd-soc-sdm845-max98927.ko"
)

for entry in "${sources[@]}"; do
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

cat > "$DEST/modules.dep" <<'EOF'
/vendor/lib/modules/snd-soc-cs35l36.ko:
/vendor/lib/modules/snd-soc-sdm845.ko: /vendor/lib/modules/snd-soc-wcd934x.ko /vendor/lib/modules/snd-soc-wcd9xxx.ko /vendor/lib/modules/wcd-core.ko
/vendor/lib/modules/snd-soc-wcd9xxx.ko: /vendor/lib/modules/wcd-core.ko
/vendor/lib/modules/wcd-core.ko:
/vendor/lib/modules/snd-soc-wcd934x.ko: /vendor/lib/modules/snd-soc-wcd9xxx.ko /vendor/lib/modules/wcd-core.ko
/vendor/lib/modules/snd-soc-wcd-spi.ko:
/vendor/lib/modules/pinctrl-wcd.ko:
/vendor/lib/modules/wlan.ko:
/vendor/lib/modules/snd-soc-sdm845-max98927.ko: /vendor/lib/modules/snd-soc-wcd934x.ko /vendor/lib/modules/snd-soc-wcd9xxx.ko /vendor/lib/modules/wcd-core.ko
/vendor/lib/modules/wcd-dsp-glink.ko:
EOF

cat > "$DEST/modules.softdep" <<'EOF'
# Soft dependencies extracted from modules themselves.
EOF

cat > "$DEST/modules.alias" <<'EOF'
# Aliases extracted from modules themselves.
alias of:N*T*Ccirrus,cs35l36 snd_soc_cs35l36
alias of:N*T*Ccirrus,cs35l36C* snd_soc_cs35l36
alias i2c:cs35l36 snd_soc_cs35l36
alias platform:sdm845-asoc-snd snd_soc_sdm845
alias of:N*T*Cqcom,sdm845-asoc-snd-tavil snd_soc_sdm845
alias of:N*T*Cqcom,sdm845-asoc-snd-tavilC* snd_soc_sdm845
alias of:N*T*Cqcom,sdm845-asoc-snd-stub snd_soc_sdm845
alias of:N*T*Cqcom,sdm845-asoc-snd-stubC* snd_soc_sdm845
alias of:N*T*Cqcom,wcd-dsp-mgr snd_soc_wcd9xxx
alias of:N*T*Cqcom,wcd-dsp-mgrC* snd_soc_wcd9xxx
alias of:N*T*Cqcom,audio-ref-clk snd_soc_wcd9xxx
alias of:N*T*Cqcom,audio-ref-clkC* snd_soc_wcd9xxx
alias of:N*T*Cqcom,tavil-i2c wcd_core
alias of:N*T*Cqcom,tavil-i2cC* wcd_core
alias of:N*T*Cqcom,tasha-i2c-pgd wcd_core
alias of:N*T*Cqcom,tasha-i2c-pgdC* wcd_core
alias of:N*T*Cqcom,wcd9xxx-i2c wcd_core
alias of:N*T*Cqcom,wcd9xxx-i2cC* wcd_core
alias i2c:tabla top level wcd_core
alias i2c:tabla analog wcd_core
alias i2c:tabla digital1 wcd_core
alias i2c:tabla digital2 wcd_core
alias of:N*T*Cqcom,wcd-spi-v2 snd_soc_wcd_spi
alias of:N*T*Cqcom,wcd-spi-v2C* snd_soc_wcd_spi
alias of:N*T*Cqcom,wcd-pinctrl pinctrl_wcd
alias of:N*T*Cqcom,wcd-pinctrlC* pinctrl_wcd
alias platform:sdm845-asoc-snd-max9827 snd_soc_sdm845_max98927
alias of:N*T*Cqcom,sdm845-asoc-snd-tavil-max98927 snd_soc_sdm845_max98927
alias of:N*T*Cqcom,sdm845-asoc-snd-tavil-max98927C* snd_soc_sdm845_max98927
alias of:N*T*Cqcom,sdm845-asoc-snd-stub snd_soc_sdm845_max98927
alias of:N*T*Cqcom,sdm845-asoc-snd-stubC* snd_soc_sdm845_max98927
alias of:N*T*Cqcom,wcd-dsp-glink wcd_dsp_glink
alias of:N*T*Cqcom,wcd-dsp-glinkC* wcd_dsp_glink
EOF

find "$DEST" -type f -print | sort
