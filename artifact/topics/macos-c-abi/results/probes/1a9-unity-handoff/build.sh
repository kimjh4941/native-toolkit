#!/usr/bin/env bash
# macOS C ABI 1a-9 probe: builds the two probe xcframeworks for the Unity hand-off.
#
#   DEVELOPER_DIR=<Xcode 26.6>/Contents/Developer ./build.sh <output folder>
#
# Output (<output folder>; outside the repository):
#   ntk-probe-mac-1.0.0.xcframework        NtkProbeMac.framework      (the MacLibrary stand-in)
#   ntk-probe-mac-capi-1.0.0.xcframework   NtkProbeMacCApi.framework  (the C ABI; depends on NtkProbeMac)
#   include/NativeToolkitC/*.h             the public headers of the C ABI
#   BUILD-INFO.txt                          toolchain, commit, exported symbols, links, rpaths, signatures
# and <output folder>-work/ (projects, archives, logs, the smoke; not handed off).
# One slice, macos-arm64_x86_64, minimum macOS 15.0. Not signed (CODE_SIGNING_ALLOWED=NO; the linker's
# ad-hoc signature stays). Versioned frameworks keep their symbolic links: nothing here follows them
# (no cp -R / rsync -L; the xcframeworks are written by -create-xcframework directly).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../../../.." && pwd)"
OUT="$(mkdir -p "${1:?usage: build.sh <output folder>}" && cd "$1" && pwd)"
: "${DEVELOPER_DIR:?set DEVELOPER_DIR to the Developer folder of Xcode 26.6}"
export DEVELOPER_DIR
xcrun swiftc --version 2>&1 | grep -q 'Swift version 6\.3' || { echo "DEVELOPER_DIR must point to Xcode 26.6 (Swift 6.3)" >&2; exit 1; }

CORE_XCF=ntk-probe-mac-1.0.0.xcframework
CAPI_XCF=ntk-probe-mac-capi-1.0.0.xcframework
WORK="${OUT}-work"
rm -rf "$WORK"
mkdir -p "$WORK/logs"

archive() { # <project> <scheme> <name>
  xcodebuild archive -project "$1" -scheme "$2" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$WORK/$3.xcarchive" \
    -derivedDataPath "$WORK/dd-$3" SKIP_INSTALL=NO CODE_SIGNING_ALLOWED=NO \
    > "$WORK/logs/archive-$3.log" 2>&1 || { tail -40 "$WORK/logs/archive-$3.log"; exit 1; }
}

xcf() { # <name> <framework> <output>
  rm -rf "${OUT:?}/$3"
  xcodebuild -create-xcframework -framework "$WORK/$1.xcarchive/Products/Library/Frameworks/$2.framework" \
    -output "$OUT/$3" > "$WORK/logs/xcf-$1.log"
}

echo "[1/3] NtkProbeMac"
ruby "$HERE/gen_projects.rb" "$WORK" core > /dev/null
archive "$WORK/core/NtkProbeMac.xcodeproj" NtkProbeMac core
xcf core NtkProbeMac "$CORE_XCF"

echo "[2/3] NtkProbeMacCApi"
ruby "$HERE/gen_projects.rb" "$WORK" capi "$OUT/$CORE_XCF" > /dev/null
archive "$WORK/capi/NtkProbeMacCApi.xcodeproj" NtkProbeMacCApi capi
xcf capi NtkProbeMacCApi "$CAPI_XCF"

echo "[3/3] check and record"
SLICE=macos-arm64_x86_64
CORE_FW="$OUT/$CORE_XCF/$SLICE/NtkProbeMac.framework"
CAPI_FW="$OUT/$CAPI_XCF/$SLICE/NtkProbeMacCApi.framework"
rm -rf "$OUT/include" && mkdir -p "$OUT/include/NativeToolkitC"
for h in "$CAPI_FW/Versions/A/Headers/NativeToolkitC/"*.h; do cat "$h" > "$OUT/include/NativeToolkitC/$(basename "$h")"; done
status=0
{
  echo "built: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "commit: $(git -C "$REPO" rev-parse --short HEAD)$([[ -z "$(git -C "$REPO" status --porcelain -- "$HERE")" ]] || echo ' (with uncommitted probe sources)')"
  echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "swiftc: $(xcrun swiftc --version 2>&1 | head -1)"
  for fw in "$CORE_FW" "$CAPI_FW"; do
    name=$(basename "$fw" .framework)
    bin="$fw/Versions/A/$name"
    echo "== $name"
    echo "archs: $(lipo -archs "$bin")"
    echo "links: $(cd "$fw" && find . -type l | sort | while read -r l; do printf '%s->%s ' "$l" "$(readlink "$l")"; done)"
    echo "install name: $(otool -D "$bin" | tail -1)"
    echo "dylibs (arm64):"
    otool -arch arm64 -L "$bin" | tail -n +2 | sed 's/^[[:space:]]*/  /'
    echo "rpaths (arm64): $(otool -arch arm64 -l "$bin" | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}' | tr '\n' ' ')"
    echo "signature: $(codesign -dv "$fw" 2>&1 | grep -E '^(Signature|CodeDirectory)' | tr '\n' ' ')"
    # The bundle is not signed (D-18): only the linker's ad-hoc signature on the binary (the signature
    # line above; codesign treats a binary inside a bundle as the bundle). So sign a ditto copy ad hoc the way an app's Embed & Sign does, then verify that copy
    # strictly (a framework whose links became real copies fails here with "bundle format is ambiguous").
    echo "codesign --verify (bundle, as shipped): $(codesign --verify "$fw" 2>&1 | sed 's|.*: ||' | head -1)"
    resign="$WORK/resign/$name.framework"
    rm -rf "$resign" && mkdir -p "$WORK/resign" && ditto "$fw" "$resign"
    codesign -s - -f "$resign" 2>/dev/null
    if codesign --verify --strict --verbose=1 "$resign" 2>"$WORK/logs/verify-resign-$name.txt"; then echo "codesign --verify --strict (ditto copy signed ad hoc): ok"; else echo "codesign --verify --strict (ditto copy signed ad hoc): FAILED $(cat "$WORK/logs/verify-resign-$name.txt")"; status=1; fi
    for arch in $(lipo -archs "$bin"); do
      echo "exports $arch: $(nm -gU -arch "$arch" "$bin" | wc -l | tr -d ' ')"
    done
  done
  for arch in $(lipo -archs "$CAPI_FW/Versions/A/NtkProbeMacCApi"); do
    other=$(nm -gU -arch "$arch" "$CAPI_FW/Versions/A/NtkProbeMacCApi" | awk '{print $NF}' | grep -v '^_ntk_' || true)
    [[ -z "$other" ]] || { echo "NON-NTK exports ($arch): $other"; status=1; }
  done
  for bad in Modules/NtkProbeMacCApi.swiftmodule Headers/NtkProbeMacCApi-Swift.h; do
    [[ ! -e "$CAPI_FW/$bad" ]] || { echo "UNEXPECTED $bad"; status=1; }
  done
  [[ -L "$CAPI_FW/Headers" && -f "$CAPI_FW/Headers/NativeToolkitC/Common.h" ]] || { echo "MISSING top-level Headers link"; status=1; }
  echo "symbols of NtkProbeMacCApi (arm64):"
  nm -gU -arch arm64 "$CAPI_FW/Versions/A/NtkProbeMacCApi" | awk '{print "  " $NF}'
} > "$OUT/BUILD-INFO.txt"
cat "$OUT/BUILD-INFO.txt"
[[ $status -eq 0 ]] || { echo "check failed" >&2; exit 1; }
echo "done: $OUT"
