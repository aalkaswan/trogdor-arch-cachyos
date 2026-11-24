#!/usr/bin/env bash
# Phase 1: Create Btrfs @arch subvolume, extract Arch Linux ARM (aarch64),
# and transplant Qualcomm SC7180 kernel modules, firmware, and Wi-Fi profiles.
# Run as root from Velvet OS (Debian aarch64) on the Chromebook.
set -euo pipefail

[[ "${EUID}" -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

ROOT_PART="${ROOT_PART:-/dev/mmcblk1p4}"
SUBVOL="${SUBVOL:-@arch}"
MNT="${MNT:-/mnt/arch}"
KVER="${KVER:-$(uname -r)}"
TARBALL="${TARBALL:-/root/ArchLinuxARM-aarch64-latest.tar.gz}"

echo "==> 1. Creating Btrfs subvolume ${SUBVOL} on ${ROOT_PART}"
mkdir -p /mnt/btrfs-top "${MNT}"
mount -o subvolid=5 "${ROOT_PART}" /mnt/btrfs-top
if [[ ! -d "/mnt/btrfs-top/${SUBVOL}" ]]; then
    btrfs subvolume create "/mnt/btrfs-top/${SUBVOL}"
fi
umount /mnt/btrfs-top

mountpoint -q "${MNT}" || mount -o "subvol=${SUBVOL},compress-force=zstd,ssd,noatime" "${ROOT_PART}" "${MNT}"

echo "==> 2. Downloading & extracting ArchLinuxARM-aarch64-latest.tar.gz"
curl -fL http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz -o "${TARBALL}"
bsdtar -xpf "${TARBALL}" -C "${MNT}"
rm -f "${TARBALL}"

echo "==> 3. Transplanting kernel modules (${KVER}) & Qualcomm firmware into updates/"
mkdir -p "${MNT}/usr/lib/modules" \
         "${MNT}/usr/lib/firmware/updates/${KVER}" \
         "${MNT}/etc/NetworkManager/system-connections" \
         "${MNT}/root/velvet-backup"

cp -a "/lib/modules/${KVER}" "${MNT}/usr/lib/modules/"
for fwdir in qcom ath10k qca; do
    [[ -d "/lib/firmware/${fwdir}" ]] && cp -a "/lib/firmware/${fwdir}" "${MNT}/usr/lib/firmware/updates/${KVER}/"
done

[[ -d /usr/share/alsa/ucm2/Qualcomm/sc7180 ]] && cp -a /usr/share/alsa/ucm2/Qualcomm/sc7180 "${MNT}/root/velvet-backup/ucm2-sc7180"
[[ -d /etc/X11/xorg.conf.d ]] && cp -a /etc/X11/xorg.conf.d "${MNT}/root/velvet-backup/xorg.conf.d"
cp -a /etc/NetworkManager/system-connections/. "${MNT}/etc/NetworkManager/system-connections/" 2>/dev/null || true

rm -f "${MNT}/etc/resolv.conf"
cp /etc/resolv.conf "${MNT}/etc/resolv.conf"

echo "==> Done! Next run: sudo ./scripts/setup-arch-inside-chroot.sh"
