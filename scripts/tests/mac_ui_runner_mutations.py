"""Mutation runs of the macOS UI test runner (macOS UI test design, chapter 7: the runner's rows).

Breaks one decision at a time in a copy of the runner (scripts/mac_ui_runner.py, scripts/test_mac.sh,
the self-tests and their fixtures, the UI test folder, the sample's sources and the project file) and
runs scripts/tests/test_mac_ui_runner.py there. Every mutation must be caught; the first entry
changes nothing and must survive. Nothing runs in the VM or on this Mac's screen; the self-tests use
temporary ledgers only, and the real ledger folder is compared before and after.

Not a unit test (the name does not start with test_). Run:
    python3 scripts/tests/mac_ui_runner_mutations.py [--only <part of a title>,...]
"""

import argparse
import hashlib
import os
import pathlib
import pwd
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
M = "scripts/mac_ui_runner.py"
S = "scripts/test_mac.sh"
COPIED = ("scripts/mac_ui_runner.py", "scripts/test_mac.sh", "scripts/mac_unit_audit.json",
          "scripts/tests/test_mac_ui_runner.py", "scripts/tests/fixtures/mac_ui_runner",
          "mac/MacLibraryExample/MacLibraryExampleUITests", "mac/MacLibraryExample/MacLibraryExample",
          "mac/MacLibraryExample/MacLibraryExample.xcodeproj/project.pbxproj")
REAL_LEDGER_DIR = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library" / "Application Support" / "native-toolkit"

MUTATIONS = [
    ("baseline: no mutation (must survive)", None, None, None),
    # Pillar 1: the selection.
    ("pillar 1: all categories -> any category", M,
     "        if any(c not in allowed for c in categories):\n            return \"category\"",
     "        if all(c not in allowed for c in categories) and categories:\n            return \"category\""),
    ("pillar 1: a VM-only category selected on this Mac", M,
     "        if key in VM_ONLY_TESTS or any(c in VM_ONLY_CATEGORIES for c in categories):",
     "        if key in VM_ONLY_TESTS:"),
    ("pillar 1: VM-only categories accepted in --allow", M,
     "    if where == \"mac\" and allowed & set(VM_ONLY_CATEGORIES):", "    if False:"),
    ("pillar 1: deferred tests selected without their targets", M,
     "    if all(t in verified_targets for t in targets):", "    if True:"),
    ("pillar 1: the Reply target forgotten for N24", M,
     "(\"macDeferred\", (\"notificationMenuItem\", \"replyInBanner\")),\n    \"NotificationColdStartUITests/testNC3",
     "(\"macDeferred\", (\"notificationMenuItem\",)),\n    \"NotificationColdStartUITests/testNC3"),
    ("pillar 1: OS-only tests run on another OS", M,
     "    if key in OS_ONLY_TESTS and OS_ONLY_TESTS[key] != os_major:", "    if False:"),
    ("pillar 1: qualification probes in a normal run", M,
     "    if key in qualification_tests:\n        return \"qualificationOnly\"", "    if False:\n        return \"qualificationOnly\""),
    ("pillar 1: an empty -only-testing list", M,
     "    if not names:\n        raise RunnerError(f\"{invocation.get('name')}: refusing",
     "    if False:\n        raise RunnerError(f\"{invocation.get('name')}: refusing"),
    ("pillar 1: a class named on its own", M,
     "        if not name.startswith(UI_TARGET + \"/\") or name.count(\"/\") != 2 or not name.endswith(\"()\"):",
     "        if not name.startswith(UI_TARGET + \"/\"):"),
    ("pillar 1: the watch not first on this Mac", M,
     "    watch_first = where == \"mac\" and watch in chosen", "    watch_first = False"),
    ("pillar 1: notification tests without the watch", M,
     "            enumeration_id_from_key(WATCH_TEST) not in selected:", "            False:"),
    ("pillar 1: the second check before xcodebuild", M,
     "            problems.append(f\"{key} never runs on this Mac\")", "            pass"),
    ("pillar 1: an empty plan on this Mac", M,
     "        if not selected:\n            raise RunnerError(\"no test is selected", "        if False:\n            raise RunnerError(\"no test is selected"),
    # Pillar 2: the declarations and the sources.
    ("pillar 2: a missing declaration passes", M,
     "    if missing:\n        problems.append(f\"tests without a declaration", "    if False:\n        problems.append(f\"tests without a declaration"),
    ("pillar 2: the classes not checked", M, "    if classes != known_classes():", "    if False:"),
    ("pillar 2: class minimums not checked", M, "        if not minimum <= set(categories):", "        if False:"),
    ("pillar 2: a renamed test of a table passes", M,
     "    undeclared = sorted(table_keys() - set(declarations))", "    undeclared = []"),
    ("pillar 2: frozen methods not checked", M, "        if sorted(methods) != sorted(frozen):", "        if False:"),
    ("pillar 2: frozen files not hashed", M,
     "        if actual != expected:\n            problems.append(f\"{relative} differs from the frozen file",
     "        if False:\n            problems.append(f\"{relative} differs from the frozen file"),
    ("pillar 2: #if allowed", M,
     "ALLOWED_POUND = {\"available\",", "ALLOWED_POUND = {\"if\", \"endif\", \"else\", \"elseif\", \"available\","),
    ("pillar 2: dangerous names allowed in test files", M,
     "            if count != allowed and (count or allowed):", "            if False:"),
    ("pillar 2: identifier strings allowed in test files", M,
     "                if role == \"test\":\n                    problem(t, \"an identifier string", "                if False:\n                    problem(t, \"an identifier string"),
    ("pillar 2: a non-final test class", M,
     "        if modifiers != [\"final\"] or attributes or inherits != [\":\", BASE_CLASS]:",
     "        if inherits != [\":\", BASE_CLASS]:"),
    ("pillar 2: async tests allowed", M,
     "    shape_ok = after[:2] == [\"(\", \")\"] and (after[2] == \"{\" or after[2:4] == [\"throws\", \"{\"])",
     "    shape_ok = True"),
    ("pillar 2: an untrusted Support file allowed", M,
     "        if relative.startswith(\"Support/\") and relative not in TRUSTED_FILES:", "        if False:"),
    ("pillar 2: trusted changes not seen", M,
     "        if actual != expected:\n            changes.append", "        if False:\n            changes.append"),
    ("pillar 2: the bundled table not compared", M,
     "    return [f\"the bundled copy differs from {DECLARATIONS_FILE}: {p}\" for p in bundle_paths if file_sha256(p) != expected]",
     "    return []"),
    ("pillar 2: the binary inventory not compared", M,
     "    if only_binary or only_enumeration:", "    if False:"),
    ("pillar 2: regex literals lexed as division", M,
     "        elif c == \"/\" and _regex_may_start(tokens) and _bare_regex_end(text, i) is not None:", "        elif False:"),
    # Pillar 3: the approval.
    ("pillar 3: approval keys not compared", M,
     "    if unknown or missing:\n        problems.append(f\"the approval's keys differ", "    if False:\n        problems.append(f\"the approval's keys differ"),
    ("pillar 3: approval values not compared", M,
     "        if approval[field] != expected[field]:", "        if False:"),
    ("pillar 3: an ID used twice", M,
     "        if approval_id in ledger_ids(text):", "        if False:"),
    ("pillar 3: a broken ledger line accepted", M,
     "        if not LEDGER_LINE.match(line):\n            raise RunnerError(f\"the approval ledger has a malformed line",
     "        if False:\n            raise RunnerError(f\"the approval ledger has a malformed line"),
    ("pillar 3: a changed trusted part approved", M,
     "    if not plan[\"trustedPart\"][\"unchanged\"]:\n        problems.append(\"the trusted part changed;",
     "    if False:\n        problems.append(\"the trusted part changed;"),
    ("pillar 3: the digest leaves the invocations out", M,
     "    return sha256_bytes(json.dumps(plan, sort_keys=True,",
     "    return sha256_bytes(json.dumps({k: v for k, v in plan.items() if k != \"invocations\"}, sort_keys=True,"),
    # The VM's qualification.
    ("VM: --no-clipboard not checked", M,
     "    if \"--no-clipboard\" not in args:", "    if False:"),
    ("VM: --dir not checked", M,
     "    for flag in (\"--dir\", \"--net-bridged\"):", "    for flag in (\"--net-bridged\",):"),
    ("VM: the zsh line counted as tart", M,
     "        if not (exe.endswith(\"/tart\") or exe == \"tart\" or exe.endswith(\"/tart.app/Contents/MacOS/tart\")):",
     "        if \"tart\" not in line:"),
    ("VM: two tart runs accepted", M, "    if len(runs) != 1:", "    if not runs:"),
    ("VM: accounts not checked", M, "        (\"accountsOnlySystem\", accounts_ok),", "        (\"accountsOnlySystem\", True),"),
    ("VM: an authenticated account of any listed type", M,
     "            elif str(entry.get(\"authenticated\")) == \"1\" and not VM_ALLOWED_ACCOUNT_TYPES[kind]:", "            elif False:"),
    ("VM: the identity not bound", M,
     "        (\"identity\", isinstance(get(\"platformUUID\"), str) and",
     "        (\"identity\", True or isinstance(get(\"platformUUID\"), str) and"),
    ("VM: hv_vmm_present not checked", M, "        (\"hvVmmPresent\", get(\"hvVmmPresent\") == \"1\"),", "        (\"hvVmmPresent\", True),"),
    ("VM: the identity check removed from ssh", S,
     "[ \\\"\\$u\\\" = '${VM_UUID}' ] || { echo 'Error: the VM is not the one that was qualified' >&2; exit 96; }; $*\"",
     "$*\""),
    # The output boundary (3.4).
    ("output: any NTK-STEP passes", M,
     "        if m.group(1) in step_vocabulary_values:\n            codes.append(f\"NTK-STEP:{m.group(1)}\")",
     "        if True:\n            codes.append(f\"NTK-STEP:{m.group(1)}\")"),
    ("output: extra keys accepted", M,
     "    if not isinstance(record, dict) or not set(record) <= allowed_keys or \"test\" not in record or \"result\" not in record:",
     "    if not isinstance(record, dict) or \"test\" not in record or \"result\" not in record:"),
    ("output: any code accepted", M,
     "    if not isinstance(codes, list) or not all(isinstance(c, str) and _PUBLIC_CODE.match(c) for c in codes):",
     "    if not isinstance(codes, list):"),
    ("output: the failure text shown", M,
     "        record = {\"test\": f\"{target}/{key}\", \"result\": outcome, \"kind\": outcome, \"codes\": codes}",
     "        record = {\"test\": f\"{target}/{key}\", \"result\": outcome, \"kind\": outcome, \"codes\": codes + ([case[\"message\"]] if case[\"message\"] else [])}"),
    # Results.
    ("results: duplicates ignored", M,
     "    if duplicates(result_keys):\n        problems.append", "    if False:\n        problems.append"),
    ("results: missing names ignored", M,
     "    if missing:\n        problems.append(f\"named but not in the results", "    if False:\n        problems.append(f\"named but not in the results"),
    ("results: unknown children trusted", M,
     "        if case[\"unknownShape\"]:\n            pseudo(\"unknownShape\")", "        if False:\n            pseudo(\"unknownShape\")"),
    ("results: a gated skip passes", M,
     "        if \"NTK-GATED:\" in reason or \"NTK-PRECONDITION:\" in reason:\n            return \"failed\"",
     "        if \"NTK-GATED:\" in reason or \"NTK-PRECONDITION:\" in reason:\n            return \"skipped\""),
    ("results: any skip passes", M, "                return \"skipped\"\n        return \"failed\"", "                return \"skipped\"\n        return \"skipped\""),
    ("results: the summary not compared", M,
     "    if summary_text is None or summary_problems(summary_text, cases):", "    if summary_text is None:"),
    ("results: not-run tests count as passed", M,
     "    return [public_record({\"test\": f\"{UI_TARGET}/{k}\", \"result\": \"failed\", \"kind\": kind",
     "    return [public_record({\"test\": f\"{UI_TARGET}/{k}\", \"result\": \"passed\", \"kind\": kind"),
    # The stopped run.
    ("stale: the executable not compared (a)", M,
     "        return p.get(\"pid\") == w.get(\"pid\") and p.get(\"start\") == w.get(\"start\") and p.get(\"exe\") == w.get(\"exe\") \\",
     "        return p.get(\"pid\") == w.get(\"pid\") and p.get(\"start\") == w.get(\"start\") \\"),
    ("stale: the start time not compared (b)", M,
     "        return p.get(\"pid\") == w.get(\"pid\") and p.get(\"start\") == w.get(\"start\") and p.get(\"exe\") == w.get(\"exe\") \\",
     "        return p.get(\"pid\") == w.get(\"pid\") and p.get(\"exe\") == w.get(\"exe\") \\"),
    ("stale: an earlier boot signalled (c)", M,
     "    if boot < boottime_now:\n        return {\"removeOnly\": True", "    if False:\n        return {\"removeOnly\": True"),
    ("stale: the group's members not checked (d)", M,
     "        if leader_ok and members_ok:", "        if leader_ok:"),
    ("stale: the woken sample not found (e)", M,
     "        elif _under(p.get(\"exe\"), root) and isinstance(p.get(\"start\"), (int, float)) and p[\"start\"] >= created:",
     "        elif False:"),
    ("stale: removed without stopping", M,
     "            if plan[\"group\"] is not None:\n                _signal_group(plan[\"group\"], 15)\n            for pid in plan[\"signal\"]:\n                _signal(pid, 15)",
     "            break"),
    # The order of the shell (design 7 "中断").
    ("shell: the trap after the first xcodebuild", S,
     "  trap mac_cleanup EXIT\n  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP\n  runner marker",
     "  runner marker"),
    ("shell: HUP not trapped", S,
     "  trap mac_cleanup EXIT\n  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP\n  runner marker",
     "  trap mac_cleanup EXIT\n  trap 'exit 130' INT; trap 'exit 143' TERM\n  runner marker"),
    ("shell: the folder removed before the children stop", S,
     "  if [[ -n \"${MAC_TMP}\" && -d \"${MAC_TMP}\" ]]; then\n    if [[ -s \"${MAC_PIDFILE}\" ]]; then",
     "  if [[ -n \"${MAC_TMP}\" && -d \"${MAC_TMP}\" ]]; then\n    rm -rf \"${MAC_TMP}\"\n    if [[ -s \"${MAC_PIDFILE}\" ]]; then"),
    ("shell: an xcodebuild without the gate", S,
     "  local seconds=\"$1\" log=\"$2\"; shift 2\n  mac_gate\n", "  local seconds=\"$1\" log=\"$2\"; shift 2\n"),
    ("shell: the in-VM half without the VM check", S,
     "  [[ \"$(sysctl -n kern.hv_vmm_present 2>/dev/null)\" == \"1\" ]] || { echo \"Error: --in-vm runs only in the VM\" >&2; exit 96; }\n",
     ""),
    # The audit (U-29).
    ("audit: allowed occurrences not compared", M,
     "        if counts != allowed:", "        if False:"),
    ("audit: .general not counted", M,
     "AUDIT_WORDS = (\"NSPasteboard.general\", \".general\",", "AUDIT_WORDS = (\"NSPasteboard.general\","),
    ("audit: no review needed", M,
     "    expired = audit.get(\"treeHash\") != current_tree_hash or not audit.get(\"review\")",
     "    expired = audit.get(\"treeHash\") != current_tree_hash"),
    ("audit: the tree not compared", M,
     "    expired = audit.get(\"treeHash\") != current_tree_hash or not audit.get(\"review\")",
     "    expired = not audit.get(\"review\")"),
    # U-30: classify_reply_state.
    ("reply: the banner-sized precondition dropped", M,
     "    if len(before) != 1 or len(holding_before) != 1 or not _contains(bound, holding_before[0]):",
     "    if len(before) != 1 or len(holding_before) != 1:"),
    ("reply: an added window not the list", M,
     "    if len(after) > len(before):\n        return \"list\"", "    if False:\n        return \"list\""),
    ("reply: growth past the margin not the list", M,
     "    if len(holding_after) == 1 and not _contains(bound, holding_after[0]):\n        return \"list\"",
     "    if False:\n        return \"list\""),
    ("reply: a field that is not focused accepted", M,
     "    if len(focused) == 1 and len(in_root) == 1:", "    if len(in_root) == 1:"),
    ("reply: two fields accepted", M,
     "    if len(focused) == 1 and len(in_root) == 1:", "    if len(focused) >= 1:"),
    ("reply: the margin boundary moved", M,
     "    return ox <= ix and oy <= iy and ix + iw <= ox + ow and iy + ih <= oy + oh",
     "    return ox < ix and oy < iy and ix + iw < ox + ow and iy + ih < oy + oh"),
    # The baseline and the coverage.
    ("baseline: a run with failures saved", M,
     "    if failed:\n        return \"the run has failures\"", "    if False:\n        return \"the run has failures\""),
    ("baseline: a narrowed run on this Mac saved", M,
     "    if sorted(plan[\"allow\"]) != sorted(MAC_CATEGORIES):", "    if False:"),
    ("baseline: excluded changes hidden", M,
     "            if current_excluded.get(t) != baseline_excluded.get(t):", "            if False:"),
    ("baseline: lost coverage not reported", M,
     "            if baseline_results[t] == \"passed\":\n                lost.append(t)", "            if False:\n                lost.append(t)"),
    ("coverage: more than one attachment accepted", M, "        if len(files) != 1:", "        if not files:"),
    ("coverage: unpressed buttons accepted", M, "    if not_pressed:\n        problems.append", "    if False:\n        problems.append"),
    ("fixture: a changed item accepted", M,
     "        if before.get(name) != after.get(name):", "        if False:"),
    ("fixture: a symlink accepted", M,
     "    if \"symlink\" in before.values() or \"symlink\" in after.values():", "    if False:"),
]


def ledger_snapshot():
    if not REAL_LEDGER_DIR.exists():
        return None
    return sorted((p.name, hashlib.sha256(p.read_bytes()).hexdigest()) for p in REAL_LEDGER_DIR.iterdir() if p.is_file())


def make_copy(base):
    for relative in COPIED:
        source = REPO / relative
        target = base / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            shutil.copy2(source, target)


def run(title, path, old, new):
    base = pathlib.Path(tempfile.mkdtemp(prefix="ntk-mac-mutation."))
    try:
        make_copy(base)
        if path is not None:
            target = base / path
            text = target.read_text(encoding="utf-8")
            if text.count(old) != 1:
                return "BROKEN", f"the text to replace appears {text.count(old)} times"
            target.write_text(text.replace(old, new), encoding="utf-8")
        env = dict(os.environ)
        finished = subprocess.run([sys.executable, "-m", "unittest", "-q", "scripts/tests/test_mac_ui_runner.py"],
                                  cwd=base, capture_output=True, text=True, env=env, timeout=900)
        caught = finished.returncode != 0
        if path is None:
            return ("SURVIVED (ok)" if not caught else "BASELINE FAILED"), finished.stderr[-2000:] if caught else ""
        return ("CAUGHT" if caught else "SURVIVED"), ""
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    wanted = [w for w in args.only.split(",") if w]
    before = ledger_snapshot()
    bad = 0
    for title, path, old, new in MUTATIONS:
        if wanted and not any(w in title for w in wanted):
            continue
        verdict, detail = run(title, path, old, new)
        print(f"{verdict:16} {title}", flush=True)
        if detail:
            print(detail)
        if verdict not in ("CAUGHT", "SURVIVED (ok)"):
            bad += 1
    if ledger_snapshot() != before:
        print("the real approval ledger changed during the mutation runs")
        bad += 1
    print(f"{bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
