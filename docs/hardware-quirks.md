# SC7180 / Google Lazor Hardware & Kernel Quirks Solved

Every non-obvious issue encountered while running Arch Linux ARM on `6.12.42-stb-cbq+` (Qualcomm Snapdragon 7c / Acer Chromebook Spin 513) and its verified fix:

## 1. `pacman` Landlock Sandbox Failure
- **Symptom**: `error: restricting filesystem access failed because Landlock is not supported by the kernel!`
- **Cause**: `6.12.42-stb-cbq+` does not enable `CONFIG_SECURITY_LANDLOCK`, and `pacman 7+` enables Landlock sandboxing by default.
- **Fix**: Add `DisableSandbox` under `[options]` in `/etc/pacman.conf`.

## 2. `CONFIG_RT_GROUP_SCHED=y` Blocks `keyd` and `rtkit-daemon`
- **Symptom**:
  - `keyd`: `sched_setscheduler: Operation not permitted` (exit 255)
  - `rtkit-daemon`: `Failed to make ourselves RT: Operation not permitted`
- **Cause**: Under cgroup v2 (`systemd`), kernels compiled with `CONFIG_RT_GROUP_SCHED=y` reject `SCHED_FIFO` realtime priority inside non-root cgroups.
- **Fix**: Move the service PID to the root cgroup before `exec` via systemd drop-ins (`configs/etc/systemd/system/keyd.service.d/override.conf` and `rtkit-daemon.service.d/override.conf`):
  ```ini
  [Service]
  ExecStart=
  ExecStart=/bin/sh -c "echo 0 > /sys/fs/cgroup/cgroup.procs; exec /usr/bin/keyd"
  ```

## 3. `CONFIG_ZRAM` Is Not Enabled — Use `zswap` + Btrfs Swapfile
- **Cause**: `6.12.42-stb-cbq+` has `# CONFIG_ZRAM is not set` but `CONFIG_ZSWAP=y` + `CONFIG_ZSWAP_ZPOOL_DEFAULT_ZSMALLOC=y`.
- **Fix**: Create a Btrfs-safe `nodatacow` swapfile (`btrfs filesystem mkswapfile --size 4g --uuid clear /swap/swapfile`) and enable `zswap` with `zstd` + `zsmalloc` + `max_pool_percent=30` in `trogdor-tweaks.service`, paired with `vm.swappiness=100` and `THP=madvise`.

## 4. Firmware Conflicts Between Velvet OS and `linux-firmware`
- **Cause**: Copying uncompressed Qualcomm/WCN3990 firmware directly into `/usr/lib/firmware/` collides with Arch's `linux-firmware` package on upgrades.
- **Fix**: Place Velvet OS firmware (`qcom`, `ath10k`, `qca`) under `/usr/lib/firmware/updates/<kver>/`. The Linux kernel firmware loader always checks `updates/<kver>/` first and `pacman` never touches it.

## 5. `keyd` Grabbing `cros_ec_buttons` Breaks Tablet-Mode Switch
- **Cause**: Both `cros_ec` (keyboard) and `cros_ec_buttons` (lid + `SW_TABLET_MODE`) report `0000:0000`.
- **Fix**: Find the exact hash with `sudo keyd monitor` and pin `[ids]` strictly to `cros_ec` (e.g., `0000:0000:af5c732c` on `lazor-rev9`).

## 6. `ananicy-cpp` Prebuilt Package Segfaults on Arch Linux ARM
- **Symptom**: `ananicy-cpp` crashes immediately with `SIGSEGV` (`code=dumped`).
- **Fix**: Remove the prebuilt `ananicy-cpp` binary (or compile from source against the current `aarch64` toolchain if desired).

## 7. Unsupported x86 / Missing-Module Sysctl Keys
- **Cause**: `6.12.42-stb-cbq+` does not build `tcp_bbr`, `sch_fq`, or `kernel.nmi_watchdog`.
- **Fix**: Keep only supported VM/I/O tuning keys in `/etc/sysctl.d/99-cachy-tuning.conf`.

## 8. `powerprofilesctl` Missing `gi.repository`
- **Fix**: Install `python-gobject` (not pulled in as a hard dependency of `power-profiles-daemon` on Arch).

## 9. Niri Translucent Terminal Focus-Ring Background
- **Symptom**: Translucent Kitty turns solid when focused in Niri.
- **Fix**: Enable `prefer-no-csd` and add `window-rule { match app-id=r#"^kitty$"#; draw-border-with-background false; }`.

## 10. Hyprland Blur Performance on Adreno 618
- **Fix**: Keep Hyprland blur at `passes = 2, size = 4, new_optimizations = true` rather than 4+ passes designed for desktop GPUs.

## 11. Squeekboard Default Theme & Phone-Width Layout
- **Fix**:
  - Install `adw-gtk-theme` (needed for `adw-gtk3` dark theme).
  - Style `sq_view` / `sq_button` in `gtk-3.0/squeekboard.css` referencing Noctalia's `@define-color` variables.
  - Install wide landscape layouts (`~7.1:1` aspect ratio) in `~/.local/share/squeekboard/keyboards/us_wide.yaml` and `terminal/us_wide.yaml`.
