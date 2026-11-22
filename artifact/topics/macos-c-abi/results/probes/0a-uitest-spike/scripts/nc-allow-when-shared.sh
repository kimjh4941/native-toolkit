#!/bin/zsh
# Inside the VM only: turn off "mute notifications while the screen is shared or mirrored"
# (com.apple.ncprefs dnd_prefs.dndMirrored). XCUITest captures the screen during a test run,
# which macOS 15 treats as screen sharing; with the default (true) banners are muted and the
# Notification Center UI test cannot see them.
/usr/bin/python3 - <<'PY'
import plistlib, os
p = os.path.expanduser("~/Library/Preferences/com.apple.ncprefs.plist")
d = plistlib.load(open(p, "rb"))
dp = plistlib.loads(d["dnd_prefs"]); dp["dndMirrored"] = False
d["dnd_prefs"] = plistlib.dumps(dp, fmt=plistlib.FMT_BINARY)
plistlib.dump(d, open(p, "wb"), fmt=plistlib.FMT_BINARY)
print(plistlib.loads(plistlib.load(open(p, "rb"))["dnd_prefs"]))
PY
killall cfprefsd usernoted NotificationCenter 2>/dev/null
