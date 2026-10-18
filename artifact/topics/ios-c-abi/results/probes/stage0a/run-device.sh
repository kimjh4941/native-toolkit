#!/bin/zsh
# usage: run-device.sh <label> <only-testing...>   (physical iPhone XS only)
S=${STAGE0A_WORK:?set STAGE0A_WORK to a work directory}
DEST="platform=iOS,id=${STAGE0A_DEVICE_UDID:?set STAGE0A_DEVICE_UDID to the hardware UDID of the device}"   # the hardware UDID from `devicectl device info details`, not the devicectl identifier
label=$1; shift
args=()
for t in "$@"; do args+=("-only-testing:IosLibraryExampleUITests/$t"); done
ts=$(date +%H%M%S)
log=$S/device/logs/$label-$ts.log
rb=$S/device/logs/$label-$ts.xcresult
start=$(date +%s)
xcodebuild test-without-building -xctestrun $S/dd-device/Build/Products/IosLibraryExample_IosLibraryExample_iphoneos26.2-arm64.xctestrun \
  -destination "$DEST" -resultBundlePath $rb "${args[@]}" > $log 2>&1
rc=$?
end=$(date +%s)
echo "== $label rc=$rc elapsed=$((end-start))s log=$log"
grep -E "^Test Case .*(passed|failed|skipped)|error: -\[|\[PROBE\]" $log | grep -v PROBE-DUMP | sed 's/^/  /'
