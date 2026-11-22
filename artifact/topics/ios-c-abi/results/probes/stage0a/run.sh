#!/bin/zsh
# usage: run.sh <udid> <label> <only-testing...>
S=${STAGE0A_WORK:?set STAGE0A_WORK to a work directory}
udid=$1; label=$2; shift 2
case $udid in
  73A3F720-16B5-45F6-A743-E9D853C92424|E6446C0D-63C7-4C9D-9849-5CFD7566050D) ;;
  *) echo "refusing non-listed udid"; exit 2;;
esac
args=()
for t in "$@"; do args+=("-only-testing:IosLibraryExampleUITests/$t"); done
ts=$(date +%H%M%S)
log=$S/logs/$label-$ts.log
rb=$S/logs/$label-$ts.xcresult
start=$(date +%s)
xcodebuild test-without-building -xctestrun $S/dd/Build/Products/IosLibraryExample_IosLibraryExample_iphonesimulator26.2-arm64.xctestrun \
  -destination "platform=iOS Simulator,id=$udid" -resultBundlePath $rb "${args[@]}" > $log 2>&1
rc=$?
end=$(date +%s)
echo "== $label rc=$rc elapsed=$((end-start))s log=$log"
grep -E "^Test Case .*(passed|failed|skipped)|error: -\[|\[PROBE\]" $log | grep -v PROBE-DUMP | sed 's/^/  /'
