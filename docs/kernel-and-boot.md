# ChromeOS Depthcharge A/B Booting & Kernel Management

## Partition Layout (`/dev/mmcblk1` — 58.2 GiB eMMC)

| Partition | Size | Label | Type | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `mmcblk1p1` | 128 MiB | `KernelA` | ChromeOS kernel | Primary/backup signed FIT kernel |
| `mmcblk1p2` | 128 MiB | `KernelB` | ChromeOS kernel | Active/test signed FIT kernel |
| `mmcblk1p3` | 1.0 GiB | `bootemmc` | `ext4` (`/boot`) | Kernel `Image`, initrd, DTBs, `.kpart` files |
| `mmcblk1p4` | 57.0 GiB | `rootemmc` | `btrfs` (`zstd`) | Holds `@arch` subvolume |

## How Safe One-Shot Booting Works

Depthcharge chooses the highest-priority ChromeOS kernel partition with `successful=1` or `tries > 0`:

- **Safe test boot on `KernelB`**:
  ```bash
  sudo cgpt add -i 2 -S 0 -T 1 -P 15 /dev/mmcblk1
  ```
  Depthcharge decrements `tries` from `1` → `0` when booting `KernelB`. If the kernel panics or hangs, power-cycling automatically falls back to `KernelA` (`priority=10, successful=1`).

- **Lock in `KernelB` permanently** (once verified):
  ```bash
  sudo cgpt add -i 2 -S 1 -T 2 -P 15 /dev/mmcblk1
  ```

- **Mirror verified kernel to `KernelA`** (redundant A/B Arch backup):
  ```bash
  sudo dd if=/boot/vmlinux.kpart-initrd-6.12.42-stb-cbq+-arch of=/dev/mmcblk1p1 bs=4M conv=fsync
  sudo cgpt add -i 1 -S 1 -T 2 -P 10 /dev/mmcblk1
  ```

## Repacking / Upgrading the Kernel Later

Because Arch Linux ARM's generic `linux-aarch64` kernel is ignored (`IgnorePkg = linux-aarch64 linux-aarch64-headers`), future kernel updates come from `velvet-os/imagebuilder` (`stb-cbq` kernel builds) or your own mainline `sc7180` kernel build:

1. Place the new `Image-<kver>`, `dtb-<kver>/`, and `initrd.img-<kver>` in `/boot/` and modules in `/usr/lib/modules/<kver>/`.
2. Build a signed FIT image targeting `subvol=@arch`:
   ```bash
   # Compress kernel
   lzma -9 -z -f -k -c /boot/Image-<kver> > /tmp/Image.lzma
   dd if=/dev/zero of=/tmp/bootloader.bin bs=512 count=1

   # Pack FIT image with SC7180 Trogdor DTBs + initrd
   ls /boot/dtb-<kver>/sc7180-trogdor-*.dtb | xargs printf " -b %s" | \
     xargs mkimage -D "-I dts -O dtb -p 2048" -f auto -A arm64 -O linux -T kernel \
     -C lzma -a 0 -d /tmp/Image.lzma -i /boot/initrd.img-<kver> /tmp/kernel.itb

   # Write kernel command line
   echo -n "root=LABEL=rootemmc rootflags=subvol=@arch console=tty1 rootwait ro fsck.fix=yes fsck.repair=yes net.ifnames=0 ipv6.disable=1 quiet splash deferred_probe_timeout=30 clk_ignore_unused=1" > /tmp/cmdline

   # Sign with ChromeOS developer keys (from vboot-utils)
   vbutil_kernel --pack /boot/vmlinux.kpart-initrd-<kver>-arch \
     --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
     --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
     --version 1 --config /tmp/cmdline --bootloader /tmp/bootloader.bin \
     --vmlinuz /tmp/kernel.itb --arch arm
   ```
3. Always flash the new kernel to the **inactive** slot (`KernelA` or `KernelB`) with `-S 0 -T 1 -P 15` first so a bad kernel always falls back to your known-good slot!
