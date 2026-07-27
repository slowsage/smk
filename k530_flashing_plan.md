# Redragon K530 Draconic PRO - Flashing Plan

## Hardware Identification

- Board: Redragon K530 Draconic PRO
- MCU: SinoWealth SH68F90A (label BYK916)
- USB, normal/wired mode: VID `0x258A` / PID `0x0049`
- USB, ISP bootloader mode: VID `0x0603` / PID `0x1020` (and `0x1021` for the v2 protocol variant)
- Device key used by tooling below: `redragon-k530-draconic-pro`

This is **not** the Sonix-based hardware revision that SonixQMK/community QMK
forks target - those (VID `0x0C45`) do not apply to this unit. Confirmed via
`lsusb` on 2026-07-27.

## Repos & Tools

- **sinowisp** (read/write the stock or custom firmware over the ISP bootloader):
  https://github.com/carlossless/sinowealth-kb-tool (crate: `sinowisp`)
- **smk** (QMK-like custom firmware for SinoWealth 8051 chips - K530 Pro support
  not yet ported, see Phase D):
  https://github.com/carlossless/smk
  Local clone: `~/hack/smk`
  Porting plan for this board: `~/hack/smk/docs/keyboards/k530.md`
- Setup script for Phase A + first backup: `~/hack/sysop/setup_sinowisp_k530.sh`

## Phase A - Environment Setup

1. Install sinowisp:
   ```
   cargo install sinowisp
   ```
2. Linux udev rule (this system uses systemd `uaccess` ACL tagging, not a
   `plugdev` group) - `/etc/udev/rules.d/99-sinowisp-k530.rules`:
   ```
   SUBSYSTEMS=="usb", ATTRS{idVendor}=="258a", ATTRS{idProduct}=="0049", TAG+="uaccess"
   SUBSYSTEMS=="usb", ATTRS{idVendor}=="0603", ATTRS{idProduct}=="1020", TAG+="uaccess"
   SUBSYSTEMS=="usb", ATTRS{idVendor}=="0603", ATTRS{idProduct}=="1021", TAG+="uaccess"
   ```
   ```
   sudo udevadm control --reload-rules
   sudo udevadm trigger
   ```
   Unplug/replug the keyboard after applying.
3. Connect the keyboard via USB-C (data cable), power switch set so it's in
   wired mode (see earlier notes: left-side ON/OFF switch to OFF enables wired
   mode regardless of the 2.4/B1/B2 slot switch).

## Phase B - Stock Firmware Backup (always first, before any write)

```
mkdir -p ~/k530-pro-firmware-backups
sinowisp read -d redragon-k530-draconic-pro \
  ~/k530-pro-firmware-backups/k530_pro_stock_$(date +%Y%m%d_%H%M%S).bin
```

- Expected size: 61440 bytes (65536 total flash - 4096 bootloader, per the
  SH68F90A platform spec)
- Keep at least one copy off this machine (external drive/cloud) - it is the
  only path back to factory state once anything is written

## Phase C - Recovery / Restore

If a custom flash misbehaves but the keyboard still enumerates (either as
`258a:0049` or in ISP mode as `0603:1020`/`0603:1021`):

```
sinowisp write -d redragon-k530-draconic-pro <path-to-backup>.bin
```

A normal `sinowisp write` only touches the firmware region, not the bootloader,
so the ISP entry path itself should survive a bad application firmware write.

## Phase D - Custom Firmware via smk (blocked on porting work)

Not usable yet - `redragon-k530-draconic-pro` is not in smk's supported device
list. See `~/hack/smk/docs/keyboards/k530.md` for the porting plan (matrix/RGB
pin reverse-engineering, code options, etc.). Once a board definition exists:

1. Prerequisites: `sdcc` >= 4.3.0, `meson` >= 0.53, `ninja` >= 1.11.1, `sinowisp`
   (Phase A) - or run `nix develop` inside `~/hack/smk` to get all of this from
   the repo's flake.
2. Build:
   ```
   cd ~/hack/smk
   meson setup build
   meson compile -C build redragon-k530-draconic-pro_default_smk.hex
   ```
3. Flash (wraps sinowisp internally):
   ```
   meson compile -C build redragon-k530-draconic-pro_default_flash
   ```
   Equivalent manual step: `sinowisp write -d redragon-k530-draconic-pro build/.../firmware.hex`
4. Test wired keypresses only at first. Do not expect 2.4G/BT to work - smk's
   most complete board (`nuphy-air60`) only has partial 2.4G and no BT; treat
   wireless as out of scope for an initial K530 Pro port.

## Safety Checklist (every session)

- [ ] A verified-readable stock backup exists before writing anything
- [ ] Only one `sinowisp`/`meson` flash operation running at a time
- [ ] USB-C cable stays connected for the entire duration of any read/write
- [ ] On a failed/interrupted write, retry `sinowisp write` with a known-good
      image before disconnecting anything

## Rollback

- Bad application firmware, device still enumerates: Phase C restore
- Device not enumerating at all under either normal or ISP VID/PID: no
  documented recovery for this specific board yet (would require the physical
  ISP-entry recon from `k530.md` Phase 1 - e.g. a pin-short procedure - which
  hasn't been derived for this board)
