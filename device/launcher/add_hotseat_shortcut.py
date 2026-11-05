#!/usr/bin/env python3
"""Add a legacy intent shortcut (with a PNG icon) to the Launcher3 hotseat / taskbar by editing its SQLite database.

Why: on Android 13 GSI with a large screen (smallest width >= 600 dp, e.g. this 1080x1920 panel at density 180) Launcher3 draws a
persistent *taskbar* instead of SystemUI's navigation bar, so the old `sysui_nav_bar` customisation (extra keys) does not apply.
Hotseat items are shown in the taskbar, so a shortcut there is the simplest way to get an always-visible "Volume" button.

Usage (database pulled from the device with the launcher STOPPED, see launcher_db_pull.sh / launcher_db_push.sh):
  add_hotseat_shortcut.py launcher_6_by_5.db icon.png "Volum" "#Intent;action=android.settings.panel.action.VOLUME;component=com.android.settings/.panel.SettingsPanelActivity;end"

The database name depends on the grid (launcher_<cols>_by_<rows>.db). A backup copy <db>.before_shortcut is written first.
"""
import shutil, sqlite3, sys

db, icon_path, title, intent = sys.argv[1:5]
shutil.copy(db, db + '.before_shortcut')
c = sqlite3.connect(db)
icon = open(icon_path, 'rb').read()
used = [r[0] for r in c.execute('SELECT screen FROM favorites WHERE container=-101')]
print('hotseat ranks in use:', sorted(used))
free = [r for r in range(0, 6) if r not in used]
assert free, 'no free hotseat slot (move or remove an icon first)'
if c.execute("SELECT COUNT(*) FROM favorites WHERE title=? AND container=-101", (title,)).fetchone()[0]:
    sys.exit('shortcut with this title already in the hotseat; nothing to do')
rank = free[0]
nid = c.execute('SELECT MAX(_id) FROM favorites').fetchone()[0] + 1
cols = [r[1] for r in c.execute('PRAGMA table_info(favorites)')]
row = dict(_id=nid, title=title, intent=intent, container=-101, screen=rank, cellX=rank, cellY=0, spanX=1, spanY=1,
           itemType=1,                       # ITEM_TYPE_SHORTCUT (legacy shortcut with its own icon blob)
           appWidgetId=-1, iconPackage=None, iconResource=None, icon=icon, appWidgetProvider=None,
           modified=0, restored=0, profileId=0, rank=0, options=0, appWidgetSource=-1)
row = {k: v for k, v in row.items() if k in cols}     # only columns this launcher version has
c.execute('INSERT INTO favorites (%s) VALUES (%s)' % (','.join(row), ','.join('?' * len(row))), list(row.values()))
c.commit()
c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
c.close()
print(f'inserted _id {nid} at hotseat rank {rank}')
