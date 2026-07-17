#!/usr/bin/env bash
set -Eeuo pipefail

KERNEL_DIR="${1:-}"
if [[ -z "$KERNEL_DIR" ]]; then
  echo "Usage: $0 /path/to/android_kernel_google_msm-4.9" >&2
  exit 2
fi

KERNEL_DIR="$(cd "$KERNEL_DIR" && pwd)"
cd "$KERNEL_DIR"

DEFCONFIG="arch/arm64/configs/b1c1_defconfig"
OUT="${OUT:-$KERNEL_DIR/out-docker}"

[[ -f Makefile ]] || { echo "Not a kernel tree"; exit 1; }
[[ -x scripts/config ]] || { echo "scripts/config missing"; exit 1; }
[[ -f "$DEFCONFIG" ]] || { echo "$DEFCONFIG missing"; exit 1; }

mkdir -p "$OUT"
cp "$DEFCONFIG" "$DEFCONFIG.backup.$(date +%Y%m%d-%H%M%S)"

symbol_exists() {
  grep -Rqs --include='Kconfig*' -E "^[[:space:]]*(menu)?config[[:space:]]+$1([[:space:]]|$)" .
}

enable() {
  if symbol_exists "$1"; then
    scripts/config --file "$DEFCONFIG" --enable "$1"
    echo "enabled CONFIG_$1"
  else
    echo "skipped CONFIG_$1 (not present)"
  fi
}

required=(
  NAMESPACES UTS_NS IPC_NS PID_NS NET_NS
  CGROUPS CGROUP_FREEZER CGROUP_DEVICE CGROUP_CPUACCT CGROUP_SCHED
  CGROUP_PIDS CPUSETS MEMCG MEMCG_SWAP BLK_CGROUP
  BRIDGE BRIDGE_NETFILTER VETH
  NETFILTER NETFILTER_XTABLES NF_CONNTRACK NF_NAT
  IP_NF_IPTABLES IP_NF_FILTER IP_NF_MANGLE IP_NF_RAW IP_NF_NAT
  OVERLAY_FS EXT4_FS TMPFS KEYS POSIX_MQUEUE
)

recommended=(
  USER_NS SECCOMP SECCOMP_FILTER
  TUN MACVLAN VXLAN DUMMY IKCONFIG IKCONFIG_PROC
  NF_NAT_IPV4 NF_NAT_NEEDED IP_NF_TARGET_MASQUERADE
  NETFILTER_XT_TARGET_MASQUERADE NETFILTER_XT_MATCH_ADDRTYPE
  NETFILTER_XT_MATCH_CONNTRACK NETFILTER_XT_MARK NETFILTER_XT_TARGET_MARK
)

for s in "${required[@]}"; do enable "$s"; done
for s in "${recommended[@]}"; do enable "$s"; done

# This Android 4.9 tree enables Clang LTO by default, but its compiler check
# expects the obsolete GNU gold linker. LTO is not required for Docker and
# disabling it makes the kernel build reliably with the modern LLVM toolchain.
for s in LTO LTO_CLANG THINLTO; do
  if symbol_exists "$s"; then
    scripts/config --file "$DEFCONFIG" --disable "$s"
    echo "disabled CONFIG_$s"
  fi
done

# The Android 4.9 compiler probe can reject stack-protector flags with some
# Clang/prebuilt combinations. Docker support does not require stack canaries,
# so prefer a buildable kernel over forcing a protector mode the toolchain
# cannot pass.
if symbol_exists CC_STACKPROTECTOR_STRONG; then
  scripts/config --file "$DEFCONFIG" --disable CC_STACKPROTECTOR_STRONG
  echo "disabled CONFIG_CC_STACKPROTECTOR_STRONG"
fi
if symbol_exists CC_STACKPROTECTOR_REGULAR; then
  scripts/config --file "$DEFCONFIG" --disable CC_STACKPROTECTOR_REGULAR
  echo "disabled CONFIG_CC_STACKPROTECTOR_REGULAR"
fi
if symbol_exists CC_STACKPROTECTOR_NONE; then
  scripts/config --file "$DEFCONFIG" --enable CC_STACKPROTECTOR_NONE
  echo "enabled CONFIG_CC_STACKPROTECTOR_NONE"
fi
if symbol_exists SHADOW_CALL_STACK; then
  scripts/config --file "$DEFCONFIG" --disable SHADOW_CALL_STACK
  echo "disabled CONFIG_SHADOW_CALL_STACK"
fi

# The stock LineageOS vendor partition supplies Wi-Fi/audio modules. Enabling
# Docker options changes symbol CRCs, so keep the kernel from rejecting those
# existing vendor modules solely because CONFIG_MODVERSIONS CRCs no longer match.
if symbol_exists MODVERSIONS; then
  scripts/config --file "$DEFCONFIG" --disable MODVERSIONS
  echo "disabled CONFIG_MODVERSIONS"
fi

QTAGUID="net/netfilter/xt_qtaguid.c"
if [[ -f "$QTAGUID" ]]; then
python3 - "$QTAGUID" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
t = p.read_text()
m = re.search(r'(static\s+int\s+proc_iface_stats_seq_show\s*\([^)]*\)\s*\{)(.*?)(\n\})', t, re.S)
if not m:
    print("WARNING: qtaguid function not found; patch manually")
    raise SystemExit(0)

b = m.group(2)
if "stats = &no_dev_stats;" in b and "dev_get_stats(iface_entry->net_dev" not in b:
    print("qtaguid workaround already present")
    raise SystemExit(0)

b = re.sub(r'struct\s+rtnl_link_stats64\s+dev_stats\s*,\s*\*stats\s*;',
           'struct rtnl_link_stats64 *stats;', b)

pat = (r'if\s*\(\s*iface_entry->active\s*\)\s*\{\s*'
       r'stats\s*=\s*dev_get_stats\s*\(\s*iface_entry->net_dev\s*,\s*&dev_stats\s*\)\s*;\s*'
       r'\}\s*else\s*\{\s*stats\s*=\s*&no_dev_stats\s*;\s*\}')
b2, n = re.subn(pat, 'stats = &no_dev_stats;', b, count=1, flags=re.S)
if not n:
    print("WARNING: qtaguid layout not recognised; patch manually")
    raise SystemExit(0)

backup = p.with_suffix(p.suffix + ".docker-backup")
if not backup.exists():
    backup.write_text(t)
p.write_text(t[:m.start(2)] + b2 + t[m.end(2):])
print("qtaguid workaround applied")
PY
fi

VDSO32_MAKEFILE="arch/arm64/kernel/vdso32/Makefile"
if [[ -f "$VDSO32_MAKEFILE" ]]; then
python3 - "$VDSO32_MAKEFILE" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text()
old = "  CC_ARM32 := $(CC) $(CLANG_TARGET_ARM32) -no-integrated-as $(CLANG_GCC32_TC) $(CLANG_PREFIX32)"
new = "  CC_ARM32 := $(CC) --target=arm-linux-gnueabi -B/usr/bin/arm-linux-gnueabi- --gcc-toolchain=/usr $(CLANG_TARGET_ARM32) $(CLANG_GCC32_TC) $(CLANG_PREFIX32)"
if new in t:
    print("vdso32 clang assembler workaround already present")
elif old in t:
    backup = p.with_suffix(p.suffix + ".docker-backup")
    if not backup.exists():
        backup.write_text(t)
    p.write_text(t.replace(old, new, 1))
    print("vdso32 clang assembler workaround applied")
else:
    print("WARNING: vdso32 Makefile layout not recognised; patch manually")
PY
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  short_head="$(git rev-parse --short=12 HEAD)"
  printf '%s\n' "-g${short_head}" > .scmversion
  echo "Pinned kernel localversion to -g${short_head}"
fi

make O="$OUT" ARCH=arm64 b1c1_defconfig
make O="$OUT" ARCH=arm64 olddefconfig
make O="$OUT" ARCH=arm64 savedefconfig
cp "$OUT/defconfig" "$DEFCONFIG"

fail=0
for s in IPC_NS PID_NS CGROUP_DEVICE BRIDGE_NETFILTER CGROUPS MEMCG VETH BRIDGE OVERLAY_FS; do
  if grep -Eq "^CONFIG_${s}=(y|m)$" "$OUT/.config"; then
    echo "OK CONFIG_$s"
  else
    echo "MISSING CONFIG_$s"
    fail=1
  fi
done

echo "Patched: $DEFCONFIG"
echo "Resolved config: $OUT/.config"
(( fail == 0 )) || exit 1

echo "Next: run ./build_bluecross.sh in the kernel tree."
