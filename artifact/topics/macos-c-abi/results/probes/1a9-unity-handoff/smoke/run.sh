#!/usr/bin/env bash
# macOS C ABI 1a-9 probe: the command-line checks on the built xcframeworks (no UI, no notification
# center, no pasteboard: category 1 of agent-rules/device-testing.md).
#
#   smoke/run.sh <output folder of build.sh>
#
# Builds the smoke with the default Xcode (26.3: the consumer side does not need Swift 6.3), runs it on
# arm64 and under Rosetta (x86_64), without and with the entry delay hook (NTK_PROBE_ENTRY_DELAY_MS), then copies the two frameworks side by side with ditto (like
# Contents/PlugIns) and dlopens the C ABI from there.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(cd "${1:?usage: run.sh <output folder of build.sh>}" && pwd)"
SLICE=macos-arm64_x86_64
CORE="$OUT/ntk-probe-mac-1.0.0.xcframework/$SLICE"
CAPI="$OUT/ntk-probe-mac-capi-1.0.0.xcframework/$SLICE"
W="${OUT}-work/smoke"
rm -rf "$W" && mkdir -p "$W/side"
echo "consumer: $(xcodebuild -version | head -1)"
xcrun clang -std=c11 -Wall -Wextra -Werror -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 \
  -F "$CAPI" -framework NtkProbeMacCApi -framework CoreFoundation \
  -Wl,-rpath,"$CAPI" -Wl,-rpath,"$CORE" "$HERE/main.c" -o "$W/smoke"
xcrun clang -std=c99 -Wall -Wextra -Werror -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 "$HERE/dlopen.c" -o "$W/dlopen"
ditto "$CORE/NtkProbeMac.framework" "$W/side/NtkProbeMac.framework"
ditto "$CAPI/NtkProbeMacCApi.framework" "$W/side/NtkProbeMacCApi.framework"
status=0
# The login user's home from the user database (never printed), and HOME pointed at a fake container
# the way the sandbox points it: the path redaction must use the former.
export NTK_SMOKE_REAL_HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')"
mkdir -p "$W/fake-home/Library/Containers/x/Data"
run() { HOME="$W/fake-home/Library/Containers/x/Data" "$@"; }
echo "== arm64";        run "$W/smoke" || status=1
echo "== x86_64";       run arch -x86_64 "$W/smoke" || status=1
# The same with the probe-only hook: entries called off main sleep 300 ms before their last statement,
# while main drains its queue. The completion is still never called on the calling thread.
echo "== arm64, entry delay 300 ms";  NTK_PROBE_ENTRY_DELAY_MS=300 run "$W/smoke" || status=1
echo "== x86_64, entry delay 300 ms"; NTK_PROBE_ENTRY_DELAY_MS=300 run arch -x86_64 "$W/smoke" || status=1
echo "== dlopen sibling layout (arm64)";  "$W/dlopen" "$W/side" || status=1
echo "== dlopen sibling layout (x86_64)"; arch -x86_64 "$W/dlopen" "$W/side" || status=1
exit $status
