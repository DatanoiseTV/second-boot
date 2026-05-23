#!/usr/bin/env bash
# Build a Debian trixie armhf rootfs via debootstrap two-stage.
# Needs root on the build host (uses chroot + qemu-arm-static).

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

SUITE="trixie"
ARCH_DEB="armhf"
MIRROR="http://deb.debian.org/debian"

ROOTFS_DIR="$ARTIFACTS_DIR/rootfs/${SUITE}-${ARCH_DEB}"
ROOTFS_TAR="$ARTIFACTS_DIR/rootfs/pocketchip-${SUITE}-${ARCH_DEB}.tar"
PKG_LIST="$HERE/../configs/rootfs/packages.list"

[ "$(id -u)" -eq 0 ] || die "must be run as root (uses chroot + bind mounts)"
[ -f "$PKG_LIST" ]   || die "missing $PKG_LIST"

ensure_dir "$(dirname "$ROOTFS_TAR")"
ensure_dir "$ROOTFS_DIR"

# Strip comments/blank lines from package list.
PKGS=$(grep -vE '^[[:space:]]*(#|$)' "$PKG_LIST" | paste -sd, -)

if [ ! -f "$ROOTFS_DIR/.first-stage-done" ]; then
    log "debootstrap first stage ($SUITE/$ARCH_DEB)"
    debootstrap --arch="$ARCH_DEB" --foreign \
        --include="$PKGS" \
        "$SUITE" "$ROOTFS_DIR" "$MIRROR"
    touch "$ROOTFS_DIR/.first-stage-done"
fi

if [ ! -f "$ROOTFS_DIR/.second-stage-done" ]; then
    log "copying qemu-arm-static into rootfs"
    cp /usr/bin/qemu-arm-static "$ROOTFS_DIR/usr/bin/"

    log "debootstrap second stage (chrooted)"
    chroot "$ROOTFS_DIR" /debootstrap/debootstrap --second-stage
    touch "$ROOTFS_DIR/.second-stage-done"
fi

log "applying system config (hostname, fstab, default user, services)"

# hostname
echo "pocketchip" > "$ROOTFS_DIR/etc/hostname"
sed -i '/127.0.1.1/d' "$ROOTFS_DIR/etc/hosts"
echo "127.0.1.1 pocketchip" >> "$ROOTFS_DIR/etc/hosts"

# fstab — root and boot partitions live on the SD card.
cat > "$ROOTFS_DIR/etc/fstab" <<'EOF'
LABEL=POCKETROOT  /        ext4  defaults,noatime,errors=remount-ro  0 1
LABEL=POCKETBOOT  /boot    vfat  defaults,noatime                    0 2
tmpfs             /tmp     tmpfs defaults,nosuid,nodev                0 0
EOF

# default user 'chip', passwordless sudo (handheld, no shoulder surfing risk)
chroot "$ROOTFS_DIR" /bin/bash -e <<'EOF'
if ! id chip >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,audio,video,input,dialout,plugdev,netdev chip
    echo "chip:chip" | chpasswd
fi
echo "chip ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/010_chip-nopasswd
chmod 0440 /etc/sudoers.d/010_chip-nopasswd

# root login disabled, ssh password auth ok (LAN handheld)
passwd -l root || true

systemctl enable ssh.service NetworkManager.service bluetooth.service
EOF

# remove qemu shim before tarring (will be copied in again if re-run)
rm -f "$ROOTFS_DIR/usr/bin/qemu-arm-static"

log "creating rootfs tarball $ROOTFS_TAR"
( cd "$ROOTFS_DIR" && tar --numeric-owner -cf "$ROOTFS_TAR" . )
log "rootfs tarball: $(du -sh "$ROOTFS_TAR" | cut -f1)"
