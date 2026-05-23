# Device entry for the Next Thing Co. PocketCHIP, appended to
# target/linux/sunxi/image/cortexa8.mk by scripts/10-build-openwrt.sh.
#
# Reuses our PocketCHIP DTS (sun5i-r8-chip-pocketchip-ng) which is
# dropped into the kernel tree under target/linux/sunxi/files-6.6/
# before kernel configuration.

define Device/nextthing_chip-pocketchip-ng
  DEVICE_VENDOR := Next Thing Co.
  DEVICE_MODEL := PocketCHIP (mainline NG)
  DEVICE_PACKAGES := \
	kmod-leds-gpio kmod-rtc-sunxi \
	kmod-rtl8723bs wpad-basic-mbedtls iw \
	kmod-bluetooth \
	kmod-backlight-pwm \
	wireless-regdb usbutils \
	dropbear nano htop \
	luci luci-mod-network luci-mod-status luci-mod-system \
	luci-app-firewall luci-theme-bootstrap
  SOC := sun5i
  SUNXI_DTS := $$(SUNXI_DTS_DIR)sun5i-r8-chip-pocketchip-ng
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += nextthing_chip-pocketchip-ng
