#!/usr/bin/env bash
# Phase 3: Build signed Depthcharge kernel targeting @arch and flash to KernelB
# with one-shot test boot (automatic fallback to KernelA if boot fails).
set -euo pipefail

[[ "${EUID}" -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

DISK="${DISK:-/dev/mmcblk1}"
KERNELB_PART="${KERNELB_PART:-/dev/mmcblk1p2}"
KVER="${KVER:-$(uname -r)}"
SUBVOL="${SUBVOL:-@arch}"
MNT="${MNT:-/mnt/arch}"

echo "==> 1. Stopping any stray chroot processes & unmounting ${MNT}"
for p in /proc/[0-9]*; do
    if [[ "$(readlink "${p}/root" 2>/dev/null || true)" == "${MNT}" ]]; then
        kill "${p#/proc/}" 2>/dev/null || true
    fi
done
sleep 1
sync
if mountpoint -q "${MNT}"; then
    umount -R "${MNT}" || umount -l "${MNT}"
fi

echo "==> 2. Building signed Depthcharge kernel targeting rootflags=subvol=${SUBVOL}"
CUSTOM_PARAMETER="rootflags=subvol=${SUBVOL}" \
CUSTOM_SUFFIX="-arch" \
NO_FLASH=1 \
vtbuild "${KVER}"

KIMG="/boot/vmlinux.kpart-initrd-${KVER}-arch"
IMG_SIZE=$(stat -c %s "${KIMG}")
PART_SIZE=$(lsblk -b -n -o SIZE -p "${KERNELB_PART}")
echo "Image size: ${IMG_SIZE} bytes | KernelB size: ${PART_SIZE} bytes"
(( IMG_SIZE <= PART_SIZE )) || { echo "ERROR: Image larger than ${KERNELB_PART}!" >&2; exit 1; }

echo "==> 3. Flashing ${KIMG} to ${KERNELB_PART} (KernelA untouched)"
dd if="${KIMG}" of="${KERNELB_PART}" bs=4M conv=fsync

echo "==> 4. Arming one-shot test boot on KernelB (auto-fallback to KernelA)"
cgpt add -i 2 -S 0 -T 1 -P 15 "${DISK}"
cgpt show "${DISK}"

echo ""
echo "Ready! Reboot to test Arch Linux ARM."
echo "Once verified inside Arch, make permanent with:"
echo "  sudo cgpt add -i 2 -S 1 -T 2 -P 15 ${DISK}"
