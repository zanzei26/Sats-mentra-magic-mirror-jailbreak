# Running the mirror as a proper Home Assistant wall panel

The goal of this part of the project: after the lock is gone and Android 13 runs (see the main report), make the mirror **work well as a Home Assistant (HA) wall panel**: a dashboard that is smooth, a camera and a microphone that Assist can use, a "turn the mirror off" button that really turns the screen off, a doorbell notice that wakes it, and a connection that survives reboots.

This page is the summary and index. The doorbell, camera-app and Cast details are in [doorbell-camera-performance.md](doorbell-camera-performance.md).

Setup on the mirror: Android 13 GSI on the Android 10 vendor, **Fully Kiosk Browser** (System WebView 109) showing an HA dashboard, the **HA Companion app** (notifications/commands, Assist), the USB webcam (`RGB Camera`, camera and the only working microphone). Entity names, dashboard paths and ids below are from one installation; replace them with your own. Measurements are from one unit and one run each unless a number says otherwise.

| Problem | Cause | Fix | Where |
|---|---|---|---|
| Camera app hangs | External camera HAL crashes on still sizes whose height is not a multiple of 16 | Pick `2048x1536` | [doorbell doc, section 1](doorbell-camera-performance.md) |
| Camera picture green | MJPEG decode uses the same VPU node as video decode, which is blocked | `cameraserver` owns `/dev/mpp_service` | main report |
| Assist hears silence | Dynamic USB audio policy makes Android ask the webcam for 24-bit **mono**, which it does not have | Explicit 16-bit 48 kHz profile, bind-mounted over the vendor file | section 2 below |
| Companion is no longer the assistant | `am force-stop` of the Companion clears the assistant settings | Never force-stop it; the boot script restores the setting if empty | section 2 |
| Dashboard choppy | Screensaver canvas, drawing page and 3D house are CPU/JavaScript bound, not GPU bound | Four HA dashboard modules (the 3D one keeps every 3D feature switched on) | section 3 |
| Clock/calendar/weather freeze after changing view | Timers stopped on disconnect, not restarted | Patch in the same module as the screen-off fix | section 3 |
| "Switch mirror off" only paints the page black | Fully's JavaScript interface needs Fully PLUS | HA sends the Android sleep key over adb | section 4 |
| Wi-Fi adb disappears at reboot | It was only a runtime setting | `persist.adb.tcp.port`, re-asserted at every boot | section 1 |
| Doorbell | Wake the screen from HA and show a notice | Companion `command_screen_on` + overlay module | [doorbell doc, section 3](doorbell-camera-performance.md) |
| Cast speakers not found | No Play services | Control them from HA | [doorbell doc, section 5](doorbell-camera-performance.md) |

## 1. Keep adb over Wi-Fi alive

The USB cable is not always connected. Wireless debugging (random port) is not enough and adb over TCP set with `setprop service.adb.tcp.port` only lasts until the next reboot. `device/data-local/mirror_local.sh` sets `persist.adb.tcp.port=5555` and restarts `adbd` once if `service.adb.tcp.port` is not 5555, at every boot. Confirmed with a real reboot: adbd came back on port 5555 by itself and the HA integration reconnected (Fully also starts by itself, in the foreground). Always run `adb connect <ip>:5555` before commands; a duplicate transport for the same serial can show "offline" (`adb disconnect`, `adb kill-server`, connect again).

Security: `ro.adb.secure=0` means anyone on the network has root. Home Assistant can also hold a connection (section 4). Do not do this on a network you do not control.

## 2. Camera and microphone for the Companion app / Assist

### Camera

Camera app fix and still-size table: [doorbell doc, section 1](doorbell-camera-performance.md). The USB webcam is the only camera and its microphone is the only microphone. A live WebRTC camera card on the dashboard costs about 250 % CPU (no hardware H.264 decode in the WebView), so use stills or no camera card.

### Microphone: records silence

Symptom, cause and fix are in the [doorbell doc, section 4](doorbell-camera-performance.md): `device/data-local/usb_audio_policy_configuration.xml` (made by `tools/make_usb_audio_policy.py` from the vendor file) is bind-mounted over `/vendor/etc/usb_audio_policy_configuration.xml` at boot by `mirror_local.sh`, followed by one `audioserver` restart. Checked after a reboot: the mount is in place before `audioserver` starts, the Companion's wake-word recorder comes up as `1ch 48000Hz ENCODING_PCM_16BIT` (ALSA `S16_LE`, 1 channel, 48 kHz) and the assistant settings are still set. The ES8323 codec (card 0) records only digital zeros in all 30 mux combinations I tried, so nothing seems wired to it.

Things learned the hard way (all on this unit):

- **Never restart `audioserver` while an app records.** Re-registering the USB device under an active recorder aborts `audioserver` in a crash loop (19 crashes). The boot hook therefore runs once per boot only.
- **Never `am force-stop` the Companion app.** It is the system voice interaction service (`voice_interaction_service` and `assistant` = `io.homeassistant.companion.android/.assist.service.AssistVoiceInteractionService`, `voice_recognition_service` = `.../.assist.service.AssistRecognitionService`); Android clears the first two when it is force-stopped. `mirror_local.sh` puts them back after boot if `voice_interaction_service` is empty.
- The Companion keeps an `AudioRecord` open on the camera microphone after Assist has been used (card 1 stays `RUNNING`). To record something yourself, unbind the service first: `settings put secure voice_interaction_service ""`, record with `tinycap`, then set both settings back.
- The microphone gain control is `Mic Capture Volume` (card 1, index 0..32 = -12..+20 dB, default 12 = 0 dB). **+12 dB made the wake word stop triggering** (probably clipping), so it is back at 0 dB. tinymix 1.1.1 cannot `set` this control (`3 values given`); a 20-line `ctlset` built from the ALSA headers works. It is not persistent.
- `af.tee`, `appops ignore` and similar tricks do not work on this `user` build; `tinycap` on a busy card hangs forever (use `kill -9`).

Measurements (camera microphone, 0 dB, normal room with two small children present; only numbers were kept, recordings were deleted):

- Speech peaks around -22 dBFS in the 300-3400 Hz band (sample peak -5 dBFS): the level is fine.
- Idle noise floor (10th percentile of 85 ms frames) -50 to -56 dBFS below 1 kHz and -60 to -62 dBFS above: the electronics are not noisy. Higher "quiet" levels were the room. A/B tests of screen on/off and CPU/GPU minimum frequencies were confounded by the room noise and proved nothing, so those frequencies were left alone.
- Speech-to-text A/B on the same recording (HA Cloud vs a Google model): Cloud transcribed the test sentence correctly, the other one did not. Keep Cloud STT.
- Every `tinycap` start gives a loud pop in the first second. Skip 1.2 s when analysing.

Assist problems that remain or were only worked around:

1. **Intermittent audio loss.** In some real Assist sessions only about half of the audio arrived (audio time / wall time 0.5-0.57 between voice-start and voice-end, normally 1.00), matching `AudioFlinger: RecordThread: buffer overflow` in the log. Network (5 GHz, 6 ms ping, no gaps) and CPU were fine; the cause was not found. The USB audio HAL uses a fixed 5 ms period (240 frames), the app's reading coroutine runs on normal-priority threads. Nothing was changed for this.
2. **Assist dead until healed.** Once the Assist window closed in the same millisecond that the wake-word listener restarted; the USB audio HAL logged `adev_open_input_stream fail - address card:1 device:0 doesn't match existing profile`, `AudioRecord` returned -38 and the app never retried. Hand fix (worked): with no recorder active, unbind the voice service, re-enumerate the USB device (`echo 0 > /sys/bus/usb/devices/<port>/authorized`, wait, `echo 1`), bind the service again. A self-healing watchdog, `device/data-local/mic_watchdog.sh`, handles this: it follows logcat for `status: -38` / `AudioRecord failed to initialize`, then does a soft heal (unbind and rebind the voice service) and, if no recorder comes back and nothing is recording, re-enumerates the USB camera. Cooldown 90 s, at most 3 heals per 15 minutes, and it never touches USB while a recorder is active (that crash-loops `audioserver`). It also logs `RecordThread: buffer overflow` lines (log only, one per 5 s) to `/data/local/mic_watchdog.log`, which gives timestamps for the audio loss in item 1. Tested by injecting the log lines with `log -p e -t AudioRecord ...`: with a recorder active it does nothing, with the voice service unbound it rebinds and the recorder is back after 13 s. The hard heal (USB re-enumeration) was only done by hand, not through the watchdog. **It is hooked into the boot script**: `/data/local/mirror_local.sh` starts it 90 s after `sys.boot_completed` (the assistant setting is restored 45 s after boot, so the two do not overlap). The hook was added only after the owner explicitly approved it: the permission system of the coding assistant used here had first refused to add a persistent boot hook on its own. The one-instance check in the script copes with the pid file surviving a reboot: the old pid only counts if it is not our own pid and its command line is this script. A second instance exits at once. Confirmed with a reboot (2026-11-05 22:30): the old pid file from before the reboot was still there, did not block the start, and the log showed `watchdog started` about 90 s after boot completed, with one watchdog running, the microphone policy mounted, the assistant setting restored and the Companion's wake-word recorder active. A backup of the previous boot script was left on the device as `/data/local/mirror_local.sh.bak-20261105`.
3. **Slow answers.** After the user stops speaking, most of the time was TTS: `tts.google_ai_tts` took 7-8 s until audio started, HA Cloud TTS (Norwegian neural voice) about 1 s. A cloned pipeline with Cloud TTS exists; the Companion's Assist window has to be switched to it by hand. The Claude conversation step takes 3.5-5 s.
4. **Wake word.** The Companion loads on-device microWakeWord models only from its APK assets (`assets/wakeword/*.json` + `*.tflite`, the ESPHome manifest format); there is no setting for a custom model. A custom phrase would need training a model and patching the APK in place (same-size overwrite; lost on update). Not done.

## 3. A smooth dashboard

**The GPU is not the limit.** Mali-T860 r18p0 is used (GL-accelerated WebView, hardware composition); GPU time per frame was 5-12 ms. The jank was JavaScript/draw-call work on the browser main thread and CPU load (all interrupts land on cpu0, a Cortex-A53 at 1.4 GHz). There is no browser or WebView flag that makes it faster.

How to measure without guessing (scripts in `tools/webview-profile/`): `dumpsys gfxinfo <pkg>` for frame stats, and `dumpsys SurfaceFlinger --latency <layer>` for per-frame present times (Fully's layer is `de.ozerov.fully/de.ozerov.fully.FullyActivity#N`, Chrome's content layer `com.chrome.beta/ChromeChildSurface#N`; the number changes after the screen wakes). Count only frames after the test start. Script the touches (`input swipe`) only when nobody is using the mirror.

### Fixes (HA dashboard modules in `device/ha/`)

All four are inline dashboard resources (type `module`), apply only on an Android user agent and the mirror's dashboard path, fall back to the original code on error, and are removed by deleting the resource and reloading Fully. Custom elements read `connectedCallback` and the other lifecycle callbacks once, at `customElements.define()`; patching them on the prototype afterwards does nothing. Plain methods and accessors (`hass`, `_start`, `_bygg`, `_tegneoppsett`, `_tikk`) are looked up at call time and can be patched.

- `speil-orb-lett.js`: the screensaver is a full-screen canvas "neural orb" with about 225 `stroke()` calls, 150 arcs and up to 90 `shadowBlur` dots per frame at 30 fps. The module draws the same picture with about 20 draw calls (strokes batched by strength, a pre-rendered glow sprite instead of `shadowBlur`, canvas at 0.75x). Idle, 20 s: p50 frame time 30 -> 22 ms, p99 77-85 -> 34 ms, SoC load 49-65 % -> 38.5 %. A 30 fps cap with a threshold of 33 ms rejected vsync pairs 32.9 ms apart, which gave a 50 ms frame every fifth frame; the threshold is now 29 (frames over 34 ms: 18.2 % -> 13.4 %).
- `speil-barn-lett.js`: the kids' drawing page redrew **all** strokes on every `pointermove` (1,844,160 `stroke()` calls for 1,920 moves; 1,920 after the fix), on top of an animated 400 % gradient and `backdrop-filter: blur` on every panel. The module draws only the new segment (a capture-phase listener stops the original handler), uses a static pastel background and no blur. Stored points are identical; 0.04 % of the pixels differ (stroke start dots). Test with 40 automatic strokes: 0.62 % janky frames, p99 48 ms. The page's 12 floating emojis and the pulsing star kept the compositor at 60 fps on an otherwise still page (SoC 29.6 % busy at rest), so they are now paused after 20 s without touch and start again on the next touch (at rest: 0 frames presented, 12.9 % busy; one stroke brings the animations back). The family card's drawing is left alone: it redraws all strokes on every move too, but with one path per stroke on a small canvas, which is cheap next to the per-segment redraw on the full-screen kids' page.
- `speil-kort-fiks.js`: (1) the main card's clock, calendar and weather froze after Speil -> another view -> Speil (the disconnect callback clears the intervals but not their ids; the connect callback only restarts the clock when the id is empty). The `hass` setter, which HA calls several times per second, now restarts the three timers when the clock has not ticked for 3 s. (2) "Switch mirror off", see section 4.
- `speil-3d-lett.js`: lets the 3D house card keep **all** its features switched on (see the next subsection). (1) `forceSinglePass` on `Material.prototype`, so Three.js stops drawing every transparent, double-sided material twice per frame. (2) While the screen is touched (and 0.6 s after) the newest `hass` for the 3D card is held back and delivered afterwards (at most 3 s), because every Home Assistant state change otherwise runs the card's whole update in the middle of an orbit.

### The 3D house card (NeonPlan 3D)

The 3D view is bound by the JavaScript main thread (one Cortex-A72 at about 100 %, GPU 5-6 ms per frame), not by the GPU. `quality: auto` picks the low level only when `deviceMemory <= 3`, `hardwareConcurrency <= 4` or a Silk/Fire user agent, so a 6-core 4 GB RK3399 gets the full level (MSAA, pixel ratio 1.125, continuous render loop). Orbit-drag test (idle 8 s + 40 swipes, about 23 s):

| Card options | Frames | Janky | p99 | Idle CPU |
|---|---|---|---|---|
| `quality: low` | 787 | 60 % | 48 ms | 20 % |
| + `flows, holograms, pets, ghost, walk: false` | 779 | 58 % | - | 10 % |
| + `plain: true`, `roof: false` | 860 | 51 % | - | - |
| + `room_names: false`, `markers: none` | 962 | 37.5 % | 36 ms | - |
| *earlier choice, replaced by the module below:* the `false` options above + `plain: true`, `roof: false`, `room_names: false`, `markers: room` | 934 | 41.5 % | 34 ms | - |

The card's own overlay (`stats: true`, do not leave it on) said 13 fps at the automatic full level (slowest frame 200 ms, 91 draw calls, 64,238 triangles) and 15 fps with the options above (slowest 100 ms, 49 draw calls, 38,900 triangles). I reported this upstream: bug issue [Mastershort/neonplan3d#952](https://github.com/Mastershort/neonplan3d/issues/952) and Ideas discussion [#953](https://github.com/Mastershort/neonplan3d/discussions/953) (the draft is in [neonplan3d-performance-report-draft.md](neonplan3d-performance-report-draft.md)). Not answered when this was written.

**All features back on (2026-11-05, `speil-3d-lett.js`).** The owner wanted the whole house again (`plain` is "floor plan only, no furniture", plus roof, room names, markers `important`, flows, holograms, pets, ghost, walk) without choppier orbiting. The card is now `type: custom:neonplan3d-card` with only `quality: low` and the usual layout options. What the profile showed (CPU profile and timeline trace over Chrome's DevTools protocol; Fully's `webviewDebugging` preference was switched on for the session and off again; the helper scripts are in `tools/webview-profile/`):

- **Three.js draws every transparent, double-sided material twice per frame** (back faces, then front faces) and sets `material.needsUpdate = true` both times. With everything on that was 20-33 materials, about 22,000 `needsUpdate` in 36 s, and every one made Three recompute the shader parameters and the program key (`getParameters`, `getProgramCacheKey`, `getProgram`: about 10 % of the main thread). `forceSinglePass = true` removes it. Screen captures of the house view and the floor view with and without it were visually identical.
- **Every Home Assistant state change** (about 6 per second here: power meters, the router's CPU and memory sensors) arrives as one websocket task of 10-30 ms in which the card also runs its update (`syncDevices` and more). Holding back the card's `hass` while touching shortens the tail a little (p99 of the animation-frame callback 35.6 -> 23.7 ms, one trace each). An experiment that also queued Home Assistant's own websocket messages while touching and replayed them afterwards gave no measurable gain and was not kept.
- Per frame the scene is already merged into about 58 draw calls (3 floors times about 10 meshes, 99 meshes and 57k triangles in all). A micro-benchmark that hid parts of the scene put all floor groups at 6-7 ms of the 9-10 ms of `render()`, roughly 0.1-0.15 ms per draw call, and no single feature dominates (glow, light spill and lamps about 1 ms together, walls about 1 ms, frames, glass and blinds about 0.3 ms). So hiding one feature while orbiting would not buy much.
- What is left is outside the card's render: a style recalculation of about 3 ms per frame for the three floor labels (0.6 ms each), Home Assistant's own message handling, and a 435 KB `config/entity_registry/list_for_display` answer about every 40 s that blocks the main thread for about 127 ms.

Orbit test (about 21 s of drags, SurfaceFlinger present intervals of Fully's layer, same day):

| Card | Frames | Intervals over 34 ms | Over 50 ms | Idle CPU |
|---|---|---|---|---|
| Earlier reduced options (`plain`, no roof, no room names, extras off) | 830-844 | 10-14 % | 4.5 % | 10 % |
| Everything on, without the module | 695-698 | 23 % | 7-9 % | 16-21 % |
| Everything on, with the module (6 runs) | 774-793 (one run 656) | 15-17 % | 4.6-6.4 % | 15 % |

So the full house now orbits almost like the reduced one did (6-8 % fewer frames, a few points more intervals over 34 ms); the animated extras keep the idle load at about 15 % instead of 10 %, which is what they cost. The test drives the screen with `input swipe`, so absolute numbers carry the injection's own rhythm; compare runs only with each other.

**NeonPlan 3.0.1 (installed 2026-11-06).** The owner answered issue #952: 3.0.1 lets `quality: auto` time the frames while the view is turned and pick the tablet level by itself when half of them take over 50 ms; a `quality` set by hand still wins, so this setup is unaffected (`slowWatch` is `null` with `quality: low`). The split-up of the state sync is not in 3.0.1. After the update (and the Home Assistant restart the release notes ask for) the module still applies unchanged on the mirror: the card and the viewer chunk are the new ones, the `hass` throttle and the `forceSinglePass` accessor are installed, all 33 transparent double-sided materials are single-pass, and the draw calls and triangles are the same as before (68-75 calls, about 43,000 triangles). `render()` per frame was not slower (9.3 and 7.8 ms in the micro-benchmark against 10.6 and 9.0 ms on 3.0.0). The orbit test that morning was worse (21.9 and 23.8 % of intervals over 34 ms), but Home Assistant was much busier than the day before: about 10 state events per second instead of 6 (a living-room media player alone changed twice a second) and a 435 KB entity-registry answer about every 10 s instead of every 40 s. So that run says little about 3.0.1 itself. A repeat the same day, with about 8 events per second (the media player quiet, the registry answer every 15 s or so), gave 19.1 and 20.2 % of intervals over 34 ms and 6.3 and 6.0 % over 50 ms (3.0.0 with the module: 15-17 % and 4.6-6.4 %). A timeline trace at the same message load had animation-frame callbacks at p50 10.9, p90 20.4 and p99 36.9 ms (3.0.0: 9.9, 18.5, 23.7), but a 39 s CPU profile gave the same share for the 3D render path as on 3.0.0 (`render` 29.9 % against 29.7 %, the program setup 9.3 % against 11.9 %, `updateLabels` 2.9 % against 2.6 %). So 3.0.1 is at most a few points worse end to end, the code the module patches costs the same, and what is left sits in the tail, where Home Assistant's own load is the likelier cause.

### Things that did not help

- **Chrome Beta 158 instead of Fully/WebView 109** (same dashboards, frames from SurfaceFlinger): the orb is identical (p50 33 ms, about 19 % over 34 ms), the 3D house is **worse** in Chrome (26.3 % over 34 ms against 9.7 %, CPU 79 % against 55 %). Chrome also adds a toolbar and has no kiosk mode without Play services.
- **WebView/Chrome command-line flags:** `/data/local/tmp/webview-command-line` is not honored; Chromium reads it only on eng/userdebug builds and this GSI reports `ro.build.type=user`.
- Raising CPU/GPU minimum frequencies or changing the governor: nothing measurable (reverted).
- A **Settings app loop** (35 % CPU after the user has opened Settings; `am force-stop com.android.settings` stops it) is worth knowing about.

### Linux instead of Android? (checked, not done)

The hardware (RK3399, Mali-T860) is not that powerful, and the browser, not Android, is the bottleneck, so Linux would not obviously help. Read-only inspection: the bootloader is unlocked, no A/B, vendor Rockchip U-Boot; eMMC has a valid idbloader, and the BootROM tries SPI, then eMMC, then SD, so an SD image is only used if eMMC is unbootable or maskrom is forced. The device tree enables an SD controller, but whether a physical slot exists is unknown. The vendor kernel 4.19.111 lacks `FHANDLE`, `AUTOFS`, PID/USER/UTS namespaces and `SYSVIPC`, so systemd would not run (a non-systemd init, Chromium `--no-sandbox`, or a self-built kernel). Linux GPU userspace for Midgard r18p0 exists (armbian/libmali-rockchip). The only reversible-ish trial would be a Linux boot image written to the `recovery` partition and started with `adb reboot recovery`; it was not tried.

## 4. "Switch mirror off" that really switches the screen off

The dashboard card only tries Fully's JavaScript interface (`window.fully.turnScreenOff`, needs Fully PLUS and the interface switched on) and otherwise paints the page black with the backlight on.

What works (see [`device/ha/screen-scripts.yaml`](../device/ha/screen-scripts.yaml)):

1. **Instant, over adb.** Add the mirror to HA with the Android Debug Bridge (`androidtv`) integration (host = the mirror, port 5555; set the screenshot interval to 0 so HA does not store pictures of the mirror, and switch off the app list). The script calls `androidtv.adb_command` with `input keyevent 223` (SLEEP): display off within a second. The wake script sends `input keyevent 224` (WAKEUP). The entity's own state is unreliable (it showed "off" with the screen on), so the script only checks that the entity is not unavailable.
2. **Fallback, via the Companion app.** The notification command `command_screen_off_timeout` (milliseconds) sets the system screen timeout. It needs the Companion to have "modify system settings" (`appops set io.homeassistant.companion.android WRITE_SETTINGS allow`). The shortest timeout Android accepts is 10 s, and it counts from the **last touch**, so a user who taps the black page while waiting restarts the countdown (a first user test failed exactly like this: "black picture but the screen is on"). The card module therefore swallows taps for the first 14 s, restarts the script (`mode: restart`) and puts the timeout back to 5 minutes afterwards.
3. **Waking.** A touch on the sleeping screen wakes it (the small evdev touch-to-wake service from the main report). `command_screen_on` and `KEYCODE_WAKEUP` also work; injected `input tap` does not wake. When the page becomes visible again the card drops the black page by itself.

Tested on the mirror: button -> display off within 1 s; wake script -> the dashboard is shown again.

## Not done / open

- A custom wake word is not made. (The Assist watchdog's boot start is confirmed, section 2.)
- Intermittent audio loss in the Companion's recording path (section 2); the watchdog now logs the overflow times.
- The 3D house now has every feature on (section 3). What is left over: it orbits a little worse than the reduced setup did (6-8 % fewer frames), and the animated extras keep the idle load at about 15 %. Further ideas, none tried: a CSS `contain`/`will-change` tweak for the floor labels (style recalculation about 3 ms per frame), fewer Home Assistant state events (the router CPU/memory sensors and the power meters update every 1-3 s; every event costs a 10-30 ms main-thread task on every dashboard), pinning the render threads to the big cores (`schedtune`, `taskset`), moving interrupts off cpu0.
- The module patches a third-party bundle at run time (a `Material.prototype` accessor and the card's `hass` setter). A NeonPlan update that renames either simply makes the patch do nothing; the effect is easy to re-check with the tools in `tools/webview-profile/`.
- The upstream NeonPlan reports are open.
