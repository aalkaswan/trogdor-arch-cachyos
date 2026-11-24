# Arch Linux ARM (CachyOS-Tuned) on Qualcomm Snapdragon 7c Chromebooks (`chromebook_trogdor`)

A complete, field-tested guide, configuration pack, and helper scripts for installing **Arch Linux ARM (`aarch64`)** with **CachyOS-style performance tuning**, **Niri / Hyprland + Noctalia Shell & Greeter**, **ChromeOS top-row keys**, and **2-in-1 touchscreen/auto-rotate/OSK support** on Qualcomm Snapdragon 7c (`SC7180` / `trogdor`) Chromebooks — specifically verified on **Acer Chromebook Spin 513 (`Google Lazor rev9`)**.

---

## Why Not Official CachyOS Directly?

Two hard technical blockers prevent installing official CachyOS ISOs on this device:

1. **Architecture (`aarch64` vs `x86_64`)**: Snapdragon 7c (`SC7180`) is a 64-bit ARM (`aarch64`) SoC (2× Kryo-4XX-Gold @ 2.11 GHz + 6× Kryo-4XX-Silver @ 1.80 GHz, `ARMv8.2-A`). Official CachyOS only builds `x86_64` ISOs and binary repos.
2. **Bootloader (`ChromeOS Depthcharge` vs UEFI)**: ARM Chromebooks boot signed ChromeOS FIT kernel partitions (`KernelA` / `KernelB` via `cgpt` + `vbutil_kernel`), not UEFI/GRUB/systemd-boot.

**The solution**: Run **Arch Linux ARM (`aarch64`)** on top of the proven **`velvet-os` (`stb-cbq`) mainline Qualcomm kernel & firmware**, then layer CachyOS's userspace/kernel tuning, `ARMv8.2-A` compiler flags, `zswap` + `THP=madvise` + MGLRU memory tuning, and a modern Wayland stack (**Niri / Hyprland + Noctalia**).

---

## Verified Hardware Profile (`Google Lazor rev9` / Acer Spin 513)

| Component | Status | Notes |
| :--- | :--- | :--- |
| **SoC / CPU** | Working | Qualcomm SC7180 (`ARMv8.2-A`, 8 cores, `schedutil` governor) |
| **GPU / Display** | Working | Adreno 618 (`FD618`), Mesa OpenGL 4.6 / Vulkan Freedreno, 1920×1080 eDP |
| **Wi-Fi & Bluetooth** | Working | Qualcomm WCN3990 (`ath10k_snoc` / `btqca`), firmware in `/usr/lib/firmware/updates/` |
| **Audio** | Working | SC7180 LPASS + RT5682 + MAX98357A (`alsa-ucm-conf` + PipeWire + WirePlumber + RTKit fix) |
| **Webcam & Video** | Working | Chicony HD USB cam + Qualcomm Venus hardware encoder/decoder (`v4l2`) |
| **Keyboard & Backlight** | Working | `cros_ec` top-row action keys + Search layer + `chromeos::kbd_backlight` via `keyd` |
| **Touchscreen & Stylus** | Working | Elan `04F3:2C07` touch + USI stylus mapped to `eDP-1` |
| **360° Hinge & Auto-Rotate** | Working | `cros_ec_buttons` (`SW_TABLET_MODE`) + `cros-ec-accel` (`iio-sensor-proxy`) + wide dark `squeekboard` |
| **Suspend** | Working | `deep` sleep supported (`/sys/power/mem_sleep`) |

---

## Repository Layout

- `README.md` — End-to-end installation & post-install guide (USB-free A/B Btrfs path)
- `docs/install-from-chromeos-usb.md` — **Start here on a clean stock ChromeOS device** (Developer Mode → `crossystem` → Velvet OS USB → direct eMMC Arch install)
- `docs/hardware-quirks.md` — Every SC7180 / `stb-cbq` kernel quirk encountered & fixed
- `docs/kernel-and-boot.md` — Depthcharge A/B kernel slots, safe one-shot testing, rollback, and updates
- `scripts/install-chroot-base.sh` — Creates Btrfs `@arch` subvolume, extracts Arch Linux ARM, transplants Qualcomm modules/firmware
- `scripts/setup-arch-inside-chroot.sh` — Runs inside native `aarch64` chroot to configure `pacman`, packages, users, swapfile, and CachyOS tuning
- `scripts/build-and-flash-kernelb.sh` — Builds signed Depthcharge kernel targeting `rootflags=subvol=@arch` and arms a one-shot test boot on `KernelB`
- `scripts/chromebook-touch-daemon`, `toggle-osk`, `toggle-autorotate` — 2-in-1 tablet mode, auto-rotate, and on-screen keyboard helpers
- `configs/` — Tested system (`/etc`) and user (`niri`, `kitty`, `squeekboard`, `chrome-flags.conf`) configs

---

## Choose Your Starting Point

- **Starting from a clean stock ChromeOS Chromebook (via USB)**: Follow **[docs/install-from-chromeos-usb.md](docs/install-from-chromeos-usb.md)** first (Developer Mode, `crossystem dev_boot_usb=1`, Velvet OS bootstrap USB, and either direct eMMC partitioning or two-step install).
- **Already running Velvet OS (`chromebook_trogdor` Debian) on internal eMMC (USB-free)**: Follow the A/B Btrfs steps directly below.

---

## Installation Guide (USB-Free A/B Btrfs Method)

> **Prerequisites**: Starting from a working **Velvet OS** (`chromebook_trogdor` Debian `aarch64`) install on internal eMMC (`/dev/mmcblk1`) with Btrfs `/` (`mmcblk1p4`), `/boot` (`mmcblk1p3`), and ChromeOS Depthcharge slots `KernelA` (`mmcblk1p1`) & `KernelB` (`mmcblk1p2`).
>
> *No USB drive required!* Your existing OS stays untouched on `KernelA` while Arch Linux ARM is installed into a sibling `@arch` Btrfs subvolume and test-booted once on `KernelB` with **automatic fallback to `KernelA`** if anything fails.

### Step 1: Create `@arch`, Extract Arch Linux ARM & Transplant Hardware Assets

```bash
sudo apt update && sudo apt install -y libarchive-tools curl
sudo ./scripts/install-chroot-base.sh
```

What this does:
- Creates Btrfs subvolume `@arch` on `/dev/mmcblk1p4` (zero repartitioning) and mounts it at `/mnt/arch` with `compress-force=zstd,ssd,noatime`.
- Downloads `ArchLinuxARM-aarch64-latest.tar.gz` to disk (avoiding 4 GB RAM `tmpfs` exhaustion) and extracts it with `bsdtar -xpf`.
- Copies `/lib/modules/<kver>` and places Qualcomm/WCN3990 firmware (`qcom`, `ath10k`, `qca`) into `/usr/lib/firmware/updates/<kver>/` (searched first by the kernel, zero `pacman` conflicts).
- Preserves NetworkManager Wi-Fi connections and `/etc/resolv.conf`.

### Step 2: Configure Arch Linux ARM in Native `aarch64` Chroot

```bash
sudo ./scripts/setup-arch-inside-chroot.sh
```

What this does inside `/mnt/arch`:
- Initializes `pacman-key` (`archlinuxarm`) and sets **`DisableSandbox`** in `/etc/pacman.conf` (required because `6.12.42-stb-cbq+` lacks Landlock).
- Removes generic `linux-aarch64` and adds `IgnorePkg = linux-aarch64 linux-aarch64-headers`.
- Installs **Niri**, **Hyprland**, **Noctalia Shell**, **Noctalia Greeter**, **Kitty**, **Fish**, **Mesa + Vulkan Freedreno**, **PipeWire + WirePlumber + RTKit**, **NetworkManager**, **BlueZ**, **vboot-utils**, **keyd**, **iio-sensor-proxy**, **squeekboard**, **earlyoom**, **upower**, **power-profiles-daemon**, and Nerd Fonts.
- Creates a **4 GiB Btrfs-safe `nodatacow` swapfile** (`btrfs filesystem mkswapfile`) + writes `/etc/fstab` targeting `subvol=@arch`.
- Applies CachyOS-inspired tuning (`ARMv8.2-A` `makepkg.conf`, `zswap zstd 30%`, `THP=madvise`, `DMA-FQ` eMMC IOMMU, `none` I/O scheduler, `schedutil` governor, `99-cachy-tuning.conf`, `keyd` + `rtkit` cgroup overrides).

### Step 3: Build & Flash One-Shot Depthcharge `KernelB`

```bash
sudo ./scripts/build-and-flash-kernelb.sh
```

What this does:
- Packs a separate signed Depthcharge FIT kernel image via `vtbuild` with `CUSTOM_PARAMETER="rootflags=subvol=@arch" CUSTOM_SUFFIX="-arch" NO_FLASH=1` (leaves `KernelA` untouched).
- Flashes **only** to `KernelB` (`/dev/mmcblk1p2`) and arms a one-shot test boot:
  ```bash
  sudo cgpt add -i 2 -S 0 -T 1 -P 15 /dev/mmcblk1
  ```

### Step 4: Reboot, Verify & Lock In

1. Reboot (`sudo reboot`). Depthcharge boots `KernelB` into Arch Linux ARM.
   - *Safety net*: If boot fails, power off and power back on — Depthcharge automatically falls back to `KernelA` (your untouched Velvet OS Debian).
2. Inside Arch, verify everything (`systemctl --failed`, Wi-Fi, audio, GPU `glxinfo -B`, `swapon --show`).
3. **Make Arch permanent**:
   ```bash
   sudo cgpt add -i 2 -S 1 -T 2 -P 15 /dev/mmcblk1
   ```
4. **Set up Noctalia Greeter** (synced with your Noctalia wallpaper & palette):
   ```bash
   sudo /usr/share/noctalia-greeter/setup_greeter_system.sh
   sudo noctalia-greeter passwordless-sync enable "$USER"
   noctalia msg config-set shell.greeter_sync.auto_sync true
   noctalia msg greeter-sync
   ```
5. **Install `yay` & optional `google-chrome` (`aarch64` AUR)**:
   ```bash
   git clone --depth 1 https://aur.archlinux.org/yay-bin.git /tmp/yay-bin && (cd /tmp/yay-bin && makepkg -si --noconfirm)
   yay -S google-chrome
   ```
6. **Optional: Reclaim old Debian space** (only once 100% happy with Arch):
   - First mirror your working `@arch` kernel onto `KernelA` too so both Depthcharge slots boot Arch:
     ```bash
     sudo dd if=/boot/vmlinux.kpart-initrd-$(uname -r)-arch of=/dev/mmcblk1p1 bs=4M conv=fsync
     sudo cgpt add -i 1 -S 1 -T 2 -P 10 /dev/mmcblk1
     ```
   - Mount `subvolid=5` of `/dev/mmcblk1p4` and delete the old Debian top-level directories while leaving `@arch` untouched (reclaims ~17–18 GiB).

---

## Keybinds & Chromebook Ergonomics

Because Chromebook keyboards only have `Ctrl` and `Alt` next to Spacebar (with Search/Super in the Caps Lock slot):

- **Window Manager Mod Key**: `Alt` in both Niri (`configs/niri/config.kdl`) and Hyprland.
- **Top Row (`configs/etc/keyd/chromebook.conf`)**:
  - `F1`–`F5`: Back, Forward, Refresh, Fullscreen (`F11`), Overview (`XF86LaunchA`)
  - `F6`–`F7`: Screen Brightness Down / Up (Noctalia OSD)
  - `F8`–`F10`: Mute, Volume Down, Volume Up (Noctalia OSD)
  - `Search + F1..F10` → Real `F1`–`F10` | `Search + Backspace` → `Delete` | `Search + Arrows` → `Home/End/PgUp/PgDn`
  - `Alt + Search` → `Caps Lock` | `Alt + F6/F7` → Keyboard Backlight | `Ctrl + F5` → Screenshot
- **2-in-1 Touch Controls**:
  - Fold 360° → auto-enables accelerometer rotation + wide dark Noctalia Squeekboard (`configs/squeekboard/` + `configs/gtk-3.0/squeekboard.css`)
  - `Alt+Shift+B` → Manual touch keyboard toggle | `Alt+Shift+O` → Cycle auto-rotate mode
