# From locked kiosk to standalone Android 13: SATS Mentra Rflex mirror (RK3399)

*Experience report for the forum. Everything was done on a single unit of a discontinued fitness mirror, in one long session (2026-11-04). Serial numbers, usernames and paths are anonymized. Use at your own risk: several of the steps write directly to the eMMC, and the partition offsets below are **specific to this mirror** — read them on your own device, do not copy them blindly.*

---

## 0. TL;DR

| Goal | Outcome |
|---|---|
| Remove the kiosk/device-owner lock ([FS] Launcher, `com.mentra.launcher`) | ✅ Removed, and it stays gone |
| App store on the mirror | ✅ Aurora Store (anonymous login) |
| A newer Android running standalone | ✅ Android 13 (GSI, `TQ3A.230805.001.A3`) permanently installed in `super`, boots in ~66 s without DSU |
| Screen off so the glass works as a mirror, tap to use | ✅ Screen-off timeout 60 s + a small "touch-to-wake" service |
| Hardware video | ❌ Deliberately disabled (kernel panic on VP9, garbage picture on A13). Software decoding instead |
| Google Play services (GMS), YouTube app | ❌ Not present in a pure AOSP GSI. YouTube runs in the browser |

The most important things we learned:

1. **Wiping `userdata` does not remove the lock.** The Mentra app lives on the read-only `odm` partition and re-establishes itself as device owner on the next boot (the build has `su`). The assumption "discontinued product = no re-provisioning" was wrong.
2. **Android versions can be tested without flashing anything** using *Dynamic System Updates* (DSU) and Google's official GSIs, thanks to the mirror having an unlocked bootloader and a Treble vendor.
3. **The vendor part (Android 10, kernel 4.19) can be kept** and combined with a GSI if you make a few adjustments (SELinux, ext4 features, HWUI flags). It is the vendor layer that owns the panel, touch, Wi-Fi, audio, etc.
4. **The hardware video decoder (rkvdec/mpp) is unusable** with this kernel: VP9 causes an IOMMU page fault → kernel panic, on the original Android 10 as well.
5. **Everything is reversible** as long as you have a full eMMC backup + maskrom. We backed up before writing anything, verified it against the device, and placed the permanent install in free space in `super` so that only one old region and the metadata were overwritten.

---

## 1. Hardware and starting point

- **Mirror:** SATS Mentra Rflex (discontinued). SoC Rockchip **RK3399**, ~3.9 GB RAM, 59 GB Samsung eMMC, USB touchscreen (eGalax), Mali-T860.
- **Factory software:** Android 10, kernel **4.19.111** (BSP), Treble (VNDK 29, FCM level 4), *dynamic partitions* (`super`), `vbmeta` with verification disabled (`flags=2`), **unlocked bootloader** (verified boot "orange").
- **The lock:** the app **[FS] Launcher** (`com.mentra.launcher`) is set as *device owner* and runs kiosk/lock-task. ADB is off and blocked by policy (`DISALLOW_DEBUGGING_FEATURES`). The hidden service menu in the launcher uses a time-based TOTP we do not have the key for. There was no soft way in.
- **Way in:** one recessed button on the back = **Rockchip maskrom**. Hold the button while applying power → black screen, the device shows up as "Rockusb Device" (VID `2207`, PID `330C`).
- **PC:** Windows 11 (+ WSL2). Tools: RKDevTool v2.86, Rockchip DriverAssistant v5.14, `adb` (platform-tools), the loader `rk3399_loader_v1.30.130.bin`.

> The Rockchip loader is loaded into RAM (`db`) and does not write flash. Maskrom is always available, regardless of what is in flash, so the device is effectively unbrickable as long as you have a backup.

---

## 2. First obstacle: USB and tooling

| Problem | Solution |
|---|---|
| Maskrom unstable ("device descriptor request failed") on a PC with USB-3 ports only | Correct cable + a **USB-2.0 hub** between PC and mirror. Use the combination that gives a stable "Rockusb Device" in Device Manager |
| `rkdeveloptool` in WSL via `usbipd` | `db`, `rfi` and `ppt` hung repeatedly (USB/IP is too unstable for Rockusb). Abandoned |
| RKDevTool **v3.37** | Crashes. **v2.86 works** (set `config.ini` to English) |
| RKDevTool v2.86 is a GUI | We drove it with Windows UI Automation/Win32 (`BM_CLICK`) against the *Advanced Function* tab: **Read Flash Info**, **Export Image** (reads an LBA region to a file), **Erase LBA**, **Reset Device**. We used an allow-list of permitted buttons in the script to avoid accidental writes |
| Modal dialog "idbloader did not find match partition" blocks the window | Dismissed with `BM_CLICK` on OK (may appear with a delay) |

---

## 3. Partition map (read, not modified)

Read with RKDevTool v2.86. Total **120,832,000 sectors × 512 B = 61,865,984,000 bytes**, GPT with a backup GPT in the last 33 sectors.

| # | LBA (hex) | Size (hex) | Name | Size |
|---|---|---|---|---|
| 01 | 0x4000 | 0x2000 | uboot | 4 MiB |
| 02 | 0x6000 | 0x2000 | trust | 4 MiB |
| 03 | 0x8000 | 0x2000 | misc | 4 MiB |
| 04 | 0xa000 | 0x2000 | dtb | 4 MiB |
| 05 | 0xc000 | 0x2000 | dtbo | 4 MiB |
| 06 | 0xe000 | 0x800 | vbmeta | 1 MiB |
| 07 | 0xe800 | 0x10000 | boot | 32 MiB |
| 08 | 0x1e800 | 0x2000 | security | 4 MiB |
| 09 | 0x20800 | 0x30000 | recovery | 96 MiB |
| 10 | 0x50800 | 0x38000 | backup | 112 MiB |
| 11 | 0x88800 | 0xc0000 | cache | 384 MiB |
| 12 | 0x148800 | 0x8000 | metadata | 16 MiB |
| 13 | 0x150800 | 0x400 | frp | 512 KiB |
| 14 | **0x150c00** | 0x614000 | **super** | 3112 MiB (system + vendor + product + odm) |
| 15 | 0x764c00 | 0x6bd73df | userdata | ~53.9 GiB |

Check: `userdata` end = 7,752,704 + 113,079,263 = 120,831,967 = total − 33 (backup GPT).

Working rules we set for ourselves (they saved us several times):

- **Never** generic RK3399 firmware: the panel settings live in the mirror's own software → black screen.
- **Never** `EraseAll` / write to the whole flash.
- **Nothing is written before a full backup has been taken, verified and copied off.**
- Do not touch `uboot`/`trust`/`parameter`/`boot`.
- Unsure about an offset? Stop.

---

## 4. Full backup (before anything else)

- The whole eMMC (61,865,984,000 bytes) was read in chunks with *Export Image* and reassembled into a single file. Verified by size (`total_sectors × 512`) and SHA-256, and copied to a second disk.
- A mistake along the way: the script meant to detect "chunk done" counted lines in the log window, but RKDevTool **clears the log for each export**. Fixed to look for the *Success* line **and** a correct file size.
- Small stuff: a PowerShell function named `H` collided with an alias; a parameter `$Gz` and a variable `$gz` are the same variable (PowerShell is not case-sensitive).
- Before the permanent flash in chapter 11 we additionally compared **the live `system` region on the device byte-for-byte against the backup** (same SHA-256) — so we know the backup actually represents the device, not just that the file is readable.

---

## 5. The first attempt and the mistake we learned the most from

**Plan (from the handover document):** the device owner lives in `/data` (`device_owner*.xml`, `device_policies.xml`) → zero out `userdata` → the lock is gone, and since the product is discontinued there is no server to set it up again.

**What happened:** the mirror rebooted onto a clean `/data`, but again showed the Mentra mirror setup in [FS] Launcher. **The lock came back.**

**Cause:** [FS] Launcher is not just an app in `/data`. The APK (≈19 MB) lives in `/odm/bundled_uninstall_back-app/com.mentra.launcher/`, on a read-only partition that a `userdata` wipe does not touch. The Rockchip/vendor Android 10 build installs it on first boot, and since the build has `su` (userdebug-like) the app sets itself up as device owner — no server involved.

**Correct procedure on the original Android 10 (done, with the owner's approval):**

1. After the `userdata` wipe, ADB (with root) was available. We pulled `device_owner_2.xml`, `device_policies.xml`, `package-restrictions.xml` and `settings_global.xml` to understand the state.
2. Removed the device-owner/policy files in `/data/system/`, and marked the package uninstalled for user 0 in `package-restrictions.xml`.
3. **Hid the APK permanently** with an overlayfs: `adb remount` creates a `scratch` partition in free `super` space, and in the overlay a *whiteout* is created over `com.mentra.launcher` in `/odm`. Then it cannot be reinstalled on the next boot.
4. Result: a normal Android launcher, no device owner. (The Mentra logo during boot is a separate cosmetic theme; it was replaced later — see 10.2.)

> **Corrected assumption:** "a userdata wipe removes the lock" — no, only if the app that sets it does not come back. Always check where the kiosk app *installs from*.

(This is the only part you need if you just want to get rid of the lock and keep Android 10. The rest of the report is about moving on to Android 13.)

---

## 6. Mapping the hardware (what is actually in this mirror?)

To judge how far up in Android version we could go, we read the system on the device:

- Treble vendor (VNDK 29), `ro.boot.dynamic_partitions`, vbmeta without verification, unlocked bootloader → **GSIs can run on top of the vendor**.
- Kernel 4.19.111: Android 13 supports 4.19, but the vendor HALs (Mali r18p0 blob, rkvdec, Wi-Fi/BT, audio) are built against Android 10.
- FCM level 4 (Android 10) → newer Android versions run in "compatibility mode" against the vendor. That is what makes this possible, and it is also the source of all the problems below.
- Chrome 156 has `minSdk 32` (Android 12L+). That is a concrete argument for A13 instead of A11.

---

## 7. Test without flashing: DSU + Google's GSIs

**DSU (Dynamic System Updates)** installs a system image in a separate dynamic partition (`system_gsi`) and its own `userdata_gsi` image **as files in `/data/gsi`**. The next boot is *one-shot*: if it does not boot, or you reboot, you are back on the original Android. Nothing in `super` is touched, and `vendor`/`odm` from the mirror are reused.

- Android 10 has DSU but hides the UI behind a feature flag (`persist.sys.fflag.override.settings_dynamic_system`); installation can also be started against the `dynsystem` service. (Today's A13 shows "DSU Loader" under Developer options.)
- We downloaded the **official Google GSIs**: Android 11 (`RP1A`), 12 (`SQ3A`), 13 (`TQ3A`), `arm64`, the `A/B` variant, extracted to a raw `system.img` and gzipped to `system_raw.gz`.

Results:

| GSI | Result |
|---|---|
| **Android 11** | Boots. HWUI crashes with `EGL_BAD_ACCESS` against the Mali blob. Solved with `debug.hwui.use_partial_updates=false`, `debug.hwui.use_buffer_age=false` |
| **Android 12** | Hung/looped at boot (the logo stayed). Cause **not** determined; likely candidates are the ones later solved on A13 (SELinux mismatch, ext4 features, `seclabel` requirement) |
| **Android 13** | Boots and runs after the modifications below |

### Modifications needed for A13 to run on the Android 10 vendor

Everything is done on a **modified copy** of `system.img` (raw ext4, `shared_blocks`) that we rebuilt into a normal writable ext4:

1. **Rebuild ext4 with a kernel-friendly feature set** for 4.19: `mke2fs -d <extracted gsi> -O ^has_journal,^resize_inode,^64bit,^metadata_csum,^orphan_file,^flex_bg,uninit_bg`. Newer `e2fsprogs` on the PC enables features (`orphan_file`, `metadata_csum`) that kernel 4.19 cannot mount. Preserve the `security.selinux` xattrs (`os.getxattr`/`setxattr`), otherwise the files become unlabeled.
   *Mistake we made:* the first image was 2304 MB — too small, since `mke2fs -d` expands out what `shared_blocks` shared. Had to go to 3072 MB.
2. **`build.prop`:** `ro.secure=0`, `ro.adb.secure=0`, `ro.debuggable=1`, `persist.sys.usb.config=adb`, `service.adb.root=1`, `debug.hwui.use_partial_updates=false`, `debug.hwui.use_buffer_age=false`, `debug.renderengine.backend=gles` (A13 uses Skia RenderEngine by default; the GLES backend works better against the old Mali blob).
3. **SELinux:** the Android 13 platform policy and the Android 10 vendor policy do not fit together. We added `(typepermissive <type>)` for all ~1820 types in `plat_sepolicy.cil` (including the vendor types). Globally `getenforce` still says "Enforcing", but all domains are effectively permissive: **violations are logged, not blocked**. The vendor's `precompiled_sepolicy` has the wrong hash against the new platform, so init compiles from CIL at boot (a bit slower, but it works).
4. **Init gotcha:** `init` refuses to start a service that cannot do a domain transition, *even if* the domain is permissive. Custom services must have `seclabel u:r:shell:s0` (or another existing domain).
5. **Boot diagnostics:** a custom service wrote `dmesg`, `getprop` and `logcat` to `/metadata/dbg` (unencrypted, readable from another Android version afterwards), and a watchdog rebooted the machine if `boot_completed` did not arrive. This was crucial for understanding crashes; `pstore/ramoops` gave us the panic log for the video crashes.

Pitfalls along the way (all self-inflicted, all instructive):
- PowerShell expands `$(...)` locally before `adb shell` sees it. **Write the scripts to a file and `adb push` them** instead of quoting complex commands.
- The WSL2 VM shuts down when "idle" and drops loop mounts. Keep it alive (`wsl ... sleep 10800`) and mount inside the script itself.
- A `service call dynamic_system 5` removed an already-installed DSU image. Remember that DSU commands are destructive; check `gsi_tool status` first.

---

## 8. App store, Chrome and browser

- **Aurora Store** (open-source Play client, APK from the GitHub/F-Droid source) with **anonymous login** via the Aurora dispenser. No Google account is logged in on the mirror.
- **Chrome** from Aurora. Requires Android 12L+ (`minSdk 32`) — a concrete reason we chose A13.
- **The YouTube app** requires Google Play services (GMS) and does not work on a pure GSI. YouTube in Chrome works, but is heavy (see the next chapter).

---

## 9. Video: what works, and why hardware decoding is turned off

The user experienced that YouTube in Chrome "worked poorly" and asked whether the hardware is strong enough, and whether it is because A13 runs on top of A10. The answer is "both."

**Findings:**

- **The decoder stack:** the vendor's `OMX.rk.video_decoder.*` (via `omx_vdec`/`mpp`/`rkvdec`) is written for the Android 10 framework. Android 13 uses `ACodec` with `DynamicANWBuffer`/`-1010` errors against it → **corrupt picture** on H.264/HEVC with hardware decoding.
- **VP9:** IOMMU page fault in `rkvdec` → **kernel panic**. This happens **on the original Android 10 as well**, so it is a kernel/driver problem and not something the GSI does.
- **CPU:** RK3399 = 2×Cortex-A72 + 4×A53. Software decoding of 1080p H.264 keeps both A72 cores ~98 % busy; 1080p VP9 is around 65 %. It works, but 1080p YouTube is at the limit. 720p is comfortable.

**Solution:** make the hardware decoder unavailable to everything except the camera service (see 9.1 for why "everything except root" was not enough). In `init` rc:

```
on boot
    chmod 0600 /dev/mpp_service
    chown cameraserver root /dev/mpp_service
```

Then `MediaCodec` fails on the OMX component (opening `/dev/mpp_service` fails), and Chrome falls back to software decoding. **Verified** on both H.264 1080p (Chrome, `OMX.rk.video_decoder.avc` → "Failed to get input buffer", fallback to software) and VP9 1080p (`OMX.rk.video_decoder.vp9` → fallback), both without kernel errors.

Additionally the startup script writes `/data/local/chrome-command-line` with `_ --disable-accelerated-video-decode`, so Chrome does not even try (note: Chrome reads that file only on "debuggable" Android, and our build has `ro.build.type=user`, so the effect of this particular file is *not* confirmed; blocking the node is what actually does the job).

**Limitation:** other apps that use `MediaCodec` directly without a fallback (e.g. some players) may fail instead of falling back. A more complete fix is to remove `OMX.rk.video_decoder.*` from the vendor's `media_codecs*.xml` — we have not done that, because it would require changing `vendor`.

---

### 9.1 Side effect: the camera image turned green (and why)

The first version of the block was `chmod 0000` + `chown root root`. Right afterwards the camera app showed **only a green picture**, and the camera provider process died with `signal 13`/`CAMERA_ERROR`. The log said it plainly:

```
ExtCamDevSsn@3.4: failed to prepare JPEG decoder
HAL_JPEG_VDPU2:   hal_jpegd_vdpu2_init mpp_dev_init failed. ret: -1
```

**Explanation:** the mirror's camera is an ordinary USB webcam (UVC, `RGB Camera`) that delivers **MJPEG**. The external camera HAL decodes MJPEG with the **same VPU (`/dev/mpp_service`)** as the video decoder. Blocking the node meant the buffers were never written — and zeroed YUV buffers show as green.

**Fix (two attempts):**

1. `chmod 0660` + group `cameraserver` → did **not** work at cold boot: the vendor process runs as user `cameraserver`, but with the primary group from its `group` line (`audio camera input drmrpc`), not `cameraserver`. (The temporary test with `chown cameraserver:cameraserver` + `0600` had worked because it granted *ownership*.)
2. **Final:** `chown cameraserver root` + `chmod 0600`. Only the *user* `cameraserver` (and root) can open the node; `mediacodec` (video decoding) cannot → still software video decoding. Verified after a cold boot: no `failed to prepare JPEG decoder`, `HAL_JPEG_VDPU2` runs, the picture is real.

> Lesson: a "safe" block of a shared device node must be tested against *all* users that legitimately need it. Here it was the camera that depended on the video hardware — not something you guess.

---

## 10. The mirror function: screen off + tap to use

Goal: the glass should be a mirror (screen black/off) until someone taps.

- **Screen-off timeout:** `settings put system screen_off_timeout 60000` (60 s) and `cmd lock_settings set-disabled true` (no lock screen). Run once on first boot.
- **Touch-to-wake:** Android 13 does not wake the screen on touch by itself. Tried and **not effective:** an IDC file with `touch.wake=1` for the eGalax touchscreen (the effect does not exist in this input stack).
- **Solution:** a small service that reads raw evdev events from the touch node and calls `input keyevent 224` (WAKEUP) if the screen is not awake:

```sh
#!/system/bin/sh
# Touch-to-wake helper for the SATS mirror
DEV=/dev/input/$(grep -A8 -i 'eGalax' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1)
while true; do
  # block until the touchscreen reports an event, then wake the display if it's off
  getevent -c 1 "$DEV" > /dev/null 2>&1 || { sleep 2; continue; }
  if ! dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake'; then
    input keyevent 224
  fi
  sleep 1
done
```

- **Mistakes we made twice here:**
  1. We interpreted a "recognized tap" as touch waking the screen, but it was the owner who had touched both the screen and the keyboard; the *keyboard* woke it. Raw touch does not wake it by itself.
  2. The first version checked `mWakefulness=Asleep`. After `sleep`, Android goes through **`Dozing` (≈2 s) → `Asleep`**, and a tap in the `Dozing` window was ignored. The correct test is "not `Awake`".
- Tested with **synthetic touch events** (`sendevent` against the touch node, the same path as a real tap). A real finger tap on the finished system is tested by the owner where applicable; see "Not verified" at the end.

---

### 10.1 UI size and speed (tuned after the system was up)

The owner felt everything was too big and that the machine was slow.

- **Display size:** the panel is 1080×1920 with `ro.sf.lcd_density=240` (≈ "150 % zoom" in Windows terms; 160 dpi = 100 %). `wm density 180` (≈ 112 %) gave more room and is a pure Android setting (`wm density reset` undoes it; it survives reboot and does not affect the system image). For smaller/larger: `wm density 160`/`200`.
- **Speed:** measured state: CPU governor `interactive` (A53 408–1416 MHz, A72 408–1800 MHz), GPU `simple_ondemand` which **idles at 200 MHz** (Mali-T860, 200–800 MHz), DDR `dmc_ondemand` at max. Because we run with `debug.hwui.use_partial_updates=false`, the whole 1080×1920 is redrawn every frame, and the GPU takes too long to ramp up. Measures: animation scales 0.5 (`window/transition/animator`), **GPU min 400 MHz**, **CPU floor 816 MHz** on both clusters. Idle temperature ~43–47 °C, so there is good margin. No noise from SELinux logging (the avc lines did not grow at idle).
- **Make tuning persistent without reflashing the system:** the system image is read-only, so `mirror_setup.sh` got a hook: `[ -f /data/local/mirror_local.sh ] && sh /data/local/mirror_local.sh`. Everything to be tuned (GPU/CPU frequencies, governor, etc.) lives in that file on `/data` and can be edited over `adb` without a reflash.
- **How the hook change got into an already-installed system:** a *same-length single-block patch*. For small files (< 4 KiB) where the file size does not change, we use `debugfs bmap` to find the filesystem block, compute which `super` block it sits in (extent A or B), build a new 4 KiB block with the new content padded with a comment line to exactly the same length, and write only that block with `dd` after checking that the current block has the expected hash. The inode is untouched, `e2fsck` is still clean. Note: this assumes the file uses only one block, and the change takes effect from the next boot.

---

### 10.2 The boot logo (Mentra → "Magic Mirror")

During boot, first U-Boot's logo and then the kernel's logo are shown. The Android phase (boot animation) is just the ordinary "android" text on A13 (we checked by running `start bootanim` on the running system; `/odm/media/bootanimation.zip` with Mentra's "Loader-Symbol" is not used by A13).

**Where is the logo?** Not in a dedicated `resource` partition: the `dtb` partition is empty. Instead, a Rockchip **resource image** (`RSCE`) sits as the "second" part of the `boot` partition (offset 27,025,408 bytes). It has three entries:

| Entry | Content |
|---|---|
| `rk-kernel.dtb` | the device tree (we do not touch it — the panel settings live here) |
| `logo.bmp` | the U-Boot logo: **240×240, 8-bit, uncompressed, 42-color palette, 57,822 bytes** |
| `logo_kernel.bmp` | the kernel logo: a byte-identical copy of `logo.bmp` |

The structure is an `RSCE` header (512 B block) + 512-byte entries (`ENTR`, 256-byte path, `offset` and `size` in blocks/bytes). Nothing other than the logo entries needs to be touched, and **there is no checksum over the resource image** that we could see (whereas `vbmeta` has verification disabled, `flags=2`).

**Procedure — swap the content of the file, not the structure:**

1. Draw a 240×240 logo (we used `System.Drawing` on Windows: an oval mirror frame, two "glint" strokes, three small stars and the text "MAGIC MIRROR", white on black).
2. Quantize to **42 grayscale levels** (the palette space in the original) and write a BMP with **exactly the same header** as the original (same height sign = bottom-up, same pixel offset 222, same `biClrUsed`=42), so the file size is identical (57,822 bytes). That way no repacking is needed and no offsets change.
3. Each file occupies 113 sectors (57,822 bytes + 34 bytes padding). The two regions are right after each other (`logo.bmp` @ sector 53,004, `logo_kernel.bmp` @ sector 53,117), so it is **a single write of 226 sectors** keeping the original's padding bytes.
4. On the device: abort if (a) the region is not identical to the original, (b) the whole 32 MiB `boot` partition does not have the same SHA-256 as the backup, (c) the patch file has the wrong hash. Write with `dd`, read back the region, and finally check that **the whole `boot` partition = original + only the logo patch** (precomputed hash). Everything went green.

Rollback: write back the same 226 sectors from the `boot` backup (or the whole `boot` partition).

> Note: we chose *not* to swap the files in the resource image with a repacker (`resource_tool`), because repacking moves offsets and requires rewriting the whole `boot` partition. A same-size swap is much less risky.

**Result:** the first version (drawn upright) was shown **90° wrong** on the panel. After rotating the bitmap **90° clockwise** before writing (pixel `(x, y)` → `(239−y, x)`; same write procedure, now with a hash check against the previously written state instead of the original), the logo is correct, confirmed by the owner at cold boot. Lesson: the panel is physically a portrait panel driven in a different orientation under U-Boot/kernel, so images in the resource image must be **pre-rotated** — not stored the way they should look. If you swap the logo on another device: expect to have to test one rotation, and keep the backup of the 226 sectors ready.

---

## 11. Permanent installation of Android 13 in `super`

The owner chose "Permanent Android 13" after being told that this is a real flash change.

### 11.1 Why it is simpler than it sounds

- `super` is an **LP metadata area (first 1 MiB) + dm-linear extents**. System = one list of extents. We do not need to move `vendor`/`odm`/`product` — they stay fixed on their sectors.
- The Android 13 GSI has `/product` and `/system_ext` *inside* the system image and a `skip_mount.cfg` (`/product`, `/system_ext`) that makes first-stage init **not** mount the mirror's own `product` partition. It can stay untouched (Android 10 content, unused, but still in the metadata).
- The GSI ignores `/odm/bundled_uninstall_back-app` (a vendor folder that only Rockchip's Android 10 framework scans). **Mentra is therefore not visible to A13 at all**, without us needing the overlay (`scratch`) anymore. Verified: no `com.mentra.*`, no device owner.

### 11.2 Layout

The finished system became **2377.7 MiB** (4,869,440 sectors; shrunk with `resize2fs -M` + 64 MiB slack). The old `system` region is only 896 MiB, so the system gets **two extents**:

| Extent | Sectors (512 B) | Physical start in `super` | Note |
|---|---|---|---|
| A | 1,834,952 | 2048 | the old system region (overwritten) |
| B | 3,034,488 | 2,930,688 | free tail in `super` (1 MiB-aligned) |

`vendor` (467,312 @ 1,837,056), `product` (580,864 @ 2,306,048) and `odm` (40,408 @ 2,887,680) are **unchanged**. The group size is 5,958,024 sectors (2909.2 MiB) of a max of 3108 MiB.

### 11.3 LP metadata — written ourselves, validated by AOSP

We wrote a minimal parser/rewriter for the `liblp` format in Python (appendix A): reads geometry + metadata, changes the partition and extent tables, recomputes SHA-256 for header and tables, and writes primary + backup for slot 0. Validation chain:

1. Our own parser reads the original metadata from the backup **and** the live metadata from the device (incl. `scratch`) — matches `lpdump` from the device.
2. The new metadata is read by **the device's own AOSP `lpdump`** (`lpdump <file>`) without errors, and shows exactly the expected layout.
3. After writing, the real `super` on the device is read with `lpdump`.
4. Before the metadata was written, we built a `dm-linear` device (`dmctl create`) with exactly the same table first-stage init will create, read the whole device back and compared the SHA-256 with the PC image, and mounted it read-only (`ro.build.version.release=13`).

### 11.4 Order and verification (from the running DSU guest)

1. `system_final.img` (2,493,153,280 B) was gzipped, `adb push`-ed to the guest's `/data`, decompressed on the device, and hash-checked (`40ad3720…`).
2. Pre-checks in the script: image hash, **live LP metadata is what we expect**, size of `super`.
3. Write **extent B** (free space) → read back → SHA-256 equal.
4. Write **extent A** (where the original `system` is overwritten) → read back → SHA-256 equal.
5. `dm-linear` test of the new layout (point 4 above).
6. Write **LP metadata** (first 1 MiB) → read back → `lpdump`.
7. Check: the `vendor`/`product`/`odm` regions are still **byte-identical with the backup**.
8. `misc`: bootloader_message `boot-recovery` + `recovery\n--wipe_data\n` → `reboot recovery`. The mirror's own Android 10 recovery formatted `/data` (≈48 s) and rebooted. (This was also necessary because the DSU images live in `userdata`.)

The whole write phase (B + A + verification) took about 1.5 minutes with `dd` (60–70 MB/s).

> Note: the filesystem is mounted read-only from `dm-0` while we later patched a single 4 KiB data block (the touch-wake script) directly on the block device, with a block hash before and after. That is safe for a file on a single block when the file size is unchanged (the inode is untouched), and the change takes effect on the next boot.

### 11.5 Rollback (prepared, not used)

- **Rollback slice** (`super` sector 0–1,837,000 from the verified backup = original LP metadata + original system region; hash-checked against the device) is written back to LBA `0x150c00` (maskrom + RKDevTool, or `dd` from Android if it comes up). The original `system` then becomes valid again together with the original metadata.
- Extent B sits in previously free space, so it does not need to be restored.
- What **cannot** be rolled back this way: the `scratch` overlay that hid Mentra on the original Android 10 (overwritten). After a rollback to the original Android 10, the Mentra hiding must be redone (chapter 5).
- A full backup of the whole eMMC exists as a last resort (`wl 0 eMMC_full_backup.img`).

---

## 12. Result

Verified on the permanent system (two boots, the last without a data wipe):

- The root fs is `dm-0` = the LP partition `system` (4,869,440 sectors), `vendor`/`odm` from the mirror, `/data` is the real `userdata` (ext4). `gsi_tool status` = "normal" (no DSU).
- `ro.build.version.release=13`, SDK 33, `sys.boot_completed=1` about **66 s** after boot. No kernel errors, no tombstones/ANR.
- `/dev/mpp_service` is `c---------` (blocked); the `tw_daemon` service runs from init; screen-off timeout 60000 ms.
- Screen off → synthetic touch → **the screen wakes** (with the patched watchdog).
- No Mentra packages, no device owner.
- Aurora Store sideloaded; the mirror is on Wi-Fi (set up by the owner on the screen — we never type a password for the owner).

---

## 13. Limitations, risk and security (be honest with yourself)

- **ADB is root and without authentication** (`ro.adb.secure=0`). This is deliberate (no physical USB access when the mirror hangs on the wall), but it means that **wireless debugging on a network you do not control is an open door**. Turn it off when you are done.
- **SELinux is effectively off** (all types permissive). Do not use this for anything security-critical.
- **Unlocked bootloader** (`orange`), `vbmeta` without verification. No verified boot.
- **No OTA.** Updating the system = new GSI + a new write. The security patches are the same as the GSI you loaded.
- **No GMS.** No Play Store, no YouTube app, no Google login; Aurora uses an anonymous account and may get rate-limited.
- **The vendor is still Android 10**, and will remain so. Unknown HAL problems may surface (camera, audio/mic not thoroughly tested here).
- **The boot logo** (U-Boot + kernel) lives in the `boot` partition's resource image and has been replaced with a custom "Magic Mirror" logo (10.2). Anyone testing this on another device should expect the image orientation/placement to differ.
- Swapping hardware (a different panel/touch variant) may make the partitions/layout not match; **read your own partition table**.

### Not verified / open

- A real finger tap on the *finished* system wakes the screen (tested synthetically, and earlier manually on the DSU guest only with a keyboard).
- Why Android 12 hung at boot (we moved on to 13).
- Whether `/data/local/chrome-command-line` is read by Chrome on a "user" build (blocking `/dev/mpp_service` is what ensures fallback).
- Audio/mic not fully tested after the switch to A13. **Camera works** (webcam via the external HAL, VPU JPEG decoding), after the fix in 9.1.
- The rollback slice is hash-checked, but not written back.

---

## 14. Mistakes and corrected assumptions — summary

1. "A userdata wipe removes the lock" → no, Mentra re-provisions from `/odm`.
2. "`rkdeveloptool` + `usbipd` works" → no, it hung. Use RKDevTool v2.86.
3. Completion detection in the backup loop via log count → RKDevTool clears the log; use *Success* + file size.
4. PowerShell quoting of complex `adb shell` commands → write `.sh` files and `adb push`.
5. The first `mke2fs` to 2304 MB was too small → 3072 MB.
6. The WSL2 VM shuts down and drops loop mounts → keep it alive and mount in the script.
7. `init` requires `seclabel` on services even with permissive SELinux.
8. IDC `touch.wake` does not work here → a custom watcher.
9. We interpreted manual touches as a "real test" → the owner pointed out that *they* had tapped; only the keyboard woke it.
10. The watcher ignored `Dozing` → test "not Awake".
11. An accidental `service call dynamic_system 5` deleted a DSU installation.
12. "We must build our own `product` partition and keep `scratch`" → unnecessary: the GSI skips `product`, and A13 does not see Mentra.
13. "A13 on A10 vendor gives poor video because the machine is weak" → partly; a large part is decoder mismatch + a kernel bug.
14. "Blocking the VPU node for everyone is safe" → no: the webcam's MJPEG decoding uses the same VPU. Result: a green camera image.
15. The first fix used the *group* `cameraserver`; the process has a different primary group. Use *ownership* (user) instead, and test after a cold boot — not just with a temporary `chown` that happened to cover it.
16. `su <uid>` does not exist in this build (adb runs as root directly) — a per-user access test must be done in other ways, or inferred by the owner/mode.
17. PowerShell + `adb shell "..."` with embedded `$(…)`/quotes failed again (third time): always write the script as a `.sh`.
18. The boot logo was first written upright and shown 90° wrong → rotate the bitmap 90° clockwise (see 10.2).
19. A search field in the launcher was attempted removed with long-press/drag (did not work: it is the launcher's built-in search box, not an ordinary widget). Attempted solution: disable the search app `com.android.quicksearchbox` (`pm disable-user --user 0`). **This did not remove the box** — after a launcher restart an empty "Søk" placeholder box is still shown at the top of the home screen. Unsolved (see `docs/taskbar-volume-button.md`). At the same time `input` taps got in the way of the owner's own use of the screen — do not drive the UI while someone is using it.

---

## Appendix A – LP metadata tool (Python 3, `lp_tool.py`)

Usage: `python3 lp_tool.py dump <super_first_MiB.bin>` and
`python3 lp_tool.py build <original_first_MiB.bin> <out.bin> --system-sectors <N> --extent-b-start <S>`.
Always validate the result with the device's own `lpdump <out.bin>` before you write anything.

```python
#!/usr/bin/env python3
"""Minimal liblp (Android dynamic partitions) metadata parser / rewriter for the SATS mirror super partition.
Usage:
  lp_tool.py dump  <super_head.bin>
  lp_tool.py build <stock_super_head.bin> <out.bin> --system-sectors N --extent-b-start S
"""
import hashlib, struct, sys

GEOM_FMT = '<II32sIII'              # magic, struct_size, checksum, metadata_max_size, slot_count, logical_block_size
GEOM_MAGIC = 0x616c4467
HDR_FMT = '<IHHI32sI32s'            # magic, major, minor, header_size, header_checksum, tables_size, tables_checksum
HDR_MAGIC = 0x414C5030
DESC_FMT = '<III'                   # offset, num_entries, entry_size
PART_FMT = '<36sIIII'               # name, attributes, first_extent_index, num_extents, group_index
EXT_FMT = '<QIQI'                   # num_sectors, target_type, target_data, target_source
GRP_FMT = '<36sIQ'                  # name, flags, maximum_size
BDEV_FMT = '<QIIQ36sI'              # first_logical_sector, alignment, alignment_offset, size, name, flags
RES = 4096
GSZ = 4096


def cstr(b):
    return b.split(b'\0', 1)[0].decode()


def parse_geometry(buf, off):
    magic, ssz, ck, max_size, slots, lbs = struct.unpack_from(GEOM_FMT, buf, off)
    assert magic == GEOM_MAGIC, hex(magic)
    raw = bytearray(buf[off:off + ssz]); raw[8:40] = b'\0' * 32
    assert hashlib.sha256(raw).digest() == ck, 'geometry checksum'
    return dict(struct_size=ssz, max_size=max_size, slots=slots, lbs=lbs)


def parse_metadata(buf, off):
    magic, major, minor, hsz, hck, tsz, tck = struct.unpack_from(HDR_FMT, buf, off)
    assert magic == HDR_MAGIC, hex(magic)
    hdr = bytearray(buf[off:off + hsz]); hdr[12:44] = b'\0' * 32
    assert hashlib.sha256(hdr).digest() == hck, 'header checksum'
    p = off + struct.calcsize(HDR_FMT)
    descs = []
    for _ in range(4):
        descs.append(struct.unpack_from(DESC_FMT, buf, p)); p += 12
    flags = struct.unpack_from('<I', buf, p)[0] if hsz >= p - off + 4 else 0
    tables = bytes(buf[off + hsz: off + hsz + tsz])
    assert hashlib.sha256(tables).digest() == tck, 'tables checksum'
    def ents(d, fmt):
        o, n, sz = d
        assert sz == struct.calcsize(fmt), (sz, fmt)
        return [struct.unpack_from(fmt, tables, o + i * sz) for i in range(n)]
    parts = [dict(name=cstr(a), attr=b, first=c, n=d, group=e) for a, b, c, d, e in ents(descs[0], PART_FMT)]
    exts = [dict(sectors=a, ttype=b, data=c, src=d) for a, b, c, d in ents(descs[1], EXT_FMT)]
    grps = [dict(name=cstr(a), flags=b, max=c) for a, b, c in ents(descs[2], GRP_FMT)]
    bdevs = [dict(first=a, align=b, align_off=c, size=d, name=cstr(e), flags=f) for a, b, c, d, e, f in ents(descs[3], BDEV_FMT)]
    return dict(major=major, minor=minor, hsz=hsz, flags=flags, parts=parts, exts=exts, grps=grps, bdevs=bdevs,
                raw_header=bytes(buf[off:off + hsz]))


def read_all(path):
    buf = open(path, 'rb').read()
    g = parse_geometry(buf, RES)
    g2 = parse_geometry(buf, RES + GSZ)
    assert g == g2, 'primary/backup geometry differ'
    prim = RES + 2 * GSZ
    back = prim + g['max_size'] * g['slots']
    slots = []
    for s in range(g['slots']):
        a = parse_metadata(buf, prim + s * g['max_size'])
        try:
            b = parse_metadata(buf, back + s * g['max_size'])
        except AssertionError as e:
            b = None
        slots.append((a, b))
    return buf, g, slots


def dump(path):
    buf, g, slots = read_all(path)
    print(f'geometry: {g}')
    for s, (a, b) in enumerate(slots):
        print(f'--- slot {s}: v{a["major"]}.{a["minor"]} header_size={a["hsz"]} flags={a["flags"]} backup_equal={b is not None and a["parts"]==b["parts"] and a["exts"]==b["exts"]}')
        for bd in a['bdevs']: print('  block device', bd)
        for gr in a['grps']: print('  group', gr)
        tot = 0
        for p in a['parts']:
            es = a['exts'][p['first']:p['first'] + p['n']]
            sec = sum(e['sectors'] for e in es); tot += sec
            print(f'  part {p["name"]:10s} attr={p["attr"]} group={p["group"]} sectors={sec} ({sec*512/1048576:.1f} MiB)')
            for e in es: print(f'      extent {e["sectors"]:>9d} sectors  type={e["ttype"]} phys_sector={e["data"]} dev={e["src"]}')
        print('  total partition sectors', tot)


def pack_tables(parts, exts, grps, bdevs):
    pt = b''.join(struct.pack(PART_FMT, p['name'].encode().ljust(36, b'\0'), p['attr'], p['first'], p['n'], p['group']) for p in parts)
    et = b''.join(struct.pack(EXT_FMT, e['sectors'], e['ttype'], e['data'], e['src']) for e in exts)
    gt = b''.join(struct.pack(GRP_FMT, g['name'].encode().ljust(36, b'\0'), g['flags'], g['max']) for g in grps)
    bt = b''.join(struct.pack(BDEV_FMT, d['first'], d['align'], d['align_off'], d['size'], d['name'].encode().ljust(36, b'\0'), d['flags']) for d in bdevs)
    offs = []; o = 0
    for t in (pt, et, gt, bt): offs.append(o); o += len(t)
    tables = pt + et + gt + bt
    descs = [(offs[0], len(parts), struct.calcsize(PART_FMT)), (offs[1], len(exts), struct.calcsize(EXT_FMT)),
             (offs[2], len(grps), struct.calcsize(GRP_FMT)), (offs[3], len(bdevs), struct.calcsize(BDEV_FMT))]
    return tables, descs


def build(stock_path, out_path, system_sectors, b_start):
    buf, g, slots = read_all(stock_path)
    a, _ = slots[0]
    assert a['major'] == 10
    bdev = a['bdevs'][0]
    byname = {p['name']: p for p in a['parts']}
    assert set(byname) >= {'system', 'vendor', 'product', 'odm'}, list(byname)
    sys_ext = a['exts'][byname['system']['first']:byname['system']['first'] + byname['system']['n']]
    assert len(sys_ext) == 1 and sys_ext[0]['ttype'] == 0
    A = sys_ext[0]
    extB_sectors = system_sectors - A['sectors']
    assert extB_sectors > 0 and extB_sectors % 8 == 0 and b_start % 8 == 0
    dev_sectors = bdev['size'] // 512
    assert b_start + extB_sectors <= dev_sectors, 'extent B beyond super'
    # B must not overlap any other partition extent
    others = []
    for n in ('vendor', 'product', 'odm'):
        p = byname[n]
        for e in a['exts'][p['first']:p['first'] + p['n']]:
            others.append((e['data'], e['data'] + e['sectors'], n))
    for lo, hi, n in others:
        assert b_start >= hi or b_start + extB_sectors <= lo, f'extent B overlaps {n}'
    new_parts, new_exts = [], []
    for name in ('system', 'vendor', 'product', 'odm'):
        p = dict(byname[name])
        es = [dict(e) for e in a['exts'][p['first']:p['first'] + p['n']]]
        if name == 'system':
            es.append(dict(sectors=extB_sectors, ttype=0, data=b_start, src=A['src']))
        p['first'] = len(new_exts); p['n'] = len(es)
        new_exts += es; new_parts.append(p)
    grp = a['grps'][1] if len(a['grps']) > 1 else a['grps'][0]
    total = sum(e['sectors'] for e in new_exts)
    gi = new_parts[0]['group']
    assert total * 512 <= a['grps'][gi]['max'], f'group max exceeded: {total*512} > {a["grps"][gi]["max"]}'
    tables, descs = pack_tables(new_parts, new_exts, a['grps'], a['bdevs'])
    # header: keep stock header layout (version, header_size, flags), recompute descriptors/size/checksums
    hsz = a['hsz']
    hdr = bytearray(a['raw_header'])
    struct.pack_into('<I', hdr, 44, len(tables))
    struct.pack_into('<32s', hdr, 48, hashlib.sha256(tables).digest())
    p = 80
    for d in descs:
        struct.pack_into(DESC_FMT, hdr, p, *d); p += 12
    hdr[12:44] = b'\0' * 32
    struct.pack_into('<32s', hdr, 12, hashlib.sha256(bytes(hdr)).digest())
    blob = bytes(hdr) + tables
    assert len(blob) <= g['max_size'], 'metadata does not fit'
    out = bytearray(buf)
    prim = RES + 2 * GSZ
    back = prim + g['max_size'] * g['slots']
    pad = blob + b'\0' * (g['max_size'] - len(blob))
    out[prim:prim + g['max_size']] = pad            # slot 0 primary
    out[back:back + g['max_size']] = pad            # slot 0 backup
    open(out_path, 'wb').write(bytes(out))
    print(f'built {out_path}: system {system_sectors} sectors = A {A["sectors"]}@{A["data"]} + B {extB_sectors}@{b_start}; '
          f'group total {total} sectors ({total*512/1048576:.1f} MiB) of max {a["grps"][gi]["max"]/1048576:.1f} MiB; blob {len(blob)} of {g["max_size"]} bytes')


if __name__ == '__main__':
    if sys.argv[1] == 'dump':
        dump(sys.argv[2])
    elif sys.argv[1] == 'build':
        args = dict(zip(sys.argv[4::2], sys.argv[5::2]))
        build(sys.argv[2], sys.argv[3], int(args['--system-sectors']), int(args['--extent-b-start']))
```

## Appendix B – init rc and helper scripts

`/system/etc/init/zz_dbg.rc`:

```
# SATS mirror (RK3399, vendor Android 10 + Android 13 GSI): diagnostics, hardware-decoder block, touch-to-wake, defaults
on early-init
    mkdir /metadata/dbg 0777 root system
    start dbg_log

on property:logd.ready=true
    start dbg_logcat

# The vendor VPU driver (rkvdec/mpp, kernel 4.19) page-faults the whole kernel on VP9 and renders garbage with the
# Android 13 framework: keep media codecs out. Only the camera provider (webcam MJPEG decode) may open the node.
on boot
    chmod 0600 /dev/mpp_service
    chown cameraserver root /dev/mpp_service

on property:sys.boot_completed=1
    start mirror_setup
    start tw_daemon

service dbg_log /system/bin/sh /system/etc/dbg_log.sh
    user root
    group root system log shell
    seclabel u:r:shell:s0
    oneshot
    disabled

service dbg_logcat /system/bin/logcat -b all -v threadtime -f /metadata/dbg/logcat.txt -r 1024 -n 3
    user root
    group root system log shell
    seclabel u:r:shell:s0
    oneshot
    disabled

service mirror_setup /system/bin/sh /system/etc/mirror_setup.sh
    user root
    group root system shell
    seclabel u:r:shell:s0
    oneshot
    disabled

service tw_daemon /system/bin/sh /system/etc/tw_daemon.sh
    user root
    group root input shell
    seclabel u:r:shell:s0
    disabled
```

`/system/etc/mirror_setup.sh`:

```sh
#!/system/bin/sh
# runs once per boot after boot_completed (idempotent)
chmod 0600 /dev/mpp_service 2>/dev/null
mkdir -p /data/local 2>/dev/null
echo '_ --disable-accelerated-video-decode' > /data/local/chrome-command-line
chmod 0644 /data/local/chrome-command-line
F=/data/local/.mirror_defaults_done
if [ ! -e $F ]; then
  settings put system screen_off_timeout 60000
  settings put global stay_on_while_plugged_in 0
  cmd lock_settings set-disabled true >/dev/null 2>&1
  touch $F
fi
# local tuning hook (editable over adb, no reflash): GPU/CPU frequencies etc.
[ -f /data/local/mirror_local.sh ] && sh /data/local/mirror_local.sh
# stop the boot-time log capture after 10 minutes (avoids constant flash writes)
sleep 600
stop dbg_logcat
```

(The *installed* version is a compressed variant of this without comments, padded to the same file size — see 10.1.)

`/data/local/mirror_local.sh` (example, what we use):

```sh
echo 400000000 > /sys/class/devfreq/ff9a0000.gpu/min_freq
echo 816000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
echo 816000 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq
```

`dbg_log.sh` (short): logs `dmesg`/`getprop` to `/metadata/dbg` for the first ~10 minutes, and has a watchdog: if `sys.boot_completed` is not 1 after 420 s, it saves state and reboots the device — **at most twice in a row**, after which it backs off (an endless reboot loop on a permanent install is worse than a hung system).

## Appendix C – write script (from the running DSU guest)

```sh
#!/system/bin/sh
# STAGE 1 of the permanent Android 13 install: write system extents into super and verify them by hash.
# Order: extent B (free tail) first, then extent A (the old stock system region). LP metadata is written in stage 2.
SUPER=/dev/block/by-name/super
IMG=/data/local/tmp/system_final.img
LOG=/data/local/tmp/flash-stage1.log
exec > $LOG 2>&1
say() { echo "[$(date +%H:%M:%S)] $*"; }
die() { say "ABORT: $*"; echo "STAGE1_FAILED" ; exit 1; }

EXP_IMG=40ad372086fe195334988d7b892a6c3d56ffb75ede22a912e5ae808450aeabd4
EXP_A=8f836b60c3f1fac12e628c816e55c10ab0ea3fec91ee53e91ab240b76dacd3dd
EXP_B=5958c46d7f00501905443740846fef0c049be4370f299b3b181a2caf4a9d7bae
EXP_HEAD_LIVE=1114605a4e2ec83a24666ec799602f106686f4d956e9c0d68c37a512aa8b37e7

say "pre-checks"
[ "$(sha256sum $IMG | cut -d' ' -f1)" = "$EXP_IMG" ] || die "image hash mismatch"
[ "$(dd if=$SUPER bs=4096 count=256 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$EXP_HEAD_LIVE" ] || die "live LP metadata is not what I expected"
[ "$(blockdev --getsize64 $SUPER)" = "3263168512" ] || die "super size unexpected"
say "pre-checks ok"

say "WRITE extent B: image 4K-blocks 229369..608679 -> super 4K-block 366336 (sector 2930688), 379311 blocks"
dd if=$IMG of=$SUPER bs=4096 skip=229369 seek=366336 count=379311 || die "dd B failed"
sync
echo 3 > /proc/sys/vm/drop_caches
H=$(dd if=$SUPER bs=4096 skip=366336 count=379311 2>/dev/null | sha256sum | cut -d' ' -f1)
say "extent B readback: $H"
[ "$H" = "$EXP_B" ] || die "extent B verify FAILED"
say "extent B verified"

say "WRITE extent A: image 4K-blocks 0..229368 -> super 4K-block 256 (sector 2048), 229369 blocks  [stock system is overwritten from here]"
dd if=$IMG of=$SUPER bs=4096 skip=0 seek=256 count=229369 || die "dd A failed"
sync
echo 3 > /proc/sys/vm/drop_caches
H=$(dd if=$SUPER bs=4096 skip=256 count=229369 2>/dev/null | sha256sum | cut -d' ' -f1)
say "extent A readback: $H"
[ "$H" = "$EXP_A" ] || die "extent A verify FAILED"
say "extent A verified"

say "dm-linear mapping test with the NEW layout (what first-stage init will build from the metadata)"
dmctl delete sysnew >/dev/null 2>&1
dmctl create sysnew -ro linear 0 1834952 $SUPER 2048 linear 1834952 3034488 $SUPER 2930688 || die "dmctl create failed"
P=$(dmctl getpath sysnew); say "mapped at $P"
echo 3 > /proc/sys/vm/drop_caches
H=$(sha256sum $P | cut -d' ' -f1)
say "mapped device sha256: $H"
[ "$H" = "$EXP_IMG" ] || { dmctl delete sysnew; die "mapped device hash mismatch"; }
mkdir -p /mnt/sysnew
mount -t ext4 -o ro $P /mnt/sysnew && { say "mounted ro OK:"; ls /mnt/sysnew | tr '\n' ' '; echo; ls /mnt/sysnew/system | head -5 | tr '\n' ' '; echo; grep -E '^ro.build.version.release=' /mnt/sysnew/system/build.prop; umount /mnt/sysnew; } || say "WARN: ro mount test failed"
dmctl delete sysnew
say "STAGE1_OK"
echo STAGE1_OK
```

Metadata was written in a separate short script (`dd` of the first 1 MiB, hash check, `lpdump`).

---

*This report was written after the job was finished. All numbers, hashes and outputs above are taken from the logs of the actual run. The parts marked "not verified" are honestly meant.*
