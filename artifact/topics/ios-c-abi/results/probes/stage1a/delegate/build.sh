#!/bin/zsh
# Builds DelegateProbe.app (no scene) and DelegateProbeScene.app (scene manifest) for the
# simulator into $STAGE1A_WORK and installs both on the simulator <UDID>.
# Usage: STAGE1A_WORK=<scratch dir> build.sh <UDID>
set -euo pipefail
here=${0:A:h}
udid=${1:?simulator UDID}
work=${STAGE1A_WORK:?set STAGE1A_WORK}
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
for variant in plain scene; do
  app=$work/DelegateProbe-$variant.app
  rm -rf $app && mkdir -p $app
  xcrun swiftc -sdk $sdk -target arm64-apple-ios18.0-simulator -swift-version 6 -module-name DelegateProbe \
    -Onone -g -o $app/DelegateProbe $here/main.swift $here/ForwardingDelegate.swift $here/Install.swift
  if [[ $variant == scene ]]; then cp $here/Info-scene.plist $app/Info.plist; else cp $here/Info.plist $app/Info.plist; fi
  codesign -s - --force $app >/dev/null
  xcrun simctl install $udid $app
done
echo "installed on $udid"
