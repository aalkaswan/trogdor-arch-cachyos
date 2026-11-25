#!/usr/bin/env bash
# Phase 2: Configure Arch Linux ARM inside native aarch64 chroot with
# CachyOS-inspired tuning, Niri + Hyprland + Noctalia, Chromebook keys, and 2-in-1 touch.
set -euo pipefail

[[ "${EUID}" -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MNT="${MNT:-/mnt/arch}"
USERNAME="${USERNAME:-abufalafel}"
HOSTNAME="${HOSTNAME:-trogdor-arch}"
TIMEZONE="${TIMEZONE:-Europe/Amsterdam}"

mountpoint -q "${MNT}" || { echo "ERROR: ${MNT} is not mounted." >&2; exit 1; }

cleanup() {
    for fs in run sys proc dev/pts dev; do
        mountpoint -q "${MNT}/${fs}" && umount -l "${MNT}/${fs}" || true
    done
}
trap cleanup EXIT

for fs in dev dev/pts proc sys run; do
    mountpoint -q "${MNT}/${fs}" || mount --bind "/${fs}" "${MNT}/${fs}"
done

echo "==> 1. Creating 4 GiB Btrfs-safe nodatacow swapfile"
mkdir -p "${MNT}/swap"
if [[ ! -f "${MNT}/swap/swapfile" ]]; then
    btrfs filesystem mkswapfile --size 4g --uuid clear "${MNT}/swap/swapfile"
fi

echo "==> 2. Installing system configs from repo"
cat <<'EOF' > "${MNT}/etc/fstab"
LABEL=rootemmc  /      btrfs  subvol=@arch,defaults,ssd,compress=zstd:1,noatime  0  0
LABEL=bootemmc  /boot  ext4   defaults,noatime,nodiratime,errors=remount-ro                     0  2
/swap/swapfile  none   swap   defaults                                                          0  0
EOF

cp -a "${REPO_DIR}/configs/etc/." "${MNT}/etc/"

echo "==> 3. Running in-chroot package installation & configuration"
/usr/sbin/chroot "${MNT}" /bin/bash -euo pipefail -c "
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

pacman-key --init
pacman-key --populate archlinuxarm

# Required for kernels without CONFIG_SECURITY_LANDLOCK (e.g. 6.12.42-stb-cbq+)
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
sed -i 's/^#IgnorePkg.*/IgnorePkg = linux-aarch64 linux-aarch64-headers/' /etc/pacman.conf

cat <<'MIRRORS' > /etc/pacman.d/mirrorlist
Server = http://mirror.archlinuxarm.org/\$arch/\$repo
Server = http://fl.us.mirror.archlinuxarm.org/\$arch/\$repo
Server = http://de3.mirror.archlinuxarm.org/\$arch/\$repo
MIRRORS

pacman -Q linux-aarch64 >/dev/null 2>&1 && pacman -Rns --noconfirm linux-aarch64 || true

pacman -Syyu --noconfirm --needed \
  base-devel sudo git vim nano curl wget htop btop fastfetch fish \
  btrfs-progs vboot-utils dosfstools pacman-contrib \
  networkmanager bluez bluez-utils \
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber alsa-utils alsa-ucm-conf rtkit \
  mesa mesa-utils vulkan-freedreno \
  niri hyprland xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland xwayland-satellite \
  noctalia noctalia-greeter greetd greetd-tuigreet mate-polkit adw-gtk-theme \
  kitty foot fuzzel satty wl-clipboard cliphist grim slurp swayidle brightnessctl playerctl xdg-utils \
  keyd iio-sensor-proxy squeekboard python-evdev python-gobject gsettings-desktop-schemas \
  upower power-profiles-daemon earlyoom realtime-privileges \
  ttf-jetbrains-mono-nerd ttf-meslo-nerd noto-fonts noto-fonts-emoji ttf-liberation \
  firefox

# Tune makepkg.conf for Qualcomm Snapdragon 7c (ARMv8.2-A)
sed -i 's/^#MAKEFLAGS=.*/MAKEFLAGS=\"-j4\"/' /etc/makepkg.conf
sed -i 's/ lto)/ !lto)/' /etc/makepkg.conf

echo '${HOSTNAME}' > /etc/hostname
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
ln -sf '/usr/share/zoneinfo/${TIMEZONE}' /etc/localtime

if ! id -u '${USERNAME}' >/dev/null 2>&1; then
    useradd -m -G wheel,video,audio,input,network,realtime -s /usr/bin/fish '${USERNAME}'
fi
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
id -u alarm >/dev/null 2>&1 && userdel -r alarm || true

systemctl enable NetworkManager bluetooth earlyoom greetd rtkit-daemon upower power-profiles-daemon keyd trogdor-tweaks fstrim.timer paccache.timer
"

echo "==> Done! Set passwords in chroot if needed, then run: sudo ./scripts/build-and-flash-kernelb.sh"
