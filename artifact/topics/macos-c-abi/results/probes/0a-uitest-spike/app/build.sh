#!/bin/zsh
# Build the probe app (ad-hoc signed) from main.swift + Info.plist in this folder. Run inside the VM.
#   build.sh            -> ~/ntk/probe/NtkProbe0a.app    (dev.ntkprobe.notif0a, not sandboxed)
#   SANDBOX=1 build.sh  -> ~/ntk/probe/NtkProbe0aSbx.app (dev.ntkprobe.sbx0a, App Sandbox + user-selected files;
#                          its log is in ~/Library/Containers/dev.ntkprobe.sbx0a/Data/ntk/probe-events.log)
set -e
cd "$(dirname "$0")"
OUT=$HOME/ntk/probe
NAME=NtkProbe0a; BID=dev.ntkprobe.notif0a
[[ -n "$SANDBOX" ]] && { NAME=NtkProbe0aSbx; BID=dev.ntkprobe.sbx0a; }
APP=$OUT/$NAME.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BID" -c "Set :CFBundleExecutable $NAME" -c "Set :CFBundleName $NAME" "$APP/Contents/Info.plist"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos15.0 main.swift -o "$APP/Contents/MacOS/$NAME"
if [[ -n "$SANDBOX" ]]; then
  cat > /tmp/ntk-sbx.entitlements <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
</dict></plist>
P
  codesign --force --sign - --entitlements /tmp/ntk-sbx.entitlements "$APP"
else
  codesign --force --sign - "$APP"
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo built "$APP" "$BID"
