# SATS Mentra Rflex mirror (RK3399): from locked kiosk to standalone Android 13

Notes, tools and scripts from taking one retired **SATS Mentra Rflex** training mirror (Rockchip RK3399, Android 10, kiosk/device-owner lock) to a **standalone Android 13** (official Google GSI on the stock Android 10 vendor), with a working screen, touch, camera, Wi-Fi and app store.

**The point of it all: to get the mirror up and running properly on Home Assistant** as a wall panel (a dashboard on the mirror, a doorbell notice, voice with Assist through the webcam's microphone, a button that really switches the screen off). The later part of the repository is about that; see **[docs/home-assistant-wall-panel.md](docs/home-assistant-wall-panel.md)**.

> **This is a write-up of what worked on one unit, not a ready-made flasher.**
> Partition offsets, hashes and several scripts are specific to that unit. Read your own partition table, take a full eMMC backup first, and verify it. Everything here writes to eMMC; mistakes can leave the device needing maskrom recovery. **Use at your own risk, and only on a device you own.**

The full story (mistakes and corrected assumptions included) is in **[docs/report-en.md](docs/report-en.md)** (English) and **[docs/rapport-no.md](docs/rapport-no.md)** (Norwegian; also as a Word file, [docs/SATS-Mentra-Rflex-rapport.docx](docs/SATS-Mentra-Rflex-rapport.docx)). If you only want to get rid of the lock and keep Android 10, read the short **[quick guide](docs/hurtigguide-no.md)** (Norwegian). The missing hardware volume keys are handled in **[docs/taskbar-volume-button.md](docs/taskbar-volume-button.md)**. Running the mirror as a Home Assistant wall panel is covered in **[docs/home-assistant-wall-panel.md](docs/home-assistant-wall-panel.md)** (overview: adb that survives reboots, the camera and the microphone for Assist, a smooth dashboard, switching the screen off and on from HA) and **[docs/doorbell-camera-performance.md](docs/doorbell-camera-performance.md)** (camera-app freeze, a doorbell notice that wakes the screen, the microphone fix, Cast speakers without Google services). The Markdown reports are the authoritative versions; the Word file is a snapshot. This README is the summary.

*Not affiliated with, endorsed by, or connected to SATS, Mentra or Rockchip. Names are used only to identify the hardware.*

---

## Outcome

| Goal | Result |
|---|---|
| Remove the kiosk lock ([FS] Launcher, `com.mentra.launcher`, device owner) | Done, and it stays removed |
| Newer Android running standalone | Android 13 (`TQ3A.230805.001.A3` GSI) permanently installed in `super`, boots in ~66 s, no DSU |
| App store | Aurora Store (anonymous login) |
| Mirror behaviour (screen off, tap to use) | 60 s screen timeout + a small touch-to-wake service |
| Camera | Works (USB webcam via the external camera HAL; the camera app no longer freezes after fixing the still size) |
| Microphone / Assist | Works: the webcam microphone recorded silence until the USB audio policy got an explicit 16-bit 48 kHz profile (bind-mounted at boot). Some Assist problems remain (intermittent audio loss, no custom wake word) |
| Home Assistant dashboard | Kiosk dashboard in Fully; screensaver, drawing page and 3D house were made much lighter; clock freeze fixed (HA dashboard modules in `device/ha/`) |
| Doorbell | The ring wakes the screen and shows a notice (a picture is not possible from a WebRTC-only doorbell) |
| Screen off from HA | The "switch mirror off" button switches the display off within a second (HA sends the Android sleep key over adb) |
| adb over Wi-Fi | Port 5555, set as a persistent property and re-asserted at every boot (confirmed with a reboot) |
| Hardware video decode | Intentionally disabled for media codecs (see below) |
| Google Play services / YouTube app | Not available on a plain AOSP GSI (so no Cast discovery in Spotify/Google Home; speakers are controlled from Home Assistant instead) |
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
9. **A USB webcam microphone that "records" silence**: the vendor's dynamic USB audio policy makes Android request 24-bit *mono*, a format the camera does not offer, so every open fails and apps get zeros. An explicit 16-bit 48 kHz profile in a copy of `usb_audio_policy_configuration.xml`, bind-mounted over the vendor file, fixes it without touching `/vendor`. Do not restart `audioserver` while something records, and do not force-stop the Companion app (it is the system assistant).
10. **The GPU was not the reason for the choppy dashboard.** The Mali is used and needs 5-12 ms per frame; the cost was thousands of canvas draw calls, O(n) redraws and JavaScript on one little core. Patching the three offending dashboard cards (monkey-patched methods in HA dashboard modules) beat any system tuning. A newer browser (Chrome Beta 158 instead of the WebView 109) was *slower* for the 3D view.
11. **Screen off from Home Assistant**: Fully's JavaScript `turnScreenOff` needs Fully PLUS. Android's shortest screen timeout is 10 s and counts from the last touch; the reliable way is HA's Android Debug Bridge integration sending `input keyevent 223` (sleep) and `224` (wake).

## Security notes (read these)

- `ro.adb.secure=0` + root adb = **unauthenticated root over adb**. Turn wireless debugging off on networks you do not control. In the Home Assistant setup the adb port is kept open at every boot and Home Assistant itself holds a connection to it (screen on/off), so anyone who reaches that port or Home Assistant has root on the mirror.
- The Companion app is the system assistant and has the microphone permission; its local database holds Home Assistant tokens (never commit or share it).
- SELinux types are all permissive; the bootloader is unlocked and verified boot is off.
- There are no OTA updates. Updating means a new GSI and a new write.

## Repository layout

```
docs/       Full report (English; Norwegian as Markdown + Word), quick guide (lock removal only), partition map, checksums
tools/      LP metadata parser/builder, resource-image inspector, logo builder, patch helpers, Companion-app local-push helper, USB audio policy generator
device/     init rc, helper scripts and local tuning for the Android 13 image; data-local/ = boot hooks (microphone policy, persistent adb, assistant setting) and the USB audio policy file; launcher/ = taskbar volume button, fully_show_navbar.sh; ha/ = Home Assistant dashboard modules (doorbell notice, lighter screensaver / drawing page, clock and screen-off fix) and the screen on/off scripts; dexopt_speed.sh = AOT-compile the touch-path apps
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
