#!/usr/bin/env bash
# Aggressively poll for FEL and, the instant it appears, run the OpenWrt NAND
# flash. This board's FEL power collapses ~1-2s after entering FEL (AXP),
# so we hammer `sunxi-fel ver` and launch the flasher within ~100ms of seeing
# the device -- once the flasher SPL runs it reconfigures the PMIC and power
# holds for the rest of the flash.
#
# Usage: 38-fel-catch-flash-openwrt.sh [max_seconds]   (default 600)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MAX="${1:-600}"

echo "Waiting for FEL (up to ${MAX}s). Power-cycle the board into FEL now."
deadline=$(( $(date +%s) + MAX ))
n=0
while [ "$(date +%s)" -lt "$deadline" ]; do
    n=$((n+1))
    if "$FEL" ver >/dev/null 2>&1; then
        echo "FEL caught on attempt $n -> launching flash"
        exec "$HERE/37-fel-flash-openwrt.sh"
    fi
    sleep 0.1
done
echo "FEL not detected within ${MAX}s. Re-run when ready." >&2
exit 1
