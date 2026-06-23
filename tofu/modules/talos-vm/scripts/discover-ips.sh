#!/usr/bin/env bash
#
# Lists DHCP leases on the slam-stack network and cross-references with
# the expected MAC→IP mapping from tofu output.
#
# Run AFTER `tofu apply` and AFTER the Talos nodes have finished booting.
# Exit 0 if all expected MACs have leases matching the expected IP.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-slam-stack}"
NETWORK="${CLUSTER_NAME}-talos-net"
TOFU_DIR="${TOFU_DIR:-$(dirname "$(dirname "$(readlink -f "$0")")")}"

cd "$TOFU_DIR"

echo "[discover-ips] network: $NETWORK"
echo

EXPECTED=$(tofu output -json expected_node_ips_by_mac 2>/dev/null || terraform output -json expected_node_ips_by_mac)
LEASES=$(virsh -c qemu:///system net-dhcp-leases --network "$NETWORK" \
  | awk 'NR>2 && $1!="" {print $2","$5}' | tr -d ' ')

EXIT=0
printf "%-20s %-15s %-15s %s\n" "MAC" "EXPECTED" "LEASED" "STATUS"
printf "%-20s %-15s %-15s %s\n" "---" "--------" "------" "------"

echo "$EXPECTED" | python3 -c "
import json, sys
expected = json.load(sys.stdin)
leases_raw = '''$LEASES'''
leases = {}
for line in leases_raw.split(','):
    parts = line.split(',')
    if len(parts) == 2:
        mac, ip = parts
        leases[mac.lower()] = ip.strip()

exit_code = 0
for mac, expected_ip in expected.items():
    leased = leases.get(mac.lower(), '—')
    status = 'OK' if leased == expected_ip else 'MISMATCH'
    if status != 'OK':
        exit_code = 1
    print(f'{mac:<20} {expected_ip:<15} {licensed:<15} {status}'.replace('licensed', 'leased'))
sys.exit(exit_code)
" || EXIT=$?

echo
if [[ $EXIT -eq 0 ]]; then
  echo "[discover-ips] all nodes reachable at expected IPs — ready for talosctl apply-config"
else
  echo "[discover-ips] some nodes not yet at expected IPs — wait a few seconds and re-run" >&2
fi
exit $EXIT
