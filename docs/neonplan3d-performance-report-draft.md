# Report to the NeonPlan 3D maintainer (posted)

Posted on 2026-11-05 as bug issue [Mastershort/neonplan3d#952](https://github.com/Mastershort/neonplan3d/issues/952) and Ideas discussion [#953](https://github.com/Mastershort/neonplan3d/discussions/953). The text below is the draft they were made from. Context: [home-assistant-wall-panel.md](home-assistant-wall-panel.md).

Based on what the repository asks for (https://github.com/Mastershort/neonplan3d, read 2026-11-05):

- **Issues are for bugs only**, with a form (`bug_report.yml`, blank issues are off). Wishes posted as issues are moved to **Discussions -> Ideas**. Questions go to Discussions -> Q&A or Discord.
- English or German is fine. Do not post private data (addresses, IP addresses, real names).
- The form asks for: tick "Bug, not a wish", NeonPlan 3D version, Home Assistant version, which part (multi-select), "What happens?", device (optional), screenshots/console/log (optional).
- Numbers help: in issue #885 ("3D View FPS drops with one active light effect") the maintainer wrote that the frame numbers from the on-screen FPS readout "made it easy to find" and fixed it the same day (2.1.0). In #752 he asked for device, app vs browser, which quality level (Auto/Tablet/High) and a short video.
- The maintainer has extended "Auto" for specific devices before (changelog 1.26.0: "'Auto' now also picks the Tablet level on the Fire HD 10 Plus"), so a device report is in the spirit of the project.
- There is already an idea close to ours: Discussions #809 "Static 'wall tablet' mode: export a floor as pictures once, show it without WebGL" (0 comments).

So: **one bug issue** (the device is classified wrongly and is slow) and **one Ideas post** (what would help). Post them from your own GitHub account if you want to send them.

---

## 1. Issue (use the "Bug report" form)

- Bug, not a wish: tick
- NeonPlan 3D version: `3.0.0`
- Home Assistant version: `2026.11.0`
- Which part: `3D view`, `Dashboard card`
- Device: `Tablet (wall tablet / Wandtablet)`

**Title:** 3D view: Auto picks the full level on a slow 6-core wall tablet (13 fps, sync ~95 ms); Tablet level is only reached by hand

**What happens?**

Wall mirror/tablet: Rockchip RK3399 (2x Cortex-A72 1.8 GHz + 4x Cortex-A53 1.4 GHz), Mali-T860, 3.9 GB RAM, Android 13, Fully Kiosk Browser, Android System WebView 109, 1080x1920 portrait. Card: `type: custom:neonplan3d-card`, `fill: true`, `theme: neon`, `markers: important`, `room_panel: true`, whole-house view, three floors, Halloween/pets packs installed.

1. Open the 3D view with `quality: auto` (default).
2. The on-screen FPS readout says "full level" (fullt nivaa), pixel ratio 1.13. Orbit the model by dragging.
3. Result: 13 fps, slowest frame 200 ms, 91 draw calls, 64,238 triangles, sync 94.7 ms. Idle: 0 fps, 101 draw calls, 65,644 triangles, sync 37.2 ms.

From the code, `auto` becomes the Tablet level only when `deviceMemory <= 3`, `hardwareConcurrency <= 4`, or the user agent is Silk/Fire. This device reports 6 cores and 4 GB, so it is treated as strong, but the CPU is weak: the browser main thread sits at ~100 % of one Cortex-A72 while orbiting (the GPU needs only 5-6 ms per frame).

With `quality: low` set by hand plus `flows: false, holograms: false, pets: false, ghost: false, walk: false, plain: true, roof: false, room_names: false, markers: room` the readout says "nettbrettnivaa, pixel ratio 1", 15 fps, slowest frame 100 ms, 49 draw calls, 38,900 triangles, sync 516.7 ms (idle: 0 fps, 46 draw calls, sync 157 ms). In my own frame counts (40 orbit drags, ~23 s, one run each, so small differences are noise): 787 frames / 60 % janky with `low` only, 934 frames / 41.5 % janky with the settings above.

Two questions: what exactly does "sync" measure, and can it be limited (it is 37-95 ms at the full level and 157-517 ms at the Tablet level here, which would block the main thread for whole frames)? Could "Auto" also use measured frame times instead of only core count and memory?

**Screenshots, browser console or HA log:** (readout text above; no screenshots because they show the floor plan)

---

## 2. Ideas post (Discussions -> Ideas)

**Title:** "Wall tablet" performance preset, and let Auto react to measured frame times

Related: #809 (static wall tablet mode), #885, #752, changelog 1.26.0.

What I measured on a slow wall tablet (details in the issue above): the 3D view is CPU-bound on the browser main thread, not GPU-bound. These card options made the biggest difference in my test (frames in 23 s of orbiting, janky share): all `low` = 787 / 60 %; plus flows/holograms/pets/ghost/walk off = 779 / 58 %; plus `plain: true`, `roof: false` = 860 / 51 %; plus `room_names: false`, `markers: none` = 962 / 37.5 %; with `markers: room` instead = 934 / 41.5 %. Turning off the animated extras mostly lowered the idle load (about 20 % to 10 % CPU at rest).

Ideas:
- One option such as `performance: wall-tablet` that sets the items above.
- Let `auto` fall back to the Tablet level when the median frame time stays above ~24 ms for a few seconds.
- Update marker and room labels less often, or only while the camera moves.
- Stop decor/flow timers when nothing visible changes.
- Document `plain`, `roof`, `room_names`, `markers` (none/room/important/all), `flows`, `holograms`, `pets`, `ghost`, `walk`, `stats` in the card reference (I could not find them in the README or the parts of the manual I read).

Happy to test builds on this device.
