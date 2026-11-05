# Volume button on a mirror without hardware keys (Android 13 taskbar)

The stock Android 10 had volume buttons in the navigation bar. The mirror has no physical buttons, and Android 13 (AOSP GSI) has no such buttons, so they have to be put back some other way.

## What we found

- With the panel at density 180 the smallest width is 960 dp (>= 600 dp), so **Launcher3 draws its own persistent taskbar** (hotseat apps + back/home/recents) instead of SystemUI's navigation bar. You can see it as a `Taskbar` window in `dumpsys window windows`.
- Because of that, the old `settings put secure sysui_nav_bar "...key(25)..."` trick (extra keys in SystemUI's navigation bar) **does not apply**: the taskbar has a fixed set of buttons.
- **Hotseat items are shown in the taskbar.** So a shortcut in the hotseat is an always-visible button.
- Android has a system volume panel (Settings Panel): the action `android.settings.panel.action.VOLUME`, handled by `com.android.settings/.panel.SettingsPanelActivity`. It shows sliders for media, calls, ring/notification and alarm, plus a link to the sound settings.

## What we did (result: one "Volum" button, left side of the taskbar)

A legacy intent shortcut with its own icon blob was inserted into the launcher's SQLite database (`favorites` table, `container = -101` = hotseat, `itemType = 1`), pointing at the volume panel:

```
#Intent;action=android.settings.panel.action.VOLUME;component=com.android.settings/.panel.SettingsPanelActivity;end
```

Steps (all files are in `device/launcher/` and `logo/`-style own artwork):

1. Draw the icon (`make_volume_icon.ps1`, 192x192 PNG, white speaker on a blue rounded square).
2. Stop the launcher and copy its database (`launcher_db_pull.sh`), `adb pull` it.
3. `add_hotseat_shortcut.py <db> <icon.png> "Volum" "<intent>"` finds a free hotseat rank, inserts the row, and keeps a `.before_shortcut` backup.
4. `adb push` the edited file as `<db>.new`, run `launcher_db_push.sh` (restores owner/mode, removes stale journal files, restarts the launcher).

Tested: the icon shows at the left of the taskbar and a tap opens the panel (also on top of a fullscreen web page).

### When Fully Kiosk Browser is on top

Fully hides the system bars by default, which hides the taskbar and the button. Its preference `showNavigationBar` ("Show Navigation Bar") turns the bar back on; `device/fully_show_navbar.sh` changes only that one value (Fully stopped, restarted afterwards). Kiosk mode itself can stay off.

## Limits and notes

- It is **one button opening a panel**, not separate volume up/down keys. Real +/- buttons would need a tiny app (two transparent activities calling `AudioManager.adjustStreamVolume(..., FLAG_SHOW_UI)`); we did not build one because no JDK was installed on the machine used.
- The hotseat has a limited number of slots (6 here, 4 in use). Check `ls /data/data/com.android.launcher3/databases/` for your grid's database name and adjust `launcher_db_*.sh`.
- Editing a launcher database is easy to undo (restore the `.before_shortcut` copy), but do it with the launcher stopped.
- Correction to the main report: disabling `com.android.quicksearchbox` did **not** remove the launcher's search box. After a launcher restart an empty "Søk" placeholder box is still shown at the top of the home screen. (Not solved; the launcher's own feature flag for the on-screen search box would be the thing to try.)

## Kort på norsk

Android 10 hadde volumknapper i navigasjonslinjen. På Android 13 med stor skjerm tegner Launcher3 en egen oppgavelinje, og den kan ikke få ekstra taster. Løsningen er en snarvei i launcherens hotseat som åpner systemets volumpanel (`android.settings.panel.action.VOLUME`). Den ligger i oppgavelinjen til venstre. I Fully Kiosk må «Show Navigation Bar» slås på for at oppgavelinjen skal vises over dashbordet. Det er én knapp som åpner et panel, ikke egne + og −.
