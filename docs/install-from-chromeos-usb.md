# Installing from a Clean ChromeOS Device via USB

This guide starts from a **stock ChromeOS** Qualcomm Snapdragon 7c (`chromebook_trogdor` / Acer Chromebook Spin 513 `Google Lazor`) and walks through unlocking Developer Mode, booting a live Linux USB, and installing **Arch Linux ARM (CachyOS-tuned)** onto internal eMMC (`/dev/mmcblk1`).

> **Warning**: Enabling Developer Mode performs a **Powerwash** (wipes all local ChromeOS user data). Back up anything important first. You can always restore stock ChromeOS later using a standard [ChromeOS Recovery USB](https://support.google.com/chromebook/answer/1080595).

---

## Step 1: Enable ChromeOS Developer Mode

1. Power off the Chromebook completely.
2. Hold **`Esc` + `Refresh` (F3)** and press **`Power`** to enter ChromeOS Recovery Mode.
3. On the *"ChromeOS is missing or damaged"* screen, press **`Ctrl + D`**.
4. Confirm turning OS verification OFF (press `Enter` or follow the on-screen prompt).
5. The Chromebook will reboot and transition into Developer Mode (takes ~5 minutes).
   - From now on, every boot shows the Developer Mode screen: press **`Ctrl + D`** to boot internal eMMC, or **`Ctrl + U`** to boot from USB.

---

## Step 2: Enable USB Booting (`crossystem`)

1. Once ChromeOS boots to the initial setup screen (you do **not** need to sign in to a Google account), switch to VT2 by pressing **`Ctrl + Alt + Forward (F2)`**.
2. Log in as **`chronos`** (no password required on a fresh Dev Mode install).
3. Enable external USB booting and unsigned/dev-key-signed Depthcharge kernels:
   ```bash
   sudo crossystem dev_boot_usb=1 dev_boot_signed_only=0
   ```
4. Verify both flags return `1` and `0`:
   ```bash
   crossystem dev_boot_usb dev_boot_signed_only
   ```
5. Power off (`sudo poweroff`).

---

## Step 3: Flash a Velvet OS (`chromebook_trogdor`) Bootstrap USB

Because Snapdragon 7c Chromebooks require a specially patched `stb-cbq` kernel, `sc7180-trogdor` Device Trees, Qualcomm firmware, `cgpt`, and `vboot-kernel-utils`, the easiest and safest live bootstrapper is a **Velvet OS `chromebook_trogdor`** USB image.

On another computer (Linux/macOS/Windows):

1. Download the latest `chromebook_trogdor-aarch64-trixie` `.img.gz` / `.img.xz` release from:
   - `https://github.com/velvet-os/imagebuilder/releases`
2. Flash it onto a USB-C drive (≥ 8 GB) — **replace `/dev/sdX` with your actual USB device**:
   ```bash
   # If .img.gz:
   gzip -dc chromebook_trogdor-aarch64-*.img.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
   # Or if .img.xz:
   xz -dc chromebook_trogdor-aarch64-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
   ```
   *(On Windows/macOS you can flash the image with Rufus, BalenaEtcher, or Raspberry Pi Imager.)*

---

## Step 4: Boot the Chromebook from USB

1. Plug the USB drive into either USB-C port on the Chromebook and power it on.
2. On the Developer Mode screen, press **`Ctrl + U`**.
3. Wait for Velvet OS Debian to boot, then log in with the default Velvet OS credentials (`linux` / `changeme`, or `root` / `changeme`).
4. Connect to Wi-Fi (via NetworkManager / `nmtui`) and clone this repository:
   ```bash
   sudo apt update && sudo apt install -y git libarchive-tools curl
   git clone https://github.com/aalkaswan/trogdor-arch-cachyos.git ~/trogdor-arch-cachyos
   cd ~/trogdor-arch-cachyos
   ```

---

## Step 5: Install Arch Linux ARM onto Internal eMMC (`/dev/mmcblk1`)

Choose **Option A** (easiest, zero manual partitioning) or **Option B** (direct clean Arch install onto eMMC without writing Debian to eMMC first).

### Option A (Easiest): Bootstrap eMMC Layout with Velvet OS, Then Install Arch Side-by-Side

1. From the Velvet OS USB, run Velvet OS's built-in eMMC installer (formats `/dev/mmcblk1` with ChromeOS `KernelA`, `KernelB`, `bootemmc`, and Btrfs `rootemmc`):
   ```bash
   sudo /scripts/install-to-emmc.sh
   ```
2. Power off, unplug the USB drive, and boot from internal eMMC (`Ctrl + D`).
3. Follow **Steps 1–4** in [README.md](../README.md) (`install-chroot-base.sh` → `setup-arch-inside-chroot.sh` → `build-and-flash-kernelb.sh`).
4. Once verified inside Arch, mirror `@arch` to `KernelA` and delete the temporary Debian directories from `subvolid=5` to reclaim all ~17 GiB.

---

### Option B (Direct): Partition Internal eMMC & Install Arch Straight from USB

From the booted Velvet OS USB (`Ctrl + U`), wipe and partition `/dev/mmcblk1` directly for Arch Linux ARM:

#### 1. Create the ChromeOS GPT Partition Table on `/dev/mmcblk1`

> **Warning**: This erases ChromeOS from internal eMMC (`/dev/mmcblk1`). Double-check with `lsblk` that internal eMMC is `/dev/mmcblk1` (and NOT your USB drive `/dev/sda`).

```bash
DISK=/dev/mmcblk1

sudo wipefs -a "$DISK"
sudo cgpt create "$DISK"

# Partition 1: KernelA (128 MiB = 262144 sectors @ 512B)
sudo cgpt add -i 1 -t kernel -b 8192 -s 262144 -l KernelA -P 10 -T 2 -S 1 "$DISK"

# Partition 2: KernelB (128 MiB)
sudo cgpt add -i 2 -t kernel -b 270336 -s 262144 -l KernelB -P 15 -T 2 -S 1 "$DISK"

# Partition 3: /boot (1 GiB = 2097152 sectors)
sudo cgpt add -i 3 -t data -b 532480 -s 2097152 -l bootemmc "$DISK"

# Partition 4: / (remaining eMMC space)
TOTAL_SECTORS=$(sudo blockdev --getsz "$DISK")
ROOT_START=2629632
ROOT_SIZE=$((TOTAL_SECTORS - ROOT_START - 64))
sudo cgpt add -i 4 -t data -b "$ROOT_START" -s "$ROOT_SIZE" -l rootemmc "$DISK"

sudo partprobe "$DISK"
sudo cgpt show "$DISK"
```

#### 2. Format `bootemmc` (`ext4`) & `rootemmc` (`btrfs`) and Copy the Kernel `/boot` Files

```bash
sudo mkfs.ext4 -F -L bootemmc /dev/mmcblk1p3
sudo mkfs.btrfs -f -L rootemmc /dev/mmcblk1p4

# Copy the working stb-cbq kernel, initrd, DTBs, and cmdline from the live USB's /boot
sudo mkdir -p /mnt/emmc-boot
sudo mount /dev/mmcblk1p3 /mnt/emmc-boot
sudo cp -a /boot/. /mnt/emmc-boot/
sudo umount /mnt/emmc-boot
```

#### 3. Extract & Configure Arch Linux ARM in `@arch` on `/dev/mmcblk1p4`

```bash
cd ~/trogdor-arch-cachyos
sudo ROOT_PART=/dev/mmcblk1p4 ./scripts/install-chroot-base.sh
sudo ./scripts/setup-arch-inside-chroot.sh
```

Set passwords for `root` and your user inside the chroot before flashing:

```bash
sudo chroot /mnt/arch passwd
sudo chroot /mnt/arch passwd abufalafel
```

#### 4. Pack & Flash the Signed Depthcharge Kernel for `root=LABEL=rootemmc` (`@arch`)

Because you are currently booted from USB (`root=LABEL=rootusb`), explicitly override `CUSTOM_ROOT_PARAMETER` so the packed kernel boots internal eMMC (`root=LABEL=rootemmc`):

```bash
KVER="$(uname -r)"

# Unmount @arch cleanly
sudo sync
sudo umount -R /mnt/arch || sudo umount -l /mnt/arch

# Build signed Depthcharge kernel targeting internal eMMC @arch
sudo CUSTOM_ROOT_PARAMETER="root=LABEL=rootemmc" \
     CUSTOM_PARAMETER="rootflags=subvol=@arch" \
     CUSTOM_SUFFIX="-arch" \
     NO_FLASH=1 \
     vtbuild "$KVER"

KIMG="/boot/vmlinux.kpart-initrd-${KVER}-arch"

# Save the packed image onto eMMC /boot as well
sudo mount /dev/mmcblk1p3 /mnt/emmc-boot
sudo cp -a "$KIMG" /mnt/emmc-boot/
sudo umount /mnt/emmc-boot

# Flash to BOTH KernelA and KernelB on internal eMMC
sudo dd if="$KIMG" of=/dev/mmcblk1p1 bs=4M conv=fsync
sudo dd if="$KIMG" of=/dev/mmcblk1p2 bs=4M conv=fsync
sudo cgpt add -i 1 -S 1 -T 2 -P 10 /dev/mmcblk1
sudo cgpt add -i 2 -S 1 -T 2 -P 15 /dev/mmcblk1
```

#### 5. Reboot into Arch Linux ARM

1. Power off (`sudo poweroff`), unplug the USB drive, and power on.
2. Press **`Ctrl + D`** at the Developer Mode screen — it will boot straight into **Arch Linux ARM** on `@arch`!
3. Continue with **Step 4** of [README.md](../README.md) (Noctalia Greeter sync, `yay`, `google-chrome`, etc.).

---

## Recovery & Troubleshooting

- **Arch fails to boot after a change**: Plug your Velvet OS USB back in, boot with **`Ctrl + U`**, mount `/dev/mmcblk1p4` with `-o subvol=@arch`, and inspect logs (`journalctl -D /mnt/arch/var/log/journal`) or chroot in to repair.
- **Restore stock ChromeOS**: Create a ChromeOS Recovery USB using the Chromebook Recovery Utility, boot into Recovery Mode (`Esc + Refresh + Power`), and insert the recovery USB.
