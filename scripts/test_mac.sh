#!/usr/bin/env bash
# Runs the macOS unit tests and the sample's UI tests in the qualified tart VM, or, after the user
# approved the list, on this Mac.
#
# Follows section 6.3 of artifact/topics/macos-c-abi/designs/2026-11-23-macos-c-abi-ui-test-design.md.
# What runs and every check of what ran is decided in scripts/mac_ui_runner.py; this script runs
# xcodebuild, tart, ssh and tar. Bash 3.2 (the one macOS ships, here and in the VM).
#
# Usage: scripts/test_mac.sh --where vm [--vm <name>] [--feature Dialog|Notification|Share|Clipboard]
#          [--skip-unit] [--baseline] [--name-each-test] [--keep-vm-run]
#        scripts/test_mac.sh --where mac [--allow <c,...>] [--allow-lsregister] [--feature ...] [--skip-unit]
#          (--dry-run | --approved <file>) [--baseline] [--vm <name>]
#   --where             vm or mac; required. The VM must pass the qualification (6.3 step 0) every time;
#                       when it does not, the runner stops and never falls back to this Mac
#   --vm                the tart VM (default ntk-macos-15-new); this Mac's runs enumerate there too
#   --feature           only that feature's UI classes and the common ones; no unit tests
#   --skip-unit         no unit tests
#   --allow             mac only: the categories allowed on this Mac (none by default):
#                       notification,settings,badge,clipboard,sharepicker,panels,coldstart
#   --allow-lsregister  mac only: NOT IMPLEMENTED; the run stops. Remove the extra registered copies
#                       yourself, then plan and ask again (U-21)
#   --dry-run           mac only: enumerates in the VM, starts nothing on this Mac (no build), prints
#                       the list, what happens, what to prepare and the time, and writes the approval list
#   --approved          mac only: the approval list the user approved; an approval runs once
#   --baseline          saves the results as the baseline of that environment (6.3 "基準の条件")
#   --name-each-test    vm only: one xcodebuild per test (this Mac always does)
#   --qualification     mac26|mac26-reply|vm-ja: only the U-30 probes of that stage (none are written yet)
#   --keep-vm-run       vm only: leave the VM's run folder (sources, DerivedData, result bundles) for a look
set -euo pipefail

# The VM half's prelude (review v1: Codex A-1, Claude B-1; v2: Codex A-1). Before anything else, in
# whatever environment it was called: the three facts of the VM, read by absolute path (a name with a
# slash is never a shell function): kern.hv_vmm_present, hw.model, and the IOPlatformUUID the runner
# qualified (`--in-vm <op> <run id> <UUID> ...`). Then `--in-vm` always starts again with an empty
# environment as a privileged bash (no exported functions, no BASH_ENV); nothing the caller can set
# skips that. The started side (`--in-vm-clean`) checks the facts again and that its environment is
# exactly what env -i made, and stops otherwise.
if [[ "${1:-}" == "--in-vm" || "${1:-}" == "--in-vm-clean" ]]; then
  [[ "$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null)" == "1" ]] || { echo "Error: --in-vm runs only in the VM" >&2; exit 96; }
  case "$(/usr/sbin/sysctl -n hw.model 2>/dev/null)" in VirtualMac*) ;; *) echo "Error: --in-vm runs only in the VM" >&2; exit 96 ;; esac
  [[ $# -ge 4 && -n "$4" && "$(/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice | /usr/bin/awk -F'"' '/IOPlatformUUID/{print $4}')" == "$4" ]] \
    || { echo "Error: --in-vm runs only in the qualified VM" >&2; exit 96; }
  if [[ "$1" == "--in-vm" ]]; then
    exec /usr/bin/env -i HOME="${HOME}" USER="${USER:-}" LOGNAME="${LOGNAME:-}" LC_ALL=C PATH=/usr/bin:/bin:/usr/sbin:/sbin \
      /bin/bash --noprofile --norc -p "${BASH_SOURCE[0]}" --in-vm-clean "${@:2}"
  fi
  [[ -o privileged && -z "$(declare -F)" && "${PATH}" == "/usr/bin:/bin:/usr/sbin:/sbin" && "${LC_ALL:-}" == C ]] \
    || { echo "Error: --in-vm-clean runs only as started by --in-vm" >&2; exit 96; }
  for __name in $(compgen -e); do
    case "${__name}" in HOME|USER|LOGNAME|LC_ALL|PATH|PWD|SHLVL|OLDPWD|_) ;; *) echo "Error: --in-vm-clean runs only as started by --in-vm" >&2; exit 96 ;; esac
  done
fi
# --- end of the VM prelude ---

# What a test may touch reaches it only through the runner's own xcodebuild (U-9).
# Nothing from outside the runner may change the build or the tests either: an xcconfig over the
# projects' settings, another toolchain or Xcode, a TEST_RUNNER_ or SIMCTL_CHILD_ variable (Codex A-3).
unset XCODE_XCCONFIG_FILE TOOLCHAINS DEVELOPER_DIR
for __name in $(compgen -e); do
  case "${__name}" in TEST_RUNNER_*|SIMCTL_CHILD_*|NTK_HOST|NTK_ALLOW|NTK_FIXTURE_DIR|NTK_EXPECTED_COPY) unset "${__name}" ;; esac
done
unset __name

DESTINATION="platform=macOS,arch=arm64"
SAMPLE_ID="com.jonghyunkim.mac.nativetoolkit.example"
PREVIEW_KEY="EnablePasteboardPrivacyDeveloperPreview"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
UI_XCTEST_BINARY="MacLibraryExampleUITests-Runner.app/Contents/PlugIns/MacLibraryExampleUITests.xctest/Contents/MacOS/MacLibraryExampleUITests"
TIME_FLAGS=(-parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 120
  -maximum-test-execution-time-allowance 240)
RUN_ID_PATTERN='^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{6}$'

# Runs a command in its own process group with a time limit: perl starts it and waits for it, polling.
# The group is signalled (TERM, up to 30 s, KILL) only by this perl and only while its leader is perl's own
# child that it has not reaped (alive or a zombie): until then the number cannot belong to anything else.
# Once the leader is reaped nothing more is sent to anything (review v5). The group is stopped when the
# time is up (142), when the stop file appears (143; how the shell asks: the shell never signals a
# number, review v5: Codex A-3), when perl's parent (the shell) is gone (129), and on HUP, INT and TERM.
# The pid file is opened and the handlers set before the fork, and the three signals are blocked across
# it, so a signal never finds a child perl does not know (review v4: Codex A-2; v5: Claude C-1).
# Arguments: <seconds> <pid file or -> <stop file or -> <command...>. stdin is /dev/null.
CAPPED_PERL='use POSIX ();
  my $seconds = shift; my $pidfile = shift; my $stopfile = shift;
  die "time limit: $seconds\n" unless $seconds =~ /^[1-9][0-9]*$/;
  my $pid = 0; my $reaped = 0; my $status = 0; my $parent = getppid();
  # Before every signal: is the leader still the own unreaped child of this perl? waitpid with WNOHANG answers
  # it even when it was reaped already (-1, ECHILD).
  my $gone = sub {
    return 1 if $reaped;
    my $r = waitpid($pid, POSIX::WNOHANG());
    if ($r == $pid) { $status = $?; $reaped = 1; return 1; }
    if ($r == -1) { $reaped = 1; return 1; }
    return 0;
  };
  my $stop = sub {
    return unless $pid > 0;
    return if $gone->();
    kill "TERM", -$pid;
    for (1..60) { return if $gone->(); select(undef, undef, undef, 0.5); }
    return if $gone->();
    kill "KILL", -$pid;
    waitpid($pid, 0); $reaped = 1;
  };
  my %number = (HUP => 1, INT => 2, TERM => 15);
  for my $name (keys %number) { $SIG{$name} = sub { $stop->(); exit 128 + $number{$name}; }; }
  my $f;
  if ($pidfile ne "-") { open($f, ">", $pidfile) or die "pid file: $!\n"; }
  my $blocked = POSIX::SigSet->new(POSIX::SIGHUP(), POSIX::SIGINT(), POSIX::SIGTERM());
  my $before = POSIX::SigSet->new();
  POSIX::sigprocmask(POSIX::SIG_BLOCK(), $blocked, $before);
  my $child = fork;
  if (defined $child && $child == 0) {
    $SIG{$_} = "DEFAULT" for keys %number;
    POSIX::sigprocmask(POSIX::SIG_SETMASK(), $before);
    setpgrp(0, 0); exec @ARGV or POSIX::_exit(127);
  }
  die "fork: $!\n" unless defined $child;
  $pid = $child; setpgrp($pid, $pid);
  POSIX::sigprocmask(POSIX::SIG_SETMASK(), $before);
  if ($f) { unless ((print {$f} "$pid\n") && close($f)) { $stop->(); exit 125; } }
  my $deadline = time + $seconds;
  until ($gone->()) {
    if (time >= $deadline) { $stop->(); exit 142; }
    if ($stopfile ne "-" && -e $stopfile) { $stop->(); exit 143; }
    if (getppid() != $parent) { $stop->(); exit 129; }
    select(undef, undef, undef, 0.2);
  }
  exit(($status & 127) ? 128 + ($status & 127) : $status >> 8);'
# The VM half's xcodebuild. After it, the same judgement as this Mac's settle runs, only written down: how
# many processes of its group are left after 15 s (the VM is cleaned anyway; review v6: Claude B-1, Codex
# B-2). `finish` prints the summary.
capped_group() {  # <seconds> <pid file or -> <command...>
  local seconds="$1" pidfile="$2" code=0; shift 2
  [[ "${pidfile}" != - ]] || pidfile="${RUN_DIR}/capped.pid"
  rm -f "${pidfile}"
  /usr/bin/perl -e "${CAPPED_PERL}" "${seconds}" "${pidfile}" - "$@" < /dev/null || code=$?
  if [[ -s "${pidfile}" ]]; then
    vrunner settle-report --pgid "$(cat "${pidfile}")" --log "${RUN_DIR}/settle.log" > /dev/null 2>&1 || true
  fi
  return "${code}"
}

# ============================================================================================
# Inside the VM (`test_mac.sh --in-vm <op> <run id> <VM UUID> ...`). Never on this Mac: before anything
# else, kern.hv_vmm_present is 1, hw.model is a VirtualMac and the IOPlatformUUID is the one the runner
# qualified, each read with an absolute path in the clean environment above. The run folder is
# ~/ntk/runs/<run id> (sources, DerivedData, results, logs).
# ============================================================================================

in_vm_main() {
  [[ "$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null)" == "1" ]] || { echo "Error: --in-vm runs only in the VM" >&2; exit 96; }
  case "$(/usr/sbin/sysctl -n hw.model 2>/dev/null)" in VirtualMac*) ;; *) echo "Error: --in-vm runs only in the VM" >&2; exit 96 ;; esac
  [[ $# -ge 3 && -n "$3" && "$(/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice | /usr/bin/awk -F'"' '/IOPlatformUUID/{print $4}')" == "$3" ]] \
    || { echo "Error: --in-vm runs only in the qualified VM" >&2; exit 96; }
  local op="$1" run_id="$2"; shift 3
  [[ "${run_id}" =~ ${RUN_ID_PATTERN} ]] || { echo "Error: malformed run id" >&2; exit 96; }
  RUNS="${HOME}/ntk/runs"
  RUN_DIR="${RUNS}/${run_id}"
  SRC="${RUN_DIR}/src/mac"
  DD_UI="${RUN_DIR}/dd-ui"
  DD_LIB="${RUN_DIR}/dd-lib"
  RES="${RUN_DIR}/results"
  LOGS="${RUN_DIR}/logs"
  FX="/private/tmp/ntk-uitest-${run_id}"
  STATE="${HOME}/ntk/state"
  # The result bundles of the VM's failed UI tests, kept until someone has written down what they say;
  # then they are removed by hand (they hold screenshots of the VM's screen). Never removed by a run.
  FAILED_KEEP="${HOME}/ntk/failed/${run_id}"
  TESTS_DIR="${SRC}/MacLibraryExample/MacLibraryExampleUITests"
  vrunner() { /usr/bin/python3 "${RUN_DIR}/runner/mac_ui_runner.py" "$@"; }
  mkdir -p "${RES}" "${LOGS}" "${STATE}"
  case "${op}" in
    clean) vm_clean "${run_id}" ;;
    tree-hash) vrunner tree-hash --dir "${RUN_DIR}/src" ;;
    # The copy's hashes come from shasum, not from the copied runner itself (review v5: Claude C-2).
    runner-hashes) printf '{"scripts/mac_ui_runner.py": "%s", "scripts/test_mac.sh": "%s"}\n' \
      "$(/usr/bin/shasum -a 256 "${RUN_DIR}/runner/mac_ui_runner.py" | /usr/bin/awk '{print $1}')" \
      "$(/usr/bin/shasum -a 256 "${RUN_DIR}/runner/test_mac.sh" | /usr/bin/awk '{print $1}')" ;;
    build) vm_build ;;
    enumerate) vm_enumerate "${DD_UI}" enumeration ;;
    enumerate-lib) vm_enumerate "${DD_LIB}" unit-enumeration ;;
    check-build) vm_check_build ;;
    prepare) vm_prepare ;;
    unit) vm_unit "$1" ;;
    ui) vm_ui "$1" ;;
    privacy-begin) vm_privacy_begin ;;
    privacy-end) vm_privacy_end ;;
    coverage) vm_coverage ;;
    finish) vm_finish "${1:-0}" ;;
    *) echo "Error: unknown op ${op}" >&2; exit 2 ;;
  esac
}

vm_restart_notification_ui() {  # 6b: NotificationCenter and usernoted, then 5 s once both are back
  killall NotificationCenter usernoted 2>/dev/null || true
  local i
  for i in $(seq 1 60); do
    pgrep -x NotificationCenter >/dev/null && pgrep -x usernoted >/dev/null && break
    sleep 0.5
  done
  sleep 5
  echo "NTK-VM restart notificationUI"
}

vm_stop_sample() {
  pkill -x MacLibraryExample 2>/dev/null || true
  local i
  for i in $(seq 1 40); do pgrep -x MacLibraryExample >/dev/null || return 0; sleep 0.25; done
  return 1
}

vm_unregister_outside() {  # U-21 (VM): every registered copy of the sample and the runner outside this run
  local dump="${LOGS}/lsregister.txt" path
  "${LSREGISTER}" -dump > "${dump}" 2>/dev/null || true
  vrunner lsregister --dump "${dump}" --run-root "${RUN_DIR}" --paths | while IFS= read -r path; do
    "${LSREGISTER}" -u "${path}" >/dev/null 2>&1 || true
    echo "NTK-VM unregistered a copy outside this run"
  done
  rm -f "${dump}"
}

vm_clean() {  # the previous runs: their processes, the preview setting they may have left, their folders
  local current="$1" folder
  pkill -x xcodebuild 2>/dev/null || true
  vm_stop_sample || true
  pkill -x Mail 2>/dev/null || true
  # Processes started from a previous run's folder (not this run's, which runs this script).
  local pid
  for pid in $(pgrep -f "${RUNS}/" || true); do
    ps -o args= -p "${pid}" 2>/dev/null | grep -qF "${RUNS}/${current}" || kill "${pid}" 2>/dev/null || true
  done
  if [[ -f "${STATE}/privacy-original" ]]; then
    # A run stopped inside the paste privacy stage: put the setting back as it was before it.
    if [[ "$(cat "${STATE}/privacy-original")" == "absent" ]]; then
      defaults delete "${SAMPLE_ID}" "${PREVIEW_KEY}" >/dev/null 2>&1 || true
    fi
    rm -f "${STATE}/privacy-original"
    echo "NTK-VM restored the paste privacy setting a stopped run left"
  fi
  for folder in "${RUNS}"/*; do
    [[ -d "${folder}" && "$(basename "${folder}")" != "${current}" ]] || continue
    rm -rf "${folder}"
    echo "NTK-VM removed a previous run folder"
  done
  rm -rf /private/tmp/ntk-uitest-* 2>/dev/null || true
  echo "NTK-VM clean"
}

vm_build() {
  local scheme dd log
  cd "${SRC}"
  for scheme in MacLibraryExample MacLibrary; do
    if [[ "${scheme}" == MacLibrary ]]; then dd="${DD_LIB}"; else dd="${DD_UI}"; fi
    log="${LOGS}/build-${scheme}.log"
    if ! capped_group 2400 - xcodebuild build-for-testing -workspace MacWorkspace.xcworkspace -scheme "${scheme}" \
        -destination "${DESTINATION}" -derivedDataPath "${dd}" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= > "${log}" 2>&1; then
      echo "NTK-VM build failed ${scheme} errors=$(grep -c ' error: ' "${log}" || true)"
      exit 1
    fi
    if [[ "$(ls "${dd}"/Build/Products/*.xctestrun 2>/dev/null | wc -l | tr -d ' ')" != "1" ]]; then
      echo "NTK-VM build failed ${scheme}: not exactly one .xctestrun"
      exit 1
    fi
    echo "NTK-VM build ok ${scheme} warnings=$(grep ' warning: ' "${log}" | grep -v appintentsmetadataprocessor | sort -u | wc -l | tr -d ' ')"
  done
}

xctestrun_of() { ls "$1"/Build/Products/*.xctestrun; }

vm_enumerate() {  # <DerivedData> <name>: the tests of that build's .xctestrun, as JSON on stdout
  local dd="$1" name="$2"
  rm -rf "${RES}/${name}.xcresult" "${RUN_DIR}/${name}.json"
  if ! capped_group 600 - xcodebuild test-without-building -xctestrun "$(xctestrun_of "${dd}")" \
      -destination "${DESTINATION}" -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
      -test-enumeration-output-path "${RUN_DIR}/${name}.json" -resultBundlePath "${RES}/${name}.xcresult" \
      > "${LOGS}/${name}.log" 2>&1; then
    echo "NTK-VM enumerate failed" >&2
    exit 1
  fi
  cat "${RUN_DIR}/${name}.json"
}

vm_check_build() {
  local products="${DD_UI}/Build/Products/Debug" binary
  binary="${products}/${UI_XCTEST_BINARY}"
  xcrun otool -arch arm64 -ov "${binary}" > "${LOGS}/otool-ov.txt"
  xcrun otool -arch arm64 -l "${binary}" > "${LOGS}/otool-l.txt"
  vrunner check-build --products "${products}" --tests-dir "${TESTS_DIR}" --enumeration "${RUN_DIR}/enumeration.json" \
    --otool-objc "${LOGS}/otool-ov.txt" --otool-load "${LOGS}/otool-l.txt"
}

vm_prepare() {
  # U-20: banners show while XCUITest records the screen.
  /usr/bin/python3 - <<'PY'
import os, plistlib
p = os.path.expanduser("~/Library/Preferences/com.apple.ncprefs.plist")
d = plistlib.load(open(p, "rb"))
dp = plistlib.loads(d["dnd_prefs"])
dp["dndMirrored"] = False
d["dnd_prefs"] = plistlib.dumps(dp, fmt=plistlib.FMT_BINARY)
plistlib.dump(d, open(p, "wb"), fmt=plistlib.FMT_BINARY)
PY
  killall cfprefsd 2>/dev/null || true
  vm_restart_notification_ui
  vm_stop_sample || true
  pkill -x Mail 2>/dev/null || true
  vm_unregister_outside
  # U-11: the fixture, made anew without following any link, and its manifest before the run.
  vrunner fixture-create --dir "${FX}"
  vrunner fixture-manifest --dir "${FX}" > "${RUN_DIR}/fixture-before.json"
  vrunner copy-mark --app "${DD_UI}/Build/Products/Debug/MacLibraryExample.app" > "${RUN_DIR}/expected-copy.txt"
  echo "NTK-VM prepared"
}

vm_xcresult_json() {  # <bundle> <out prefix>
  xcrun xcresulttool get test-results tests --path "$1" > "$2-tests.json" 2>/dev/null || rm -f "$2-tests.json"
  xcrun xcresulttool get test-results summary --path "$1" > "$2-summary.json" 2>/dev/null || rm -f "$2-summary.json"
}

vm_unit() {
  local index="$1" target xctestrun code=0 args
  target="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["unitInvocations"][int(sys.argv[2])]["target"])' "${RUN_DIR}/plan.json" "${index}")"
  if [[ "${target}" == MacLibraryTests ]]; then xctestrun="$(xctestrun_of "${DD_LIB}")"; else xctestrun="$(xctestrun_of "${DD_UI}")"; fi
  # The names are read on their own, so that a failed or empty lookup stops instead of running everything.
  args="$(vrunner only-testing --plan "${RUN_DIR}/plan.json" --unit "${index}")" || exit 1
  [[ -n "${args}" ]] || exit 1
  rm -rf "${RES}/unit-${index}.xcresult"
  # shellcheck disable=SC2086
  capped_group 1800 - xcodebuild test-without-building -xctestrun "${xctestrun}" -destination "${DESTINATION}" \
    ${args} -resultBundlePath "${RES}/unit-${index}.xcresult" -parallel-testing-enabled NO \
    > "${LOGS}/unit-${index}.log" 2>&1 || code=$?
  vm_xcresult_json "${RES}/unit-${index}.xcresult" "${RES}/unit-${index}"
  vrunner unit-record --plan "${RUN_DIR}/plan.json" --index "${index}" --tests-json "${RES}/unit-${index}-tests.json" \
    --summary-json "${RES}/unit-${index}-summary.json" --exit-code "${code}" --tests-dir "${TESTS_DIR}"
}

vm_reset_permission() {  # U-7 (VM): the sample stopped, its entry gone from com.apple.ncprefs, up to 3 tries
  vm_stop_sample || true
  local attempt
  for attempt in 1 2 3; do
    /usr/bin/python3 - "${SAMPLE_ID}" <<'PY'
import os, plistlib, sys
p = os.path.expanduser("~/Library/Preferences/com.apple.ncprefs.plist")
d = plistlib.load(open(p, "rb"))
d["apps"] = [a for a in d.get("apps", []) if a.get("bundle-id") != sys.argv[1]]
plistlib.dump(d, open(p, "wb"), fmt=plistlib.FMT_BINARY)
PY
    killall cfprefsd usernoted NotificationCenter 2>/dev/null || true
    sleep 2
    if ! defaults read com.apple.ncprefs apps 2>/dev/null | grep -qF "${SAMPLE_ID}"; then
      echo "NTK-VM permission reset attempt=${attempt}"
      return 0
    fi
  done
  echo "NTK-VM permission reset failed"
  return 1
}

vm_ui() {
  local index="$1" line stage name timeout prepare after class code=0 timed_out=0 args failed
  line="$(vrunner invocations --plan "${RUN_DIR}/plan.json" | awk -F'\t' -v i="${index}" '$1 == i')"
  IFS=$'\t' read -r _ stage name timeout prepare after class <<< "${line}"
  case ",${prepare}," in
    *,ncreset,*) vm_reset_permission || echo "{\"test\": \"MacLibraryExampleUITests/${name}#permissionReset\", \"result\": \"failed\", \"codes\": [\"NTK-RUNNER:permissionReset\"]}" ;;
  esac
  case ",${prepare}," in *,ncui,*) vm_restart_notification_ui ;; esac
  args="$(vrunner only-testing --plan "${RUN_DIR}/plan.json" --index "${index}")" || exit 1
  [[ -n "${args}" ]] || exit 1
  rm -rf "${RES}/ui-${index}.xcresult"
  # shellcheck disable=SC2086
  TEST_RUNNER_NTK_HOST=vm \
  TEST_RUNNER_NTK_ALLOW="notification,ncsettings,settings,badge,clipboard,pasteprivacy,sharepicker,realservice,panels,coldstart" \
  TEST_RUNNER_NTK_FIXTURE_DIR="${FX}" TEST_RUNNER_NTK_EXPECTED_COPY="$(cat "${RUN_DIR}/expected-copy.txt")" \
    capped_group "${timeout}" - xcodebuild test-without-building -xctestrun "$(xctestrun_of "${DD_UI}")" \
    -destination "${DESTINATION}" ${args} -resultBundlePath "${RES}/ui-${index}.xcresult" "${TIME_FLAGS[@]}" \
    > "${LOGS}/ui-${index}.log" 2>&1 || code=$?
  [[ "${code}" == 142 ]] && timed_out=1
  vm_xcresult_json "${RES}/ui-${index}.xcresult" "${RES}/ui-${index}"
  vrunner record --plan "${RUN_DIR}/plan.json" --index "${index}" --tests-json "${RES}/ui-${index}-tests.json" \
    --summary-json "${RES}/ui-${index}-summary.json" --exit-code "${code}" --timed-out "${timed_out}" \
    --tests-dir "${TESTS_DIR}" | tee "${RES}/ui-${index}.records"
  failed=0
  grep -q '"result": "failed"' "${RES}/ui-${index}.records" && failed=1
  if [[ "${failed}" == 1 && -d "${RES}/ui-${index}.xcresult" ]]; then
    mkdir -p "${FAILED_KEEP}"
    cp -R "${RES}/ui-${index}.xcresult" "${FAILED_KEEP}/"
    cp "${LOGS}/ui-${index}.log" "${FAILED_KEEP}/" 2>/dev/null || true
  fi
  case "${class}" in
    NotificationPermissionUITests|NotificationUITests|NotificationEventUITests|NotificationColdStartUITests)
      # 6b: a notification test that failed may leave a banner expanded in the list; restart before the next.
      [[ "${failed}" == 1 ]] && vm_restart_notification_ui ;;
  esac
  case ",${after}," in *,stopMail,*) pkill -x Mail 2>/dev/null || true ;; esac
  vm_stop_sample || true
}

vm_privacy_begin() {  # U-12: the preview setting of the sample, and what it was before
  vm_stop_sample || true
  if defaults read "${SAMPLE_ID}" "${PREVIEW_KEY}" >/dev/null 2>&1; then
    echo "NTK-VM privacy setting already present; not starting the stage"
    exit 1
  fi
  echo absent > "${STATE}/privacy-original"
  defaults write "${SAMPLE_ID}" "${PREVIEW_KEY}" -bool yes
  echo "NTK-VM privacy begin"
}

vm_privacy_end() {
  vm_stop_sample || true
  defaults delete "${SAMPLE_ID}" "${PREVIEW_KEY}" >/dev/null 2>&1 || true
  if defaults read "${SAMPLE_ID}" "${PREVIEW_KEY}" >/dev/null 2>&1; then
    echo '{"test": "MacLibraryExampleUITests#privacyRestore", "result": "failed", "codes": ["NTK-RUNNER:privacyRestore"]}'
    exit 1
  fi
  rm -f "${STATE}/privacy-original"
  echo '{"test": "MacLibraryExampleUITests#privacyRestore", "result": "passed", "codes": []}'
}

vm_coverage() {
  local bundle n=0
  rm -rf "${RES}/attachments"
  mkdir -p "${RES}/attachments"
  for bundle in "${RES}"/ui-*.xcresult; do
    [[ -d "${bundle}" ]] || continue
    n=$((n + 1))
    xcrun xcresulttool export attachments --path "${bundle}" --output-path "${RES}/attachments/${n}" >/dev/null 2>&1 || true
  done
  vrunner coverage --plan "${RUN_DIR}/plan.json" --sample-dir "${SRC}/MacLibraryExample/MacLibraryExample" \
    --attachments-root "${RES}/attachments"
}

vm_finish() {
  local keep="$1" app
  # Only a run that prepared the fixture compares it (an enumeration for this Mac's plan did not).
  if [[ -f "${RUN_DIR}/fixture-before.json" ]]; then
    if [[ -d "${FX}" ]] && vrunner fixture-manifest --dir "${FX}" > "${RUN_DIR}/fixture-after.json"; then
      vrunner fixture-compare --before "${RUN_DIR}/fixture-before.json" --after "${RUN_DIR}/fixture-after.json"
    else
      echo '{"test": "MacLibraryExampleUITests#fixture", "result": "failed", "codes": ["NTK-RUNNER:fixture"]}'
    fi
  fi
  [[ -f "${RUN_DIR}/settle.log" ]] && vrunner settle-summary --log "${RUN_DIR}/settle.log"
  if [[ -d "${FAILED_KEEP}" ]]; then
    echo "NTK-VM kept $(ls -d "${FAILED_KEEP}"/*.xcresult 2>/dev/null | wc -l | tr -d ' ') failed result bundle(s) under ~/ntk/failed in the VM; remove them once written down"
  fi
  vm_stop_sample || true
  pkill -x Mail 2>/dev/null || true
  for app in "${DD_UI}/Build/Products/Debug/MacLibraryExample.app" \
             "${DD_UI}/Build/Products/Debug/MacLibraryExampleUITests-Runner.app"; do
    [[ -d "${app}" ]] && "${LSREGISTER}" -u "${app}" >/dev/null 2>&1 || true
  done
  rm -rf "${FX}"
  if [[ "${keep}" == 1 ]]; then
    echo "NTK-VM kept the run folder"
  else
    rm -rf "${RUN_DIR}"
    echo "NTK-VM removed the run folder"
  fi
}


# ============================================================================================
# On this Mac.
# ============================================================================================

# The run on this Mac starts in main (at the end of this file).

# --- The VM: qualification, identity and the commands sent to it ------------------------------

vm_ssh_raw() {
  ssh -F /dev/null -i "${VM_KEYS}/id_ed25519" -o UserKnownHostsFile="${VM_KEYS}/known_hosts" -o StrictHostKeyChecking=yes \
    -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=10 \
    -o LogLevel=ERROR "admin@${VM_IP}" "$@"
}

# Every command after the qualification first checks, on this Mac, that tart still runs the VM with
# --no-clipboard and no shared folder (Claude B-2), and in the VM that it is the one that was qualified:
# the same IOPlatformUUID and the same boot (6.3 "同一性の束ね").
vm_ssh() {
  ps -axo args= | runner tart-check --ps - --vm "${VM_NAME}" || exit 96
  vm_ssh_raw "u=\$(/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice | /usr/bin/awk -F'\"' '/IOPlatformUUID/{print \$4}'); \
b=\$(/usr/sbin/sysctl -n kern.boottime | /usr/bin/sed -E 's/^\\{ sec = ([0-9]+),.*/\\1/'); \
$(vm_identity_check) || { echo 'Error: the VM is not the one that was qualified' >&2; exit 96; }; $*"
}

# The check the VM runs on `u` (its IOPlatformUUID) and `b` (the seconds of its kern.boottime): the UUID exactly,
# and the same boot within VM_BOOT_SLACK seconds. The guest's clock is adjusted while it runs, and that moves
# kern.boottime across a second's edge (2026-11-28: …503.017 → …502.948); a restart moves it by minutes and
# stays another VM. A `b` that is not a number is another VM too.
VM_BOOT_SLACK="5"
vm_identity_check() {
  printf '%s' "case \"\$b\" in ''|*[!0-9]*) b=-1 ;; esac; [ \"\$u\" = '${VM_UUID}' ] && [ \"\$b\" -ge 0 ] && \
[ \$((b - ${VM_BOOT})) -ge -${VM_BOOT_SLACK} ] && [ \$((b - ${VM_BOOT})) -le ${VM_BOOT_SLACK} ]"
}

vm_op() {  # <op> <run id> [args...]: the in-VM half of this script (stdin is not the caller's)
  local op="$1" id="$2"; shift 2
  vm_ssh "bash \"\$HOME/ntk/runs/${id}/runner/test_mac.sh\" --in-vm ${op} ${id} ${VM_UUID} $*" < /dev/null
}

json_lines() { grep '^{' "$1" || true; }

vm_qualify() {
  local facts="${PRIVATE}/vm-facts.txt"
  [[ -f "${VM_KEYS}/id_ed25519" && -f "${VM_KEYS}/known_hosts" ]] || fail "the VM's own ssh key and known_hosts are missing"
  tart list --format json > /dev/null 2>&1 || fail "tart is not available"
  VM_IP="$(tart ip "${VM_NAME}" 2>/dev/null)" || fail "the VM ${VM_NAME} is not running (tart ip)"
  [[ "${VM_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "unexpected address of the VM"
  vm_ssh_raw 'bash -s' > "${facts}" <<'EOS'
echo "hvVmmPresent=$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null)"
echo "hwModel=$(/usr/sbin/sysctl -n hw.model 2>/dev/null)"
echo "vmBoottime=$(/usr/sbin/sysctl -n kern.boottime | /usr/bin/sed -E 's/^\{ sec = ([0-9]+),.*/\1/')"
echo "osVersion=$(sw_vers -productVersion)"
echo "osBuild=$(sw_vers -buildVersion)"
if defaults read MobileMeAccounts Accounts >/dev/null 2>&1; then echo "mobileMeAccounts=present"; else echo "mobileMeAccounts=absent"; fi
sqlite3 -separator '|' "$HOME/Library/Accounts/Accounts4.sqlite" \
  "select t.ZIDENTIFIER, a.ZAUTHENTICATED from ZACCOUNT a left join ZACCOUNTTYPE t on a.ZACCOUNTTYPE = t.Z_PK;" 2>/dev/null \
  | sed 's/^/account=/'
echo "virtiofsMounts=$(mount | grep -c virtiofs)"
xcodebuild -version 2>/dev/null | awk 'NR==1{print "xcodeVersion="$2} NR==2{print "xcodeBuild="$3}'
echo "language=$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | tr -d ' ",')"
echo "platformUUID=$(/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice | /usr/bin/awk -F'"' '/IOPlatformUUID/{print $4}')"
echo "macAddress=$(/sbin/ifconfig en0 2>/dev/null | /usr/bin/awk '/ether/{print $2}')"
echo "arch=$(uname -m)"
EOS
  python3 - "${facts}" "${PRIVATE}/vm-facts.json" <<'PY'
import json, sys
facts = {"accounts": []}
for line in open(sys.argv[1], encoding="utf-8"):
    key, _, value = line.rstrip("\n").partition("=")
    if key == "account":
        kind, _, authenticated = value.partition("|")
        facts["accounts"].append({"type": kind, "authenticated": authenticated})
    elif key:
        facts[key] = value
json.dump(facts, open(sys.argv[2], "w"))
PY
  # The tart VM of that name and the ssh peer are the same machine: tart's MAC address of the VM equals the
  # peer's en0 (Codex v2 B-2). tart's own file is read, never written.
  python3 - "${PRIVATE}/vm-facts.json" "${ACCOUNT_HOME}/.tart/vms/${VM_NAME}/config.json" <<'PY'
import json, sys
facts = json.load(open(sys.argv[1]))
try:
    facts["tartMacAddress"] = json.load(open(sys.argv[2])).get("macAddress", "")
except (OSError, ValueError):
    facts["tartMacAddress"] = ""
json.dump(facts, open(sys.argv[1], "w"))
PY
  ps -axo args= | runner vm-qualify --facts "${PRIVATE}/vm-facts.json" --ps - --vm "${VM_NAME}" \
    --out "${OUT}/vm-qualification.json" --uuid-out "${PRIVATE}/vm-id" --qualification "${QUALIFICATION}"
  IFS=$'\t' read -r VM_UUID VM_BOOT < "${PRIVATE}/vm-id"
  VM_OS="$(python3 -c 'import json,sys; f=json.load(open(sys.argv[1])); print(f["osVersion"], f["osBuild"], f["arch"], f["language"], f["xcodeVersion"], sep="\t")' "${PRIVATE}/vm-facts.json")"
  rm -f "${facts}" "${PRIVATE}/vm-facts.json" "${PRIVATE}/vm-id"
}

vm_push() {  # 6.3 step 1: mac/ as git would hand it over, and the runner, by tar over ssh
  local list="${PRIVATE}/files"
  vm_ssh "mkdir -p \"\$HOME/ntk/runs/${RUN_ID}/src\" \"\$HOME/ntk/runs/${RUN_ID}/runner\""
  runner file-list --repo "${ROOT_DIR}" > "${list}"
  (cd "${ROOT_DIR}" && COPYFILE_DISABLE=1 tar --null -T "${list}" -cf -) | \
    vm_ssh "tar -xf - -C \"\$HOME/ntk/runs/${RUN_ID}/src\""
  # The runner goes from a snapshot taken once; its hashes are what the plan and the baseline name, after
  # the VM's copy is checked against them (review v4: Codex A-3).
  rm -rf "${PRIVATE}/runner-snapshot"
  mkdir "${PRIVATE}/runner-snapshot"
  cp "${ROOT_DIR}/scripts/mac_ui_runner.py" "${ROOT_DIR}/scripts/test_mac.sh" "${ROOT_DIR}/scripts/mac_unit_audit.json" \
    "${PRIVATE}/runner-snapshot/"
  runner runner-hashes --dir "${PRIVATE}/runner-snapshot" > "${PRIVATE}/runner-files.json"
  (cd "${PRIVATE}/runner-snapshot" && COPYFILE_DISABLE=1 tar -cf - mac_ui_runner.py test_mac.sh) | \
    vm_ssh "tar -xf - -C \"\$HOME/ntk/runs/${RUN_ID}/runner\""
  echo "[vm] handed over $(tr -cd '\0' < "${list}" | wc -c | tr -d ' ') files of mac/ and the runner"
  rm -f "${list}"
}

vm_send_plan() {
  vm_ssh "cat > \"\$HOME/ntk/runs/${RUN_ID}/plan.json\"" < "$1"
}

vm_enumeration() {  # <HEAD> <mac tree>: 6.3 steps 0-3 in the VM: qualification, hand-over, build, both enumerations
  local head="$1" mac_tree="$2"
  vm_qualify
  vm_push
  # The copy the VM builds is the tree the plan and the baseline name (review v3: Codex A-4).
  [[ "$(vm_op tree-hash "${RUN_ID}")" == "${mac_tree}" && "$(git -C "${ROOT_DIR}" rev-parse HEAD)" == "${head}" ]] \
    || fail "mac/ changed while it was handed to the VM; run again"
  runner runner-hashes-match --vm "$(vm_op runner-hashes "${RUN_ID}")" --snapshot "${PRIVATE}/runner-files.json" \
    || fail "the VM's copy of the runner is not the snapshot handed over; run again"
  vm_op clean "${RUN_ID}" | grep '^NTK-VM' | sed 's/^/  /'
  echo "[vm] building (Xcode 26.3, ad-hoc)"
  vm_op build "${RUN_ID}" | sed 's/^/  /'
  vm_op enumerate "${RUN_ID}" > "${OUT}/enumeration.json"
  vm_op enumerate-lib "${RUN_ID}" > "${OUT}/unit-enumeration.json"
}

# Adds a failed record for a call that gave none (Codex A-7, Claude A-4).
no_result() {  # <test key with #>
  echo "{\"test\": \"$1#noResult\", \"result\": \"failed\", \"codes\": [\"NTK-RUNNER:noResult\"]}" | runner accept --results "${RESULTS}"
}

# --- The VM way --------------------------------------------------------------------------------

run_vm() {
  local head mac_tree index stage name timeout prepare after class stopped="" restarts=0 rc status passed
  local plan="${OUT}/plan.json" count target
  runner check-sources --tests-dir "${TESTS_DIR}" --pbxproj "${PBXPROJ}"
  head="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
  mac_tree="$(runner tree-hash --repo "${ROOT_DIR}")"
  if [[ "${BASELINE}" == 1 && -n "$(git -C "${ROOT_DIR}" status --porcelain=v1 -uall -- mac | grep -v ' mac/MacLibraryExample/build/' || true)" ]]; then
    fail "--baseline needs mac/ without uncommitted changes"
  fi
  vm_enumeration "${head}" "${mac_tree}"
  IFS=$'\t' read -r VM_OS_VERSION VM_OS_BUILD VM_ARCH VM_LANGUAGE VM_XCODE <<< "${VM_OS}"
  runner preflight --where vm --enumeration "${OUT}/enumeration.json" --unit-enumeration "${OUT}/unit-enumeration.json" \
    --tests-dir "${TESTS_DIR}" --repo "${ROOT_DIR}" --feature "${FEATURE}" --qualification "${QUALIFICATION}" \
    --os-major "${VM_OS_VERSION%%.*}" --os-version "${VM_OS_VERSION}" --os-build "${VM_OS_BUILD}" --xcode "${VM_XCODE}" \
    --head "${head}" --mac-tree "${mac_tree}" --unit "${UNIT}" --plan "${plan}" --baseline-dir "${BASELINE_DIR}" \
    --runner-files "${PRIVATE}/runner-files.json" $([[ "${NAME_EACH_TEST}" == 1 ]] && echo --name-each-test) $([[ "${BASELINE}" == 1 ]] && echo --baseline)
  vm_send_plan "${plan}"
  vm_op check-build "${RUN_ID}" | sed 's/^/  /'
  vm_op prepare "${RUN_ID}" | grep '^NTK-VM' | sed 's/^/  /'
  # Unit tests (6.3 step 5).
  count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["unitInvocations"]))' "${plan}")"
  for ((index = 0; index < count; index++)); do
    echo "[unit] ${index}"
    rc=0; vm_op unit "${RUN_ID}" "${index}" > "${PRIVATE}/unit.out" || rc=$?
    [[ "${rc}" != 96 ]] || fail "the VM is not the one that was qualified"
    json_lines "${PRIVATE}/unit.out" | runner accept --results "${RESULTS}"
    if [[ "${rc}" != 0 || -z "$(json_lines "${PRIVATE}/unit.out")" ]]; then
      target="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["unitInvocations"][int(sys.argv[2])]["target"])' "${plan}" "${index}")"
      no_result "${target}"
    fi
  done
  # The permission stage, the classes, the paste privacy stage (6.3 steps 6-8).
  while IFS=$'\t' read -r index stage name timeout prepare after class; do
    [[ -z "${stopped}" ]] || continue
    if [[ ",${prepare}," == *,privacy,* ]]; then
      vm_op privacy-begin "${RUN_ID}" | sed 's/^/  /'
    fi
    echo "[ui ${index}] ${stage} ${name}"
    rc=0; vm_op ui "${RUN_ID}" "${index}" > "${PRIVATE}/ui.out" || rc=$?
    grep '^NTK-VM' "${PRIVATE}/ui.out" | sed 's/^/  /' || true
    restarts=$((restarts + $(grep -c '^NTK-VM restart' "${PRIVATE}/ui.out" || true)))
    json_lines "${PRIVATE}/ui.out" | runner accept --results "${RESULTS}"
    status="$(json_lines "${PRIVATE}/ui.out" | grep -c '"result": "failed"' || true)"
    passed="$(json_lines "${PRIVATE}/ui.out" | grep -c '"result": "passed"' || true)"
    if [[ ",${prepare}," == *,privacy,* ]]; then
      vm_op privacy-end "${RUN_ID}" | runner accept --results "${RESULTS}"
    fi
    [[ "${rc}" != 96 ]] || fail "the VM is not the one that was qualified"
    if [[ "${rc}" != 0 || "$((status + passed))" == 0 ]]; then
      # The call gave no result: its tests and the rest count as failures, nothing more runs.
      echo "[stop] call ${index} returned no result; the remaining UI tests are not run"
      runner not-run --plan "${plan}" --from-index "${index}" --kind runStopped | runner accept --results "${RESULTS}"
      stopped=noResult
    elif [[ "${stage}" == watch && ( "${status}" != 0 || "${passed}" != 1 ) ]]; then
      # U-20: the watch did not pass exactly once; the rest of the UI tests do not run and count as failures.
      echo "[watch] the watch N4 failed: the premise or the banner path does not hold; the remaining UI tests are not run"
      runner not-run --plan "${plan}" --from-index "$((index + 1))" --kind watchStopped | runner accept --results "${RESULTS}"
      stopped=watch
    fi
  done < <(runner invocations --plan "${plan}")
  if [[ -z "${FEATURE}" && -z "${QUALIFICATION}" && -z "${stopped}" ]]; then
    vm_op coverage "${RUN_ID}" | runner accept --results "${RESULTS}"
  fi
  VM_FINISHED=1
  vm_op finish "${RUN_ID}" "${KEEP_VM_RUN}" > "${PRIVATE}/finish.out" || true
  grep '^NTK-VM' "${PRIVATE}/finish.out" | sed 's/^/  /' || true
  json_lines "${PRIVATE}/finish.out" | runner accept --results "${RESULTS}"
  python3 - "${OUT}/environment.json" "${OUT}/vm-qualification.json" "${VM_OS_VERSION}" "${VM_OS_BUILD}" "${VM_ARCH}" \
    "${VM_LANGUAGE}" "${VM_XCODE}" "${restarts}" <<'PY'
import json, sys
q = json.load(open(sys.argv[2]))
q["notificationUIRestarts"] = int(sys.argv[8])
env = {"where": "vm", "os": sys.argv[3], "osBuild": sys.argv[4], "arch": sys.argv[5], "language": sys.argv[6],
       "xcode": sys.argv[7], "signing": "adhoc", "vm": q}
json.dump(env, open(sys.argv[1], "w"), indent=2)
PY
  echo "[vm] notification UI restarts: ${restarts}"
  local code=0
  runner summary --plan "${plan}" --environment "${OUT}/environment.json" --results "${RESULTS}" \
    --baseline-dir "${BASELINE_DIR}" --repo "${ROOT_DIR}" $([[ "${BASELINE}" == 1 ]] && echo --save-baseline) || code=$?
  echo "[out] the public results: mac/MacLibraryExample/build/test_mac/${RUN_ID}-vm/"
  return "${code}"
}

# --- This Mac ------------------------------------------------------------------------------------

MAC_PIDFILE=""; MAC_STOPFILE=""

# Before any xcodebuild on this Mac: the approved plan, the ledger, the runner and the tree (R-19).
mac_gate() {
  runner gate --plan "${MAC_TMP}/plan.approved.json" --approved "${MAC_TMP}/approval.approved.json" --repo "${ROOT_DIR}" \
    || exit 97
}

# Runs one xcodebuild on this Mac: the gate, then the call's own paths and names (Claude A-1, Codex A-2),
# then the call in its own group with nothing from outside in its environment (Codex A-3). Its PID,
# start time, real executable and group go into the run's marker once it is the Xcode 26.6 xcodebuild;
# if that cannot be recorded, the call is stopped and the run fails (Claude B-4). The next call starts only
# after perl reaped this one and nothing of its group runs (review v5: Codex A-2).
mac_xcodebuild() {  # <seconds> <log> <build|unit|ui> <index> <xcodebuild arguments...>
  local seconds="$1" log="$2" kind="$3" index="$4"; shift 4
  mac_gate
  runner check-call --plan "${MAC_TMP}/plan.approved.json" --root "${MAC_TMP}" --kind "${kind}" --index "${index}" "$@" \
    || exit 97
  rm -f "${MAC_PIDFILE}" "${MAC_STOPFILE}"
  # The marker says an xcodebuild is starting until it is recorded; with the pid file left in the folder,
  # a later run can still show whether it runs (review v4: Codex A-2; v5: Claude C-3).
  runner marker --root "${MAC_TMP}" --launching || fail "the run's marker could not be written; nothing was started"
  # Only what the run sets reaches xcodebuild (Claude v2 C-2): an empty environment with HOME, USER,
  # LOGNAME, TMPDIR, a fixed PATH, the Xcode, and the runner's TEST_RUNNER_NTK_ values.
  local environment=(HOME="${HOME}" USER="${USER:-}" LOGNAME="${LOGNAME:-}" TMPDIR="${MAC_TMP}/tmp/"
    PATH=/usr/bin:/bin:/usr/sbin:/sbin DEVELOPER_DIR="${MAC_XCODE_DIR}") name
  for name in TEST_RUNNER_NTK_HOST TEST_RUNNER_NTK_ALLOW TEST_RUNNER_NTK_FIXTURE_DIR TEST_RUNNER_NTK_EXPECTED_COPY; do
    [[ -n "${!name+set}" ]] && environment+=("${name}=${!name}")
  done
  /usr/bin/perl -e "${CAPPED_PERL}" "${seconds}" "${MAC_PIDFILE}" "${MAC_STOPFILE}" /usr/bin/env -i "${environment[@]}" \
    "${MAC_XCODE_DIR}/usr/bin/xcodebuild" "$@" < /dev/null > "${log}" 2>&1 &
  MAC_WAITER=$!
  local i code=0
  for i in $(seq 1 100); do [[ -s "${MAC_PIDFILE}" ]] && break; sleep 0.1; done
  if ! { [[ -s "${MAC_PIDFILE}" ]] && runner marker --root "${MAC_TMP}" --pid "$(cat "${MAC_PIDFILE}")" \
           --role xcodebuild --expect-under "$(cd -P "${MAC_XCODE_DIR}" && pwd -P)"; }; then
    stop_waiter
    fail "the xcodebuild could not be recorded as a writer; stopped"
  fi
  wait "${MAC_WAITER}" || code=$?
  MAC_WAITER=""
  runner settle --root "${MAC_TMP}" || exit 1
  rm -f "${MAC_PIDFILE}"
  return "${code}"
}

# Asks the background perl of the current xcodebuild to stop its group, and waits for it. The shell never
# signals a number (review v5: Codex A-3): it makes the stop file perl polls, and perl, which has not
# reaped its child, stops the group itself. The EXIT trap comes here first too (through mac_cleanup).
stop_waiter() {
  [[ -n "${MAC_WAITER}" ]] || return 0
  : > "${MAC_STOPFILE}"
  wait "${MAC_WAITER}" 2>/dev/null || true
  MAC_WAITER=""
}

# The end of a run on this Mac (6.3 step 4): perl stops and reaps the current xcodebuild; then, only when
# nothing of the run runs, this run's registrations, fixture and folder go. Nothing is signalled; if
# something runs, or that cannot be shown, the folder stays and the run fails (Codex A-4, review v5).
mac_cleanup() {
  [[ -n "${MAC_TMP}" && -d "${MAC_TMP}" ]] || return 0
  stop_waiter
  runner stop-current --root "${MAC_TMP}"
}

# Reads the -only-testing arguments of a call into ONLY_TESTING; a failed or empty lookup stops.
read_only_testing() {  # <only-testing arguments of the runner...>
  local out line
  out="$(runner only-testing --plan "${MAC_TMP}/plan.approved.json" "$@")" || fail "the planned names could not be read"
  ONLY_TESTING=()
  while IFS= read -r line; do [[ -n "${line}" ]] && ONLY_TESTING+=("${line}"); done <<< "${out}"
  [[ ${#ONLY_TESTING[@]} -gt 0 ]] || fail "no planned names; not running anything"
}

run_mac() {
  local head mac_tree os_version os_build xcode plan="${OUT}/plan.json" approval_out="${OUT}/approval.json"
  local lsreg="${PRIVATE}/lsregister.json" stale="${PRIVATE}/stale.json"
  # Step 0: read-only checks of this Mac.
  os_version="$(sw_vers -productVersion)"; os_build="$(sw_vers -buildVersion)"
  [[ "${os_version%%.*}" == 26 ]] || fail "this Mac is not macOS 26"
  [[ -d "${MAC_XCODE_DIR}" ]] || fail "Xcode 26.6 is not at /Applications/Xcode26.6.app (U-23)"
  xcode="$(DEVELOPER_DIR="${MAC_XCODE_DIR}" xcodebuild -version | awk 'NR==1{print $2}')"
  runner check-sources --tests-dir "${TESTS_DIR}" --pbxproj "${PBXPROJ}"
  head="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
  mac_tree="$(runner tree-hash --repo "${ROOT_DIR}")"
  # Step 1: the enumeration comes from the VM (the same tree).
  vm_enumeration "${head}" "${mac_tree}"
  VM_FINISHED=1
  vm_op finish "${RUN_ID}" 0 | grep '^NTK-VM' | sed 's/^/  /' || true
  # The previous runs of this Mac (6.3 step 4) and the registered copies of the sample (U-21; only when
  # coldstart is allowed). Both read only; the raw lists stay in the private folder.
  if [[ "${DRY_RUN}" == 1 ]]; then
    runner stale --scan-root "${SCAN_ROOT}" --list --out "${stale}"
  else
    # The approved run plans with the earlier runs' folders the user saw (so a run that ended since does not
    # change the plan; review v3: Codex B-5). Those folders are never stopped: `stale --clean` removes each
    # one only where nothing of its run runs, and otherwise the run stops before it builds (review v5).
    runner approval-stale --approved "${APPROVED}" --out "${stale}"
  fi
  echo '[]' > "${lsreg}"
  if [[ ",${ALLOW}," == *,coldstart,* ]]; then
    "${LSREGISTER}" -dump > "${PRIVATE}/lsregister.txt" 2>/dev/null || true
    runner lsregister --dump "${PRIVATE}/lsregister.txt" --repo-root "${ROOT_DIR}" \
      --derived-root "${ACCOUNT_HOME}/Library/Developer/Xcode/DerivedData" --out "${lsreg}"
    rm -f "${PRIVATE}/lsregister.txt"
  fi
  local preflight=(preflight --where mac --enumeration "${OUT}/enumeration.json"
    --unit-enumeration "${OUT}/unit-enumeration.json" --tests-dir "${TESTS_DIR}" --repo "${ROOT_DIR}"
    --allow "${ALLOW}" --feature "${FEATURE}" --qualification "${QUALIFICATION}" --os-major "${os_version%%.*}"
    --os-version "${os_version}" --os-build "${os_build}" --xcode "${xcode}" --head "${head}" --mac-tree "${mac_tree}"
    --unit "${UNIT}" --plan "${plan}" --baseline-dir "${BASELINE_DIR}" --lsregister "${lsreg}" --stale "${stale}"
    --runner-files "${PRIVATE}/runner-files.json")
  [[ "${BASELINE}" == 1 ]] && preflight+=(--baseline)
  if [[ "${DRY_RUN}" == 1 ]]; then
    runner "${preflight[@]}" --dry-run --approval-out "${approval_out}"
    if [[ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "${lsreg}")" != 0 ]]; then
      echo "[dry-run] coldstart: extra copies are registered; the run will stop until you remove them yourself (--allow-lsregister is not implemented)"
    fi
    echo "[dry-run] the approval list: mac/MacLibraryExample/build/test_mac/${RUN_ID}-mac/approval.json"
    return 0
  fi
  [[ -f "${APPROVED}" ]] || fail "the approval file does not exist or cannot be read"
  runner "${preflight[@]}" > /dev/null
  runner approve --plan "${plan}" --approved "${APPROVED}" --repo "${ROOT_DIR}"
  # Step 4: the private run folder and its marker before the first xcodebuild (the EXIT trap is set
  # above and reaches mac_cleanup once MAC_TMP is set).
  # The folder, its marker (naming the consumed approval) and the read-only copies of the plan and the
  # approval are made complete under another name and then renamed (Claude v2 B-3, Codex v3 B-3).
  MAC_TMP="$(umask 077; runner make-run-folder --scan-root "${SCAN_ROOT}" --run-id "${RUN_ID}" --approved "${APPROVED}" \
    --plan "${plan}")"
  MAC_PIDFILE="${MAC_TMP}/xcodebuild.pid"; MAC_STOPFILE="${MAC_TMP}/xcodebuild.stop"
  plan="${MAC_TMP}/plan.approved.json"
  # The folders of earlier runs go only where nothing of their run runs; nothing is stopped, and the run
  # stops here (before it builds) while any of them stays (review v5).
  runner stale --scan-root "${SCAN_ROOT}" --current-root "${MAC_TMP}" --clean --plan "${plan}" \
    --approved "${MAC_TMP}/approval.approved.json" --repo "${ROOT_DIR}"
  # The sources this Mac builds are the same list the VM got, copied into the run folder, and must hash
  # to the approved tree (Claude B-12: nothing git ignores, such as a user scheme in xcuserdata).
  runner file-list --repo "${ROOT_DIR}" > "${PRIVATE}/files"
  mkdir "${MAC_TMP}/src"
  (cd "${ROOT_DIR}" && COPYFILE_DISABLE=1 tar --null -T "${PRIVATE}/files" -cf -) | tar -xf - -C "${MAC_TMP}/src"
  [[ "$(runner tree-hash --dir "${MAC_TMP}/src")" == "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["macTree"])' "${plan}")" ]] \
    || fail "the copied sources differ from the approved tree"
  # The names in $TMPDIR before the run (names only, kept private), to count what Xcode leaves there
  # (review v3: Claude B-1). xcodebuild itself gets a TMPDIR inside the run folder.
  runner tmp-names --dir "${SCAN_ROOT}" --out "${MAC_TMP}/tmp-before.json"
  # Step 5: the build of this Mac (Xcode 26.6, the project's automatic signing; U-23, U-31).
  echo "[mac] building (Xcode 26.6)"
  mac_xcodebuild 2400 "${MAC_TMP}/build-ui.log" build 0 build-for-testing \
    -workspace "${MAC_TMP}/src/mac/MacWorkspace.xcworkspace" -scheme MacLibraryExample -destination "${DESTINATION}" \
    -derivedDataPath "${MAC_TMP}/dd-ui" || fail "the build failed (the log stays private)"
  local products="${MAC_TMP}/dd-ui/Build/Products/Debug" binary
  binary="${products}/${UI_XCTEST_BINARY}"
  DEVELOPER_DIR="${MAC_XCODE_DIR}" xcrun otool -arch arm64 -ov "${binary}" > "${MAC_TMP}/otool-ov.txt"
  DEVELOPER_DIR="${MAC_XCODE_DIR}" xcrun otool -arch arm64 -l "${binary}" > "${MAC_TMP}/otool-l.txt"
  runner check-build --products "${products}" --tests-dir "${TESTS_DIR}" --enumeration "${OUT}/enumeration.json" \
    --otool-objc "${MAC_TMP}/otool-ov.txt" --otool-load "${MAC_TMP}/otool-l.txt"
  # Step 6: coldstart counts the registered copies again; any is a stop (U-21).
  if [[ ",${ALLOW}," == *,coldstart,* ]]; then
    "${LSREGISTER}" -dump > "${MAC_TMP}/lsregister.txt" 2>/dev/null || true
    runner lsregister --dump "${MAC_TMP}/lsregister.txt" --run-root "${MAC_TMP}" --repo-root "${ROOT_DIR}" \
      --derived-root "${ACCOUNT_HOME}/Library/Developer/Xcode/DerivedData" --out "${MAC_TMP}/lsregister.json"
    [[ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "${MAC_TMP}/lsregister.json")" == 0 ]] \
      || fail "extra registered copies of the sample; not running coldstart (U-21)"
  fi
  # Step 7: the fixture (panels), made anew without following links (U-11).
  local fx="/private/tmp/ntk-uitest-${RUN_ID}"
  if [[ ",${ALLOW}," == *,panels,* ]]; then
    runner fixture-create --dir "${fx}"
    runner fixture-manifest --dir "${fx}" > "${MAC_TMP}/fixture-before.json"
  fi
  local expected_copy xctestrun
  expected_copy="$(runner copy-mark --app "${products}/MacLibraryExample.app")"
  xctestrun="$(ls "${MAC_TMP}"/dd-ui/Build/Products/*.xctestrun)"
  # Step 8: the audited unit tests only (U-29).
  local count index code
  count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["unitInvocations"]))' "${plan}")"
  if [[ "${count}" != 0 ]]; then
    mac_xcodebuild 2400 "${MAC_TMP}/build-lib.log" build 0 build-for-testing \
      -workspace "${MAC_TMP}/src/mac/MacWorkspace.xcworkspace" -scheme MacLibrary -destination "${DESTINATION}" \
      -derivedDataPath "${MAC_TMP}/dd-lib" || fail "the library build failed"
    for ((index = 0; index < count; index++)); do
      code=0
      read_only_testing --unit "${index}"
      mac_xcodebuild 1800 "${MAC_TMP}/unit-${index}.log" unit "${index}" test-without-building \
        -xctestrun "$(ls "${MAC_TMP}"/dd-lib/Build/Products/*.xctestrun)" -destination "${DESTINATION}" \
        "${ONLY_TESTING[@]}" -derivedDataPath "${MAC_TMP}/dd-test" -resultBundlePath "${MAC_TMP}/unit-${index}.xcresult" \
        -collect-test-diagnostics never || code=$?
      DEVELOPER_DIR="${MAC_XCODE_DIR}" xcrun xcresulttool get test-results tests --path "${MAC_TMP}/unit-${index}.xcresult" \
        > "${MAC_TMP}/unit-${index}-tests.json" 2>/dev/null || rm -f "${MAC_TMP}/unit-${index}-tests.json"
      DEVELOPER_DIR="${MAC_XCODE_DIR}" xcrun xcresulttool get test-results summary --path "${MAC_TMP}/unit-${index}.xcresult" \
        > "${MAC_TMP}/unit-${index}-summary.json" 2>/dev/null || rm -f "${MAC_TMP}/unit-${index}-summary.json"
      runner unit-record --plan "${plan}" --index "${index}" --tests-json "${MAC_TMP}/unit-${index}-tests.json" \
        --summary-json "${MAC_TMP}/unit-${index}-summary.json" --exit-code "${code}" --tests-dir "${TESTS_DIR}" \
        | runner accept --results "${RESULTS}"
    done
  fi
  # Step 9: the UI tests one by one; the watch first; a notification test that fails stops the rest.
  local stage name timeout prepare after class stop_kind="" timed_out rcode
  while IFS=$'\t' read -r index stage name timeout prepare after class; do
    [[ -z "${stop_kind}" ]] || continue
    echo "[ui ${index}] ${name}"
    code=0; timed_out=0
    read_only_testing --index "${index}"
    TEST_RUNNER_NTK_HOST=mac TEST_RUNNER_NTK_ALLOW="${ALLOW}" TEST_RUNNER_NTK_FIXTURE_DIR="${fx}" \
    TEST_RUNNER_NTK_EXPECTED_COPY="${expected_copy}" \
      mac_xcodebuild "${timeout}" "${MAC_TMP}/ui-${index}.log" ui "${index}" test-without-building -xctestrun "${xctestrun}" \
      -destination "${DESTINATION}" "${ONLY_TESTING[@]}" -derivedDataPath "${MAC_TMP}/dd-test" \
      -resultBundlePath "${MAC_TMP}/ui-${index}.xcresult" "${TIME_FLAGS[@]}" -collect-test-diagnostics never || code=$?
    [[ "${code}" == 142 ]] && timed_out=1
    DEVELOPER_DIR="${MAC_XCODE_DIR}" xcrun xcresulttool get test-results tests --path "${MAC_TMP}/ui-${index}.xcresult" \
      > "${MAC_TMP}/ui-${index}-tests.json" 2>/dev/null || rm -f "${MAC_TMP}/ui-${index}-tests.json"
    DEVELOPER_DIR="${MAC_XCODE_DIR}" xcrun xcresulttool get test-results summary --path "${MAC_TMP}/ui-${index}.xcresult" \
      > "${MAC_TMP}/ui-${index}-summary.json" 2>/dev/null || rm -f "${MAC_TMP}/ui-${index}-summary.json"
    rcode=0
    runner record --plan "${plan}" --index "${index}" --tests-json "${MAC_TMP}/ui-${index}-tests.json" \
      --summary-json "${MAC_TMP}/ui-${index}-summary.json" --exit-code "${code}" --timed-out "${timed_out}" \
      --tests-dir "${TESTS_DIR}" > "${MAC_TMP}/ui-${index}.records" || rcode=$?
    runner accept --results "${RESULTS}" < "${MAC_TMP}/ui-${index}.records"
    rm -rf "${MAC_TMP}/ui-${index}.xcresult" "${MAC_TMP}/ui-${index}-tests.json" "${MAC_TMP}/ui-${index}-summary.json"
    [[ "${rcode}" == 0 ]] || fail "the results are not exactly the named tests; stopping (design 6.3 step 9)"
    if grep -q '"result": "failed"' "${MAC_TMP}/ui-${index}.records" || \
       { [[ "${stage}" == watch ]] && [[ "$(grep -c '"result": "passed"' "${MAC_TMP}/ui-${index}.records" || true)" != 1 ]]; }; then
      if [[ "${stage}" == watch ]]; then stop_kind=watchStopped
      elif [[ "${class}" == Notification* ]]; then stop_kind=notificationStopped; fi
      if [[ -n "${stop_kind}" ]]; then
        echo "[stop] ${stop_kind}: Notification Center may still be open; close it, then plan and ask again for the rest"
        runner not-run --plan "${plan}" --from-index "$((index + 1))" --kind "${stop_kind}" | runner accept --results "${RESULTS}"
      fi
    fi
  done < <(runner invocations --plan "${plan}")
  # Step 10: the fixture, what is left on this Mac, the summary.
  runner tmp-names --dir "${SCAN_ROOT}" --compare "${MAC_TMP}/tmp-before.json"
  if [[ -f "${MAC_TMP}/fixture-before.json" ]]; then
    runner fixture-manifest --dir "${fx}" > "${MAC_TMP}/fixture-after.json"
    runner fixture-compare --before "${MAC_TMP}/fixture-before.json" --after "${MAC_TMP}/fixture-after.json" \
      | runner accept --results "${RESULTS}"
  fi
  echo "[mac] left on this Mac: the test strings on the pasteboard (clipboard), the category sample-category and badge 0"
  echo "      (notification, badge), System Settings or Finder brought to the front. The run's own registrations, fixture"
  echo "      and private folder are removed at the end when nothing of the run is shown running; otherwise they stay"
  echo "      and the run says what still runs (NTK-STALE:alive)"
  python3 - "${OUT}/environment.json" "${os_version}" "${os_build}" "$(uname -m)" \
    "$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | tr -d ' ",')" "${xcode}" <<'PY'
import json, sys
env = {"where": "mac", "os": sys.argv[2], "osBuild": sys.argv[3], "arch": sys.argv[4], "language": sys.argv[5],
       "xcode": sys.argv[6], "signing": "team"}
json.dump(env, open(sys.argv[1], "w"), indent=2)
PY
  code=0
  runner summary --plan "${plan}" --environment "${OUT}/environment.json" --results "${RESULTS}" \
    --baseline-dir "${BASELINE_DIR}" --repo "${ROOT_DIR}" --approved "${MAC_TMP}/approval.approved.json" \
    $([[ "${BASELINE}" == 1 ]] && echo --save-baseline) || code=$?
  return "${code}"
}

# The one EXIT trap of a run (set in main).
on_exit() {
  local code=$?
  trap - EXIT INT TERM HUP
  if [[ -n "${MAC_TMP}" ]]; then
    mac_cleanup || code=1
  fi
  if [[ -n "${VM_UUID}" && "${VM_FINISHED}" != 1 ]]; then
    VM_FINISHED=1
    vm_op finish "${RUN_ID}" "${KEEP_VM_RUN}" 2>/dev/null | grep '^NTK-VM' | sed 's/^/  /' || true
  fi
  rm -rf "${PRIVATE}"
  exit "${code}"
}

# What runs on this Mac: the options, the private folder and its trap, then the VM's or this Mac's run.
main() {
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  MAC_DIR="${ROOT_DIR}/mac"
  TESTS_DIR="${MAC_DIR}/MacLibraryExample/MacLibraryExampleUITests"
  PBXPROJ="${MAC_DIR}/MacLibraryExample/MacLibraryExample.xcodeproj/project.pbxproj"
  OUT_ROOT="${MAC_DIR}/MacLibraryExample/build/test_mac"
  BASELINE_DIR="${ROOT_DIR}/scripts"
  ACCOUNT_HOME="$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
  VM_KEYS="${ACCOUNT_HOME}/.tart/ntk-ssh"
  MAC_XCODE_DIR="/Applications/Xcode26.6.app/Contents/Developer"

  runner() { python3 "${ROOT_DIR}/scripts/mac_ui_runner.py" "$@"; }
  fail() { echo "Error: $*" >&2; exit 1; }

  WHERE=""; VM_NAME="ntk-macos-15-new"; FEATURE=""; SKIP_UNIT=0; ALLOW=""; ALLOW_LSREGISTER=0; DRY_RUN=0; APPROVED=""
  BASELINE=0; NAME_EACH_TEST=0; QUALIFICATION=""; KEEP_VM_RUN=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --where) WHERE="${2:-}"; shift 2 ;;
      --vm) VM_NAME="${2:-}"; shift 2 ;;
      --feature) FEATURE="${2:-}"; shift 2 ;;
      --skip-unit) SKIP_UNIT=1; shift ;;
      --allow) ALLOW="${2-}"; shift 2 ;;
      --allow-lsregister) ALLOW_LSREGISTER=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --approved) APPROVED="${2:-}"; shift 2 ;;
      --baseline) BASELINE=1; shift ;;
      --name-each-test) NAME_EACH_TEST=1; shift ;;
      --qualification) QUALIFICATION="${2:-}"; shift 2 ;;
      --keep-vm-run) KEEP_VM_RUN=1; shift ;;
      *) fail "unknown option $1 (see the header of scripts/test_mac.sh)" ;;
    esac
  done

  [[ "${WHERE}" == vm || "${WHERE}" == mac ]] || fail "--where vm|mac is required (design 6.3)"
  [[ "${VM_NAME}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "malformed --vm"
  case "${FEATURE}" in ""|Dialog|Notification|Share|Clipboard) ;; *) fail "--feature must be Dialog, Notification, Share or Clipboard" ;; esac
  case "${QUALIFICATION}" in ""|mac26|mac26-reply|vm-ja) ;; *) fail "--qualification must be mac26, mac26-reply or vm-ja" ;; esac
  if [[ "${WHERE}" == vm ]]; then
    [[ -z "${ALLOW}" && "${ALLOW_LSREGISTER}" == 0 && "${DRY_RUN}" == 0 && -z "${APPROVED}" ]] || \
      fail "--allow, --allow-lsregister, --dry-run and --approved are for --where mac"
    [[ -z "${QUALIFICATION}" || "${QUALIFICATION}" == vm-ja ]] || fail "--qualification ${QUALIFICATION} runs on this Mac"
  else
    [[ "${NAME_EACH_TEST}" == 0 && "${KEEP_VM_RUN}" == 0 ]] || fail "--name-each-test and --keep-vm-run are for --where vm"
    [[ -z "${QUALIFICATION}" || "${QUALIFICATION}" != vm-ja ]] || fail "--qualification vm-ja runs in the VM"
    [[ "${ALLOW_LSREGISTER}" == 0 ]] || fail "--allow-lsregister is not implemented: remove the extra registered copies yourself, then plan and ask again"
    if [[ "${DRY_RUN}" == 1 ]]; then
      [[ -z "${APPROVED}" ]] || fail "--dry-run and --approved go to separate runs"
    else
      [[ -n "${APPROVED}" ]] || fail "this Mac runs only with --approved <file> (run --dry-run first and ask the user)"
      # Its place is never shown (design 3.4; review v4: Codex A-1); every read of it is the runner's.
      [[ -f "${APPROVED}" && -r "${APPROVED}" ]] || fail "the approval file does not exist or cannot be read"
    fi
  fi
  [[ -z "${FEATURE}" ]] || SKIP_UNIT=1
  UNIT=1; [[ "${SKIP_UNIT}" == 1 ]] && UNIT=0
  [[ -n "${QUALIFICATION}" ]] && UNIT=0

  # The raw things of this run on this Mac (the VM's facts, LaunchServices dumps, the tart arguments are
  # never written at all) stay in a private temporary folder outside the repository, removed on every
  # exit (Codex A-9, Claude A-2, B-7). One EXIT trap for everything the run may leave.
  SCAN_ROOT="${TMPDIR:-/tmp}"; SCAN_ROOT="${SCAN_ROOT%/}"
  PRIVATE="$(umask 077; mktemp -d "${SCAN_ROOT}/ntk-test-mac-private.XXXXXX")"
  MAC_TMP=""; MAC_WAITER=""; VM_UUID=""; VM_BOOT=""; VM_IP=""; VM_FINISHED=0
  trap on_exit EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
  # A run killed without its trap leaves its private folder; the next run removes the ones whose owner (the
  # runner's shell, by PID and start time) is gone (Claude v2 B-3).
  runner private --dir "${PRIVATE}" --own "$$"
  runner private --scan-root "${SCAN_ROOT}" --dir "${PRIVATE}"

  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(python3 -c 'import secrets; print(secrets.token_hex(3))')"
  OUT="${OUT_ROOT}/${RUN_ID}-${WHERE}"
  mkdir -p "${OUT}"
  chmod 700 "${OUT}"
  RESULTS="${OUT}/results.jsonl"
  : > "${RESULTS}"
  echo "[run] ${RUN_ID} (${WHERE})"
  if [[ "${WHERE}" == vm ]]; then
    run_vm
  else
    run_mac
  fi
}

# The last two lines. bash reads a line whole before it runs it, and each of these ends the script, so
# nothing after them is ever read: a file changed while a run goes on (it takes long) is not read on
# (review v5: Claude B-1). The VM half runs only after the prelude above let it through.
if [[ "${1:-}" == "--in-vm-clean" ]]; then shift; in_vm_main "$@"; exit 0; fi
main "$@"; exit $?
