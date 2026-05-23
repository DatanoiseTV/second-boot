#!/usr/bin/env bash
# Fetch external sources on the build host. Run ON the remote VM.
#
#   ssh syso@10.243.243.8 'bash -s' < scripts/01-fetch-sources.sh
#
# Or copy the whole scripts/ tree across and run there.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

ensure_dir "$SOURCES_DIR"
ensure_dir "$ARTIFACTS_DIR"

clone_or_update "$UBOOT_REPO"          "$UBOOT_REF"          "$SOURCES_DIR/u-boot"
clone_or_update "$LINUX_REPO"          "$LINUX_REF"          "$SOURCES_DIR/linux"
clone_or_update "$SUNXI_TOOLS_REPO"    "$SUNXI_TOOLS_REF"    "$SOURCES_DIR/sunxi-tools"
clone_or_update "$LINUX_FIRMWARE_REPO" "$LINUX_FIRMWARE_REF" "$SOURCES_DIR/linux-firmware"

log "sources ready at $SOURCES_DIR"
