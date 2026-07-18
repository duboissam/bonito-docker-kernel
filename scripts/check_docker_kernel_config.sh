#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${1:-}"
if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
  echo "Usage: $0 /path/to/kernel.config" >&2
  exit 2
fi

has_enabled() {
  grep -Eq "^CONFIG_$1=(y|m)$" "$CONFIG_FILE"
}

has_symbol() {
  grep -Eq "^(CONFIG_$1=|# CONFIG_$1 is not set)" "$CONFIG_FILE"
}

required=(
  NAMESPACES UTS_NS IPC_NS PID_NS NET_NS SYSVIPC
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
  NETFILTER_XT_MATCH_CGROUP
)

fail=0
warn=0

echo "Required Docker kernel features:"
for symbol in "${required[@]}"; do
  if has_enabled "$symbol"; then
    printf '  OK       CONFIG_%s\n' "$symbol"
  elif has_symbol "$symbol"; then
    printf '  MISSING  CONFIG_%s is present but disabled\n' "$symbol"
    fail=1
  else
    printf '  ABSENT   CONFIG_%s does not exist in this kernel tree/config\n' "$symbol"
    fail=1
  fi
done

echo
echo "Recommended / useful Docker kernel features:"
for symbol in "${recommended[@]}"; do
  if has_enabled "$symbol"; then
    printf '  OK       CONFIG_%s\n' "$symbol"
  elif has_symbol "$symbol"; then
    printf '  WARN     CONFIG_%s is present but disabled\n' "$symbol"
    warn=1
  else
    printf '  SKIP     CONFIG_%s does not exist in this kernel tree/config\n' "$symbol"
  fi
done

echo
if (( fail != 0 )); then
  echo "Result: not Docker-ready. Required kernel features are missing or disabled."
  exit 1
fi

if (( warn != 0 )); then
  echo "Result: required features are present, but some recommended features are disabled."
else
  echo "Result: required and recommended checked features are enabled."
fi
