# SATS Mentra Rflex mirror (RK3399): from locked kiosk to standalone Android 13

Notes, tools and scripts from taking one retired **SATS Mentra Rflex** training mirror (Rockchip RK3399, Android 10, kiosk/device-owner lock) to a **standalone Android 13** (official Google GSI on the stock Android 10 vendor), with a working screen, touch, camera, Wi-Fi and app store.

> **This is a write-up of what worked on one unit, not a ready-made flasher.**
> Partition offsets, hashes and several scripts are specific to that unit. Read your own partition table, take a full eMMC backup first, and verify it. Everything here writes to eMMC; mistakes can leave the device needing maskrom recovery. **Use at your own risk, and only on a device you own.**

The full story (mistakes and corrected assumptions included) is in **[docs/report-en.md](docs/report-en.md)** (English) and **[docs/rapport-no.md](docs/rapport-no.md)** (Norwegian; also as a Word file, [docs/SATS-Mentra-Rflex-rapport.docx](docs/SATS-Mentra-Rflex-rapport.docx)). If you only want to get rid of the lock and keep Android 10, read the short **[quick guide](docs/hurtigguide-no.md)** (Norwegian). This README is the summary.

*Not affiliated with, endorsed by, or connected to SATS, Mentra or Rockchip. Names are used only to identify the hardware.*

---

## Outcome

| Goal | Result |
|---|---|
| Remove the kiosk lock ([FS] Launcher, `com.mentra.launcher`, device owner) | Done, and it stays removed |
| Newer Android running standalone | Android 13 (`TQ3A.230805.001.A3` GSI) permanently installed in `super`, boots in ~66 s, no DSU |
| App store | Aurora Store (anonymous login) |
| Mirror behaviour (screen off, tap to use) | 60 s screen timeout + a small touch-to-wake service |
| Camera | Works (USB webcam via the external camera HAL) |
| Hardware video decode | Intentionally disabled for media codecs (see below) |
| Google Play services / YouTube app | Not available on a plain AOSP GSI |
| Boot logo | Replaced (own "Magic Mirror" bitmap) |

## Key findings

1. **Wiping `userdata` does not remove the lock.** The kiosk APK is on the read-only `odm` partition (`/odm/bundled_uninstall_back-app/`) and re-provisions itself as device owner on the next boot (the build has `su`). On stock Android 10 it has to be hidden (overlay/whiteout) as well as cleaned out of `/data/system`. A plain AOSP Android 13 never scans that vendor directory, so the problem disappears there.
2. **Test Android versions without flashing**: Dynamic System Updates (DSU) with official Google GSIs works because the bootloader is unlocked and the vendor is Treble (VNDK 29). One-shot boot; reboot = back to stock.
3. **GSI on an Android 10 vendor + kernel 4.19 needs:** an ext4 feature set the old kernel can mount (no `orphan_file`/`metadata_csum`/`64bit`/`flex_bg`), SELinux `typepermissive` for all types (platform/vendor policy mismatch), `seclabel` on every custom init service (init refuses services without a domain transition, even if permissive), and a couple of HWUI/RenderEngine properties for the old Mali blob.
4. **Video decoding (rkvdec/mpp):** VP9 page-faults the kernel (also on stock Android 10) and Android 13's `ACodec` mis-renders the vendor OMX decoders. Blocking `/dev/mpp_service` makes Chrome fall back to software decoding. **But the webcam's MJPEG decode uses the same VPU node**: blocking it for everyone gives a *green camera picture*. Fix: make the user `cameraserver` the owner (`chown cameraserver root`, `chmod 0600`); media codecs stay locked out.
5. **Permanent install into `super` by hand** (from a running DSU guest): the LP metadata is a small, well-documented structure. We wrote a minimal parser/rewriter, gave `system` two extents (old region + free tail), validated the result with Android's own `lpdump`, wrote data and metadata with hash read-back, tested a `dm-linear` device with the new table, then wiped `userdata` through the stock recovery (`misc` BCB `--wipe_data`).
6. **Touch-to-wake** is not provided by Android 13 here; a ~10-line service reading raw evdev and sending `KEYCODE_WAKEUP` fixes it. Check for "not `Awake`", not just `Asleep` (there is a 2 s `Dozing` state).
7. **Boot logo** lives in a Rockchip resource image (`RSCE`) inside the `boot` partition (not in `dtb`). Replace the bitmap contents with a same-size 8-bit BMP (no repacking, no offset changes). On this portrait panel the bitmap had to be **pre-rotated 90° clockwise**.
8. **Patch a single 4 KiB block of an installed read-only system file** (same length, inode untouched) via `debugfs bmap` + `dd` with before/after hashes. Handy for small init/script changes without re-flashing the system.

## Security notes (read these)

- `ro.adb.secure=0` + root adb = **unauthenticated root over adb**. Turn wireless debugging off on networks you do not control.
- SELinux types are all permissive; the bootloader is unlocked and verified boot is off.
- There are no OTA updates. Updating means a new GSI and a new write.

## Repository layout

```
docs/       Full report (English; Norwegian as Markdown + Word), quick guide (lock removal only), partition map, checksums
tools/      LP metadata parser/builder, resource-image inspector, logo builder, patch helpers
device/     init rc, helper scripts and local tuning that went into the Android 13 image
flash/      Scripts used on the device to write/verify extents, metadata, boot-logo and single-block patches
build/      WSL scripts that rebuilt the GSI system image (ext4 features, SELinux, build.prop)
logo/       The "Magic Mirror" boot logo (own artwork) and the renderer
```

Scripts contain placeholder paths such as `/path/to/work/` at the top: edit them before use.

## Deliberately not included

- **Any disk image or backup** (full eMMC, `super`, `userdata`): they contain device-specific and personal data (including the `security` partition and DRM material).
- The original **Mentra APK, logo and boot animation** (other people's copyright/trademarks) and any vendor blobs.
- **Google GSI images** and **RKDevTool/Rockchip drivers**: download them from their official sources.
- Your own Wi-Fi/Google credentials: the system is set up on the device; nothing secret is baked into the image.

## Suggested order if you try something similar

1. Maskrom access, full eMMC backup, verify, copy away. Nothing is written before this is done.
2. Read your GPT; do **not** reuse offsets from this repo.
3. Try newer Android with DSU first (no flash writes).
4. Only then consider a permanent install, with a rollback slice cut from your verified backup and hash-checked against the live partition.

## License

Scripts and tools: MIT (see `LICENSE`). Text and documentation: CC BY-SA 4.0 (see `LICENSE-docs.md`). Third-party names, firmware and software remain the property of their owners.
