#!/usr/bin/env python3
"""Turn on the Home Assistant Companion app's "persistent connection" (local push)
by editing a COPY of its Room database.

Why: on a kiosk without a Google/FCM setup, `notify.mobile_app_<device>` with
`command_screen_on` only works while the app holds a websocket to HA. HA answers
"not connected to local push notifications" otherwise. The app keeps this setting
in table `settings` (one row per HA server, id = servers.id). With no row it
defaults to "never".

Usage (run on the PC, with the app force-stopped on the device):

    adb shell am force-stop io.homeassistant.companion.android
    adb pull /data/data/io.homeassistant.companion.android/databases/HomeAssistantDB work/HomeAssistantDB
    python3 -I tools/companion_enable_local_push.py work/HomeAssistantDB
    adb push work/HomeAssistantDB /data/local/tmp/HomeAssistantDB.new
    # on the device, as root: copy over the original, delete -wal/-shm, restore owner,
    # mode (600) and SELinux label (restorecon), then start the app again.

The original is copied to <db>.orig first. The database contains HA access tokens: keep
it (and the copy) out of version control and out of backups you share.
"""
import shutil
import sqlite3
import sys


def main(path: str) -> int:
    shutil.copy2(path, path + ".orig")
    con = sqlite3.connect(path)
    con.execute("pragma wal_checkpoint(TRUNCATE)")
    ids = [r[0] for r in con.execute("select id from servers")]
    if not ids:
        print("no servers row: sign the app in to HA first")
        return 1
    con.execute("delete from settings")
    for sid in ids:
        con.execute(
            "insert into settings (id, websocket_setting, sensor_update_frequency) "
            "values (?, 'ALWAYS', 'NORMAL')",
            (sid,),
        )
    con.commit()
    con.execute("pragma wal_checkpoint(TRUNCATE)")
    print("settings now:", con.execute("select * from settings").fetchall())
    print("integrity   :", con.execute("pragma integrity_check").fetchone()[0])
    con.close()
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
