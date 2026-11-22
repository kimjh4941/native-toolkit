#!/bin/zsh
# Inside the VM only: drop the notification settings of the given bundle ids from com.apple.ncprefs
# and restart the notification daemons, so the next requestAuthorization asks again.
# Quit the apps first. dnd_prefs is not touched (see nc-allow-when-shared.sh).
# usage: ncreset.sh <bundle id>...
P=~/Library/Preferences/com.apple.ncprefs.plist
/usr/bin/python3 - "$P" "$@" <<'PY'
import plistlib, subprocess, sys
p = sys.argv[1]; ids = set(sys.argv[2:])
d = plistlib.load(open(p, 'rb'))
before = len(d.get('apps', []))
d['apps'] = [a for a in d.get('apps', []) if a.get('bundle-id') not in ids]
plistlib.dump(d, open(p, 'wb'), fmt=plistlib.FMT_BINARY)
print('apps', before, '->', len(d['apps']))
PY
killall cfprefsd usernoted NotificationCenter 2>/dev/null
sleep 2
defaults read com.apple.ncprefs apps | grep -c "bundle-id"
