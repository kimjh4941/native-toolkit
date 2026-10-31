#!/bin/zsh
# Runs scenarios against DelegateProbe on the simulator <UDID> with a UI test runner built from a
# scratch copy of ios/ (the repository is not touched), then prints the app's events.log.
# Usage: STAGE1A_WORK=<scratch dir> run.sh <UDID> <plain|scene> <scenario>...
#   (first time: build.sh, then `run.sh <UDID> plain auth` and `run.sh <UDID> scene auth`)
set -euo pipefail
here=${0:A:h}
repo=${here:h:h:h:h:h:h:h}
udid=${1:?UDID}; variant=${2:?plain|scene}; shift 2
work=${STAGE1A_WORK:?set STAGE1A_WORK}
case $udid in
  E6446C0D-63C7-4C9D-9849-5CFD7566050D|3C89774D-8F20-4188-ADB8-4A1747120C31) ;;
  *) echo "refusing: only the two probe simulators are allowed" >&2; exit 2 ;;
esac
bundle=com.jonghyunkim.stage1a.delegateprobe; [[ $variant == scene ]] && bundle=$bundle.scene
src=$work/src
if [[ ! -d $src/ios ]]; then
  mkdir -p $src/ios
  # The UI test folder is a synchronized group: copy it empty so only the probe test is built.
  rsync -a --exclude build --exclude Build --exclude xcuserdata --exclude 'IosLibraryExampleUITests/*' \
    $repo/ios/IosLibrary $repo/ios/IosLibraryExample $repo/ios/IosWorkspace.xcworkspace $src/ios/
fi
cp $here/Stage1aDelegateProbeTests.swift $src/ios/IosLibraryExample/IosLibraryExampleUITests/
if ! xcodebuild build-for-testing -workspace $src/ios/IosWorkspace.xcworkspace -scheme IosLibraryExample \
  -destination "platform=iOS Simulator,id=$udid,arch=arm64" -derivedDataPath $work/dd -quiet > $work/build.log 2>&1; then
  grep -E 'error:' $work/build.log; echo "build failed" >&2; exit 1
fi
data=$(xcrun simctl get_app_container $udid $bundle data)
mkdir -p $data/Documents && : > $data/Documents/events.log
TEST_RUNNER_PROBE_BUNDLE=$bundle TEST_RUNNER_PROBE_SCENARIOS="$*" \
  xcodebuild test-without-building -workspace $src/ios/IosWorkspace.xcworkspace -scheme IosLibraryExample \
  -destination "platform=iOS Simulator,id=$udid,arch=arm64" -derivedDataPath $work/dd \
  -only-testing:IosLibraryExampleUITests/Stage1aDelegateProbeTests/testScenarios 2>&1 \
  | grep -E '\[PROBE-UI\]|error:|\*\* TEST' | grep -v 'with "\[PROBE-UI\]' || true
echo "---- events ($variant)"
cat $data/Documents/events.log
