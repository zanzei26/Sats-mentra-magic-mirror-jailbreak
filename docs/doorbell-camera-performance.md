# Doorbell image, camera app and performance on the Android 13 mirror

Notes from running the mirror as a Home Assistant (HA) wall panel (Fully Kiosk Browser showing a dashboard). Entity names and ids below are from one installation; replace them with your own. The overview of the whole wall-panel setup (microphone and Assist, dashboard smoothness, switching the screen off, adb) is in [home-assistant-wall-panel.md](home-assistant-wall-panel.md).

## 1. Camera app freezes after a few seconds

Symptom: the stock camera app shows a live preview, then hangs (usually when the shutter is pressed).

Cause: the external camera HAL (`camera.device@3.4-external`, USB webcam) crashes in libjpeg's `forward_DCT` when the picture height is not a multiple of 16. The webcam's 2592x1944 mode hits this (1944 = 16 x 121.5).

Fix: pick a still size whose height is a multiple of 16. In the camera app's preferences (`/data/data/com.android.camera2/shared_prefs/com.android.camera2_preferences.xml`, key `pref_camera_picturesize_front_key`) we use `2048x1536`.

| Size | Frame rate (this webcam) | Note |
|---|---|---|
| 2592x1944 | crashes | height not a multiple of 16 |
| 2048x1536 | ~21.6 fps | 3 MP, chosen |
| 1600x1200 | ~27.8 fps | 2 MP, smoother |
| 1024x768 | 30 fps | |

The on-screen preview size does not change with this setting; only the saved photo gets smaller.

## 2. Is Android itself laggy?

No. Measured with `dumpsys gfxinfo` and scripted taps:

- The apps on the touch path were only `verify`-compiled on the GSI (interpreted + JIT). `device/dexopt_speed.sh` AOT-compiles them (`cmd package compile -m speed -f <pkg>`), which gives a small but visible gain.
- Raising CPU/GPU minimum frequencies or changing the governor gave nothing measurable and was reverted.
- The remaining lag is the HA web dashboard in the WebView, not Android. Later measurements (screensaver, drawing page, 3D house, Chrome instead of Fully) are in [home-assistant-wall-panel.md](home-assistant-wall-panel.md), section 3.
- A live WebRTC camera card on the dashboard burns ~250 % CPU because the WebView cannot hardware-decode H.264 here (decode error -13). Use a still instead, or no camera card on the mirror.

## 3. A picture of who rang the doorbell

Goal: when the doorbell is pressed, wake the mirror and show a **new picture of that visit**.

### What does not work

- **The camera entity's still.** A WebRTC-only Nest doorbell (`Google Nest Doorbell`, `supported_features: 2`) has no snapshot API. `camera.async_camera_image` returns HA's grey **placeholder image** (a dark 640x480 gradient). It looks like a very dark photo, but it never changes and never shows anything.
- **Nest event images.** `media_source/resolve_media` for `media-source://nest/<device_id>/<nest_event_id>` looks valid, but the picture never arrives: the "Recent Events" list stays empty and HA logs `google_nest_sdm.event_media ... CameraEventImage.GenerateImage is not supported due to camera not supporting RTSP protocol`. The Nest (SDM) API only offers per-event images for RTSP cameras, so a WebRTC-only doorbell cannot give HA a picture of a ring, with or without a subscription.
- **Live WebRTC in the kiosk WebView** (see above), and anything that needs the Nest OAuth secrets outside HA (go2rtc's `nest:` source).

### What works

1. **Wake the display from HA.** The Companion app only receives `command_screen_on` when it holds a websocket to HA ("persistent connection"). The app keeps this in its Room database: table `settings`, one row per HA server with `id = servers.id`, `websocket_setting = 'ALWAYS'`. With no row it defaults to never. `tools/companion_enable_local_push.py` edits a copy of the database. The app has to be force-stopped while the file is swapped (restore owner, mode 600 and the SELinux label), and a stopped app only starts again for a broadcast sent with `--include-stopped-packages`:
   `am broadcast --include-stopped-packages -a android.intent.action.BOOT_COMPLETED -p io.homeassistant.companion.android`.
   Then `notify.mobile_app_<device>` with `message: command_screen_on` wakes the screen in about 2 s. The database holds HA tokens: never commit or share it.
2. **A notice, not a picture.** On a WebRTC-only doorbell there is no picture to show (see above). For an RTSP camera, `media_source/resolve_media` with `media-source://nest/<device_id>/<nest_event_id>` would return an event image (`nest_event_id` is an attribute of the doorbell's `event.*` entity and is new for every ring); that variant was tried and removed from the overlay.
3. **Show it.** `device/ha/doorbell-overlay.js` is a dashboard resource (module) that opens a full-screen overlay (bell, "Noen ringer på", time) on the kiosk dashboard when the doorbell event entity, or a helper `input_button` that the automation presses, carries a timestamp younger than 40 s. Tap to close; it also closes after 45 s.
4. **Automation.** Trigger `event.received` on the doorbell event entity (`event_type: ring`); actions: `notify.mobile_app_<device>` with `command_screen_on` (with `continue_on_error`), then `input_button.press` on the helper.

### Pitfall: do not use bus events for the kiosk

A first version of the overlay subscribed to a custom bus event (`connection.subscribeEvents`). It worked in an admin browser tab but never on the mirror, where HA reported no listener: the kiosk session is a normal (non-admin) user, and non-admin users may not subscribe to arbitrary events. Reading `hass.states` works for everyone. Also do not compare with the previous state: if the kiosk page was loaded while the screen slept, its first observation is already the state *after* the ring and no change is ever seen. The state value of both entities is the ISO time of the ring, so the overlay just checks that it is younger than 40 s.

### Status

Tested with a real doorbell press: HA receives the ring, the automation runs, the Companion app wakes the display (it was asleep) and the overlay opens on the kiosk. The picture itself does not work on a WebRTC-only Nest doorbell (see above). Ideas that are not tried: decode the live H.264 WebRTC stream with Chrome (software decoding) instead of the System WebView, or take a frame server-side with go2rtc's `nest:` source (needs the Nest OAuth credentials, which the owner must enter themselves).

## 4. The microphone records silence (Companion app / Assist)

Symptom: the Home Assistant Companion app has the microphone permission and Android reports an active recording ("not silenced"), but Assist hears nothing. `logcat` fills with `alsa_device_proxy: proxy_open() pcm_is_ready() failed: cannot set hw params: Invalid argument` (20 000+ lines).

Cause: the only working microphone is the USB webcam's (card 1, `USB-Audio - RGB Camera`; `/proc/asound/card1/stream0` lists S16_LE mono 48 kHz, S16_LE stereo 22.05/32/48/96 kHz and **only stereo** for S24_3LE). `/vendor/etc/usb_audio_policy_configuration.xml` leaves the USB input profile fully dynamic, so Android builds a cross product of formats and channel masks and picks 24-bit **mono** at 48 kHz for a mono client. That combination does not exist on the device, the open fails on every attempt, and the app only ever gets zeros. The board's ES8323 codec (card 0) opens fine but records digital silence (RMS 0), so no microphone seems to be wired to it.

Fix: give the USB input mix port and device port an explicit profile (`AUDIO_FORMAT_PCM_16_BIT`, 48000 Hz, mono and stereo) in a copy of the file (`device/data-local/usb_audio_policy_configuration.xml`, generated by `tools/make_usb_audio_policy.py`), bind-mount it over the vendor file and restart `audioserver`. `/vendor` is not modified; the hook is in `device/data-local/mirror_local.sh` and repeats at every boot. After the restart `dumpsys audio` shows the recorder as `dev=1ch 48000Hz ENCODING_PCM_16BIT`, `/proc/asound/card1/pcm0c/sub0/hw_params` says `S16_LE channels: 1 rate: 48000`, and the errors stop.

How to test without an app: build `tinycap` from tinyalsa 1.1.1 (static, `aarch64-linux-gnu-gcc`), push it, and record with `timeout -s INT 4 tinycap /data/local/tmp/x.wav -D 1 -d 0 -c 1 -r 48000 -b 16` (this tinyalsa version has no `-T`). Check levels as numbers (RMS/peak) and delete the file. The camera microphone gave about -24 dBFS RMS in a normal room. Never restart `audioserver` while an app is recording (crash loop) and never force-stop the Companion app (Android then drops it as the assistant); the hook restores the assistant setting if it is empty. More on Assist, gain and measurements: [home-assistant-wall-panel.md](home-assistant-wall-panel.md), section 2.

## 5. Casting from Spotify / Google Home does not find the speakers

The Android 13 AOSP GSI has no Google Play services (`gms`, `gsf`, `vending`). Cast discovery in Spotify and the Google Home app goes through the Cast SDK in Play services, so the speakers never appear, even though the network and mDNS (`mdnsd`) work. What we did instead: control the speakers from HA. A separate dashboard (`jarvis-musikk`) has a Mushroom media-player card per Cast speaker (power, previous/play-pause/next, mute, volume +/-), and a "Musikk" button on the mirror dashboard opens it. Starting Spotify from the mirror would need HA's Spotify integration (OAuth with the owner's own Spotify developer app and account, set up by the owner); without it HA only controls what is already playing. HA's built-in tile features `media-player-playback` rendered nothing here, the Mushroom card works. The alternative, a GApps/microG image, means rebuilding the system image: here `super` is 3.26 GB and the system image is already 98 % full with roughly 200 MB free in total, so it would also need trimming.
