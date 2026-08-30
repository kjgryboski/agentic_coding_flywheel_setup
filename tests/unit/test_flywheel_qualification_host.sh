#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CHECKER_SOURCE="$REPO_ROOT/scripts/flywheel-qualification-host.sh"
REPOSITORY_CONTROL="$REPO_ROOT/scripts/flywheel-repository-control.py"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flywheel-qualification-host.XXXXXXXX")"
SOURCE_ROOT="$TEST_ROOT/source"
SOURCE_BUNDLE="$TEST_ROOT/source.bundle"
BIN_ROOT="$TEST_ROOT/bin"
OS_RELEASE="$TEST_ROOT/os-release"
MEMINFO="$TEST_ROOT/meminfo"

trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$SOURCE_ROOT/scripts/lib" "$BIN_ROOT"
git -C "$SOURCE_ROOT" init -q
printf 'qualification fixture\n' >"$SOURCE_ROOT/fixture.txt"
printf '# Qualification fixture instructions\n' >"$SOURCE_ROOT/AGENTS.md"
printf '# trusted runtime contract fixture\n' >"$SOURCE_ROOT/scripts/lib/contract.sh"
cp "$REPO_ROOT/flywheel" "$SOURCE_ROOT/flywheel"
cp "$CHECKER_SOURCE" "$SOURCE_ROOT/scripts/flywheel-qualification-host.sh"
chmod 0755 "$SOURCE_ROOT/flywheel" "$SOURCE_ROOT/scripts/flywheel-qualification-host.sh"
git -C "$SOURCE_ROOT" add AGENTS.md fixture.txt scripts/lib/contract.sh
git -C "$SOURCE_ROOT" add flywheel scripts/flywheel-qualification-host.sh
git -C "$SOURCE_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm initial
git -C "$SOURCE_ROOT" bundle create "$SOURCE_BUNDLE" HEAD
CHECKER="$SOURCE_ROOT/scripts/flywheel-qualification-host.sh"

cat >"$OS_RELEASE" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
EOF
cat >"$MEMINFO" <<'EOF'
MemTotal:       10485760 kB
MemFree:         1048576 kB
SwapTotal:       8388604 kB
SwapFree:        8388604 kB
EOF
cat >"$BIN_ROOT/uname" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == "-m" ]] && printf 'aarch64\n' || exec /usr/bin/uname "$@"
SH
cat >"$BIN_ROOT/df" <<'SH'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/mock 100000000 1 60000000 1%% /\n'
SH
cat >"$BIN_ROOT/systemd-detect-virt" <<'SH'
#!/usr/bin/env bash
printf 'qemu\n'
SH
chmod 0755 "$BIN_ROOT/uname" "$BIN_ROOT/df" "$BIN_ROOT/systemd-detect-virt"

run_checker() {
    PATH="$BIN_ROOT:$PATH" \
    FLYWHEEL_SOURCE_ROOT="$SOURCE_ROOT" \
    FLYWHEEL_OS_RELEASE_FILE="$OS_RELEASE" \
    FLYWHEEL_MEMINFO_FILE="$MEMINFO" \
    FLYWHEEL_BASH_MAJOR=5 \
    FLYWHEEL_BASH_VERSION=5.2.0 \
    FLYWHEEL_OBSERVED_AT=2026-08-30T12:00:00Z \
    "$CHECKER" --json --bundle "$1"
}

receipt="$(run_checker "$SOURCE_BUNDLE")"
python3 - "$receipt" "$SOURCE_ROOT" "$SOURCE_BUNDLE" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

value = json.loads(sys.argv[1])
source_root = str(pathlib.Path(sys.argv[2]).resolve())
bundle_path = pathlib.Path(sys.argv[3]).resolve()
head = subprocess.check_output(["git", "-C", source_root, "rev-parse", "HEAD"], text=True).strip()
tree = subprocess.check_output(["git", "-C", source_root, "rev-parse", "HEAD^{tree}"], text=True).strip()

assert value["schema"] == "agent-flywheel.qualification-host/v1"
assert value["status"] == "pass"
assert value["summary"] == {"fail": 0, "pass": 9}
assert value["contract"] == {
    "architectures": ["aarch64", "x86_64"],
    "clean_source_identity_required": True,
    "critical_source_bytes_required": ["all-tracked-regular-files"],
    "exact_bundle_identity_required": True,
    "host_identity": "any-compliant-host",
    "isolation_required": True,
    "minimum_bash_major": 4,
    "minimum_disk_gib": 20,
    "minimum_memory_gib": 8,
    "minimum_swap_gib": 8,
    "receipt_digest": "sha256(canonical-json-without-receipt_sha256+newline)",
    "ubuntu_version": "24.04",
}
assert value["host"]["os"] == {"id": "ubuntu", "version": "24.04"}
assert value["host"]["architecture"] == "aarch64"
assert value["host"]["isolation"] == "qemu"
assert value["host"]["resources"]["memory_total_bytes"] == 10 * 1024**3
assert value["host"]["resources"]["swap_total_bytes"] == 8388604 * 1024
assert value["source"]["head"] == head
assert value["source"]["tree"] == tree
assert value["source"]["requested_root"] == source_root
assert value["source"]["git_paths"]["root"] == source_root
assert all(value["source"]["git_paths"].values())
assert value["source"]["clean"] is True
assert all(value["source"]["clean_state_evidence"].values())
assert value["bundle"]["verified"] is True
assert value["bundle"]["source_head"] == head
assert value["bundle"]["sha256"] == hashlib.sha256(bundle_path.read_bytes()).hexdigest()

declared_digest = value.pop("receipt_sha256")
canonical = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
assert declared_digest == hashlib.sha256(canonical.encode()).hexdigest()
PY

SHADOW_ROOT="$TEST_ROOT/python-shadow"
mkdir -p "$SHADOW_ROOT"
for module in datetime hashlib json pathlib; do
    printf 'raise RuntimeError("caller CWD module executed")\n' >"$SHADOW_ROOT/$module.py"
done
shadow_receipt="$(cd "$SHADOW_ROOT" && run_checker "$SOURCE_BUNDLE")"
python3 -I - "$shadow_receipt" <<'PY'
import json
import sys

assert json.loads(sys.argv[1])["status"] == "pass"
PY

POISON_ROOT="$TEST_ROOT/poison-repository"
TRACE_SENTINEL="$TEST_ROOT/git-trace.log"
TRACE2_SENTINEL="$TEST_ROOT/git-trace2.log"
TRACE_PERFORMANCE_SENTINEL="$TEST_ROOT/git-trace-performance.log"
mkdir -p "$POISON_ROOT"
git -C "$POISON_ROOT" init -q
printf 'poison\n' >"$POISON_ROOT/poison.txt"
git -C "$POISON_ROOT" add poison.txt
git -C "$POISON_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm poison
poison_receipt="$({
    export GIT_DIR="$POISON_ROOT/.git"
    export GIT_WORK_TREE="$POISON_ROOT"
    export GIT_INDEX_FILE="$POISON_ROOT/.git/index"
    export GIT_COMMON_DIR="$POISON_ROOT/.git"
    export GIT_OBJECT_DIRECTORY="$POISON_ROOT/.git/objects"
    export GIT_ALTERNATE_OBJECT_DIRECTORIES="$POISON_ROOT/.git/objects"
    export GIT_CEILING_DIRECTORIES="$TEST_ROOT"
    export GIT_NAMESPACE=poison
    export GIT_SHALLOW_FILE="$POISON_ROOT/.git/shallow"
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0=core.fsmonitor
    export GIT_CONFIG_VALUE_0="$TEST_ROOT/should-not-run"
    export GIT_TRACE="$TRACE_SENTINEL"
    export GIT_TRACE2="$TRACE2_SENTINEL"
    export GIT_TRACE_PERFORMANCE="$TRACE_PERFORMANCE_SENTINEL"
    run_checker "$SOURCE_BUNDLE"
})"
python3 -I - "$poison_receipt" <<'PY'
import json
import sys

assert json.loads(sys.argv[1])["status"] == "pass"
PY
[[ ! -e "$TRACE_SENTINEL" ]]
[[ ! -e "$TRACE2_SENTINEL" ]]
[[ ! -e "$TRACE_PERFORMANCE_SENTINEL" ]]

PYTHON_SHIM_SENTINEL="$TEST_ROOT/python-shim-ran"
cat >"$BIN_ROOT/python3" <<SH
#!/bin/sh
printf 'ran\n' >'$PYTHON_SHIM_SENTINEL'
exit 97
SH
chmod 0755 "$BIN_ROOT/python3"
python_shim_receipt="$(run_checker "$SOURCE_BUNDLE")"
/usr/bin/python3 -I - "$python_shim_receipt" <<'PY'
import json
import sys

assert json.loads(sys.argv[1])["status"] == "pass"
PY
[[ ! -e "$PYTHON_SHIM_SENTINEL" ]]

FSMONITOR_SENTINEL="$TEST_ROOT/fsmonitor-ran"
cat >"$TEST_ROOT/fsmonitor" <<SH
#!/usr/bin/env bash
printf 'ran\n' >'$FSMONITOR_SENTINEL'
exit 1
SH
chmod 0755 "$TEST_ROOT/fsmonitor"
git -C "$SOURCE_ROOT" config core.fsmonitor "$TEST_ROOT/fsmonitor"
fsmonitor_receipt="$(run_checker "$SOURCE_BUNDLE")"
python3 -I - "$fsmonitor_receipt" <<'PY'
import json
import sys

assert json.loads(sys.argv[1])["status"] == "pass"
PY
[[ ! -e "$FSMONITOR_SENTINEL" ]]

# Worktree acceptance compares raw bytes to committed blobs. Repository-local
# diff/textconv/clean/process helpers must neither execute nor conceal drift in
# a sourced runtime dependency.
DIFF_SENTINEL="$TEST_ROOT/diff-driver-ran"
FILTER_SENTINEL="$TEST_ROOT/filter-driver-ran"
PROCESS_SENTINEL="$TEST_ROOT/filter-process-ran"
cat >"$TEST_ROOT/poison-diff" <<SH
#!/bin/sh
printf 'ran\n' >'$DIFF_SENTINEL'
exit 0
SH
cat >"$TEST_ROOT/poison-filter" <<SH
#!/bin/sh
printf 'ran\n' >'$FILTER_SENTINEL'
cat
SH
cat >"$TEST_ROOT/poison-process" <<SH
#!/bin/sh
printf 'ran\n' >'$PROCESS_SENTINEL'
exit 1
SH
chmod 0755 "$TEST_ROOT/poison-diff" "$TEST_ROOT/poison-filter" "$TEST_ROOT/poison-process"
printf 'scripts/lib/contract.sh diff=poison filter=poison\n' >"$SOURCE_ROOT/.git/info/attributes"
git -C "$SOURCE_ROOT" config diff.poison.command "$TEST_ROOT/poison-diff"
git -C "$SOURCE_ROOT" config diff.poison.textconv "$TEST_ROOT/poison-diff"
git -C "$SOURCE_ROOT" config filter.poison.clean "$TEST_ROOT/poison-filter"
git -C "$SOURCE_ROOT" config filter.poison.process "$TEST_ROOT/poison-process"
printf '# concealed dependency drift\n' >>"$SOURCE_ROOT/scripts/lib/contract.sh"
set +e
filtered_drift_receipt="$(run_checker "$SOURCE_BUNDLE")"
filtered_drift_status=$?
set -e
[[ "$filtered_drift_status" -eq 1 ]]
/usr/bin/python3 -I - "$filtered_drift_receipt" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
assert value["status"] == "fail"
assert value["source"]["clean_state_evidence"]["worktree_clean"] is False
assert value["source"]["clean_state_evidence"]["critical_source_bytes_match"] is False
PY
[[ ! -e "$DIFF_SENTINEL" ]]
[[ ! -e "$FILTER_SENTINEL" ]]
[[ ! -e "$PROCESS_SENTINEL" ]]
git -C "$SOURCE_ROOT" show HEAD:scripts/lib/contract.sh >"$SOURCE_ROOT/scripts/lib/contract.sh"
: >"$SOURCE_ROOT/.git/info/attributes"
git -C "$SOURCE_ROOT" config --unset-all diff.poison.command
git -C "$SOURCE_ROOT" config --unset-all diff.poison.textconv
git -C "$SOURCE_ROOT" config --unset-all filter.poison.clean
git -C "$SOURCE_ROOT" config --unset-all filter.poison.process

PLAN_INVENTORY="$TEST_ROOT/rollout-inventory.json"
printf '{"schema":"agent-flywheel.rollout-inventory/v1","repositories":[{"path":"%s","cohort":"pilot"}]}\n' \
    "$SOURCE_ROOT" >"$PLAN_INVENTORY"
python3 -I - "$REPOSITORY_CONTROL" "$PLAN_INVENTORY" "$SOURCE_ROOT" "$TEST_ROOT" <<'PY'
import copy
import importlib.util
import os
import pathlib
import sys

control_path, inventory_path, source_root, test_root = sys.argv[1:]
spec = importlib.util.spec_from_file_location("flywheel_repository_control", control_path)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

plan = module.build_rollout_plan(inventory_path)
module.validate_plan_receipt(module.canonical_bytes(plan), plan)

def sealed(candidate):
    candidate.pop("plan_sha256", None)
    candidate["plan_sha256"] = module.content_digest(candidate)
    return module.canonical_bytes(candidate)

def rejects(label, mutate):
    candidate = copy.deepcopy(plan)
    mutate(candidate)
    try:
        module.validate_plan_receipt(sealed(candidate), candidate)
    except module.ControlError:
        return
    raise AssertionError(f"forged plan accepted: {label}")

rejects("extra top-level key", lambda item: item.__setitem__("live_rollout_passed", True))
rejects("missing top-level key", lambda item: item.pop("inventory_sha256"))
rejects("wrong status", lambda item: item.__setitem__("status", "eligible"))
rejects("wrong execution status", lambda item: item.__setitem__("execution_status", "executed"))
rejects("mutation authorization", lambda item: item.__setitem__("mutation_authorized", True))
rejects("repository count bool", lambda item: item.__setitem__("repository_count", True))
rejects("attention wrong type", lambda item: item.__setitem__("repositories_requiring_attention", {}))
rejects("missing cohort key", lambda item: item["cohorts"][0].pop("required_gate"))
rejects("extra cohort key", lambda item: item["cohorts"][0].__setitem__("live_claim", "PASS"))
rejects("cohort order bool", lambda item: item["cohorts"][0].__setitem__("cohort_order", False))
rejects("repository wrong type", lambda item: item["cohorts"][0].__setitem__("repository", []))
rejects(
    "nested count bool",
    lambda item: item["cohorts"][0]["repository"].__setitem__("change_record_count", False),
)
rejects(
    "unsafe requested path",
    lambda item: item["cohorts"][0]["repository"].__setitem__("requested_path", "/tmp/bad\0path"),
)
rejects(
    "live eligibility claim",
    lambda item: item["cohorts"][0].__setitem__("live_rollout_eligible", True),
)

def add_duplicate(item):
    duplicate = copy.deepcopy(item["cohorts"][0])
    duplicate.update({
        "cohort": "low-risk",
        "cohort_order": 1,
        "required_gate": module._required_gate("low-risk"),
    })
    item["cohorts"].append(duplicate)
    item["repository_count"] = 2

rejects("duplicate repository root", add_duplicate)

def add_out_of_order(item):
    second = copy.deepcopy(item["cohorts"][0])
    other_root = str(pathlib.Path(test_root, "other-repository").resolve())
    second.update({
        "cohort": "low-risk",
        "cohort_order": 1,
        "required_gate": module._required_gate("low-risk"),
    })
    second["repository"].update({
        "name": "other-repository",
        "requested_path": other_root,
        "root": other_root,
        "git_paths": {
            "root": other_root,
            "git_dir": other_root + "/.git",
            "common_dir": other_root + "/.git",
            "index": other_root + "/.git/index",
        },
    })
    item["cohorts"] = [second, item["cohorts"][0]]
    item["repository_count"] = 2

rejects("cohort order drift", add_out_of_order)

source = pathlib.Path(source_root).resolve()
expected_repository = "example/source"
os.environ.update({
    "GIT_DIR": str(pathlib.Path(test_root, "poison-repository/.git")),
    "GIT_WORK_TREE": str(pathlib.Path(test_root, "poison-repository")),
    "GIT_INDEX_FILE": str(pathlib.Path(test_root, "poison-repository/.git/index")),
    "GIT_COMMON_DIR": str(pathlib.Path(test_root, "poison-repository/.git")),
    "GIT_OBJECT_DIRECTORY": str(pathlib.Path(test_root, "poison-repository/.git/objects")),
    "GIT_CEILING_DIRECTORIES": test_root,
    "GIT_NAMESPACE": "poison",
    "GIT_CONFIG_COUNT": "1",
    "GIT_CONFIG_KEY_0": "core.fsmonitor",
    "GIT_CONFIG_VALUE_0": str(pathlib.Path(test_root, "should-not-run")),
    "GIT_TRACE": str(pathlib.Path(test_root, "repository-control-trace")),
})
inspection = module.inspect_repository(str(source))
assert inspection["repository"]["root"] == str(source)
assert not pathlib.Path(test_root, "repository-control-trace").exists()

module.git(source, "config", "remote.origin.url", "https://github.com/example/source.git")
origin = module.bind_origin(source, expected_repository)
assert origin["fetch_repository"] == expected_repository
assert origin["push_repository"] == expected_repository
assert origin["fetch_url"] == origin["push_url"]

module.git(source, "config", "--add", "remote.origin.url", "git@github.com:example/source.git")
try:
    module.bind_origin(source, expected_repository)
except module.ControlError:
    pass
else:
    raise AssertionError("multiple fetch URLs accepted")
module.git(source, "config", "--unset-all", "remote.origin.url")
module.git(source, "config", "remote.origin.url", "https://github.com/example/source.git")

def origin_rejects(label):
    try:
        module.bind_origin(source, expected_repository)
    except module.ControlError:
        return
    raise AssertionError(f"unsafe origin accepted: {label}")

module.git(source, "config", "remote.origin.pushurl", "https://github.com/example/other.git")
origin_rejects("divergent push destination")
module.git(source, "config", "--unset-all", "remote.origin.pushurl")
module.git(source, "config", "--add", "remote.origin.pushurl", "https://github.com/example/source.git")
module.git(source, "config", "--add", "remote.origin.pushurl", "git@github.com:example/source.git")
origin_rejects("multiple push URLs")
module.git(source, "config", "--unset-all", "remote.origin.pushurl")
module.git(source, "config", "remote.origin.mirror", "true")
origin_rejects("mirror configuration")
module.git(source, "config", "--unset-all", "remote.origin.mirror")
module.git(source, "config", "remote.origin.pushurl", "git@github.com:example/source.git")
assert module.bind_origin(source, expected_repository)["push_repository"] == expected_repository
module.git(source, "update-ref", "refs/remotes/origin/main", "HEAD")
target = module.bind_target_repository(str(source), expected_repository)
assert target["requested_path"] == str(source)
assert target["git_paths"] == module.repository_binding(source)
assert target["remote"]["fetch_repository"] == expected_repository
assert target["remote"]["push_repository"] == expected_repository
assert target["remote"]["fetch_url"] == "https://github.com/example/source.git"
assert target["remote"]["push_url"] == "git@github.com:example/source.git"
PY

printf 'changed\n' >>"$SOURCE_ROOT/fixture.txt"
set +e
dirty_receipt="$(run_checker "$SOURCE_BUNDLE")"
dirty_status=$?
set -e
[[ "$dirty_status" -eq 1 ]]
python3 - "$dirty_receipt" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
requirements = {item["id"]: item["status"] for item in value["requirements"]}
assert value["status"] == "fail"
assert value["source"]["clean"] is False
assert value["source"]["clean_state_evidence"]["worktree_clean"] is False
assert requirements["source_identity"] == "fail"
PY
printf 'qualification fixture\n' >"$SOURCE_ROOT/fixture.txt"

assert_source_evidence_failure() {
    local candidate_receipt="$1"
    local evidence_key="$2"
    python3 -I - "$candidate_receipt" "$evidence_key" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
evidence_key = sys.argv[2]
requirements = {item["id"]: item["status"] for item in value["requirements"]}
assert value["status"] == "fail"
assert value["source"]["clean"] is False
assert value["source"]["clean_state_evidence"][evidence_key] is False
assert requirements["source_identity"] == "fail"
PY
}

git -C "$SOURCE_ROOT" update-index --assume-unchanged fixture.txt
set +e
assume_receipt="$(run_checker "$SOURCE_BUNDLE")"
assume_status=$?
set -e
[[ "$assume_status" -eq 1 ]]
assert_source_evidence_failure "$assume_receipt" index_flags_clean
git -C "$SOURCE_ROOT" update-index --no-assume-unchanged fixture.txt

git -C "$SOURCE_ROOT" update-index --skip-worktree fixture.txt
set +e
skip_receipt="$(run_checker "$SOURCE_BUNDLE")"
skip_status=$?
set -e
[[ "$skip_status" -eq 1 ]]
assert_source_evidence_failure "$skip_receipt" index_flags_clean
git -C "$SOURCE_ROOT" update-index --no-skip-worktree fixture.txt

git -C "$SOURCE_ROOT" config core.sparseCheckout true
set +e
sparse_receipt="$(run_checker "$SOURCE_BUNDLE")"
sparse_status=$?
set -e
[[ "$sparse_status" -eq 1 ]]
assert_source_evidence_failure "$sparse_receipt" sparse_checkout_disabled
git -C "$SOURCE_ROOT" config core.sparseCheckout false

git -C "$SOURCE_ROOT" config core.sparseCheckout invalid
set +e
invalid_sparse_receipt="$(run_checker "$SOURCE_BUNDLE")"
invalid_sparse_status=$?
set -e
[[ "$invalid_sparse_status" -eq 1 ]]
assert_source_evidence_failure "$invalid_sparse_receipt" sparse_checkout_disabled
git -C "$SOURCE_ROOT" config core.sparseCheckout false

printf '\n# hidden qualification drift\n' >>"$SOURCE_ROOT/flywheel"
git -C "$SOURCE_ROOT" update-index --assume-unchanged flywheel
set +e
critical_drift_receipt="$(run_checker "$SOURCE_BUNDLE")"
critical_drift_status=$?
set -e
[[ "$critical_drift_status" -eq 1 ]]
assert_source_evidence_failure "$critical_drift_receipt" critical_source_bytes_match
git -C "$SOURCE_ROOT" update-index --no-assume-unchanged flywheel
git -C "$SOURCE_ROOT" show HEAD:flywheel >"$SOURCE_ROOT/flywheel"
chmod 0755 "$SOURCE_ROOT/flywheel"

set +e
missing_bundle_receipt="$(run_checker "$TEST_ROOT/missing.bundle")"
missing_bundle_status=$?
set -e
[[ "$missing_bundle_status" -eq 1 ]]
python3 - "$missing_bundle_receipt" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
requirements = {item["id"]: item["status"] for item in value["requirements"]}
assert value["bundle"] == {"sha256": None, "source_head": None, "verified": False}
assert requirements["bundle_identity"] == "fail"
PY

cat >"$MEMINFO" <<'EOF'
MemTotal:       4194304 kB
SwapTotal:            0 kB
EOF
set +e
undersized_receipt="$(run_checker "$SOURCE_BUNDLE")"
undersized_status=$?
set -e
[[ "$undersized_status" -eq 1 ]]
python3 - "$undersized_receipt" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
requirements = {item["id"]: item["status"] for item in value["requirements"]}
assert requirements["memory_total"] == "fail"
assert requirements["swap_total"] == "fail"
PY

set +e
invalid_threshold_output="$(
    FLYWHEEL_MIN_MEMORY_GIB=0 run_checker "$SOURCE_BUNDLE" 2>&1
)"
invalid_threshold_status=$?
set -e
[[ "$invalid_threshold_status" -eq 2 ]]
[[ "$invalid_threshold_output" == *"positive whole GiB"* ]]

fixture_blob="$(git -C "$SOURCE_ROOT" rev-parse HEAD:fixture.txt)"
{
    printf '0 0000000000000000000000000000000000000000\tfixture.txt\n'
    printf '100644 %s 1\tfixture.txt\n' "$fixture_blob"
    printf '100644 %s 2\tfixture.txt\n' "$fixture_blob"
    printf '100644 %s 3\tfixture.txt\n' "$fixture_blob"
} | git -C "$SOURCE_ROOT" update-index --index-info
set +e
unmerged_receipt="$(run_checker "$SOURCE_BUNDLE")"
unmerged_status=$?
set -e
[[ "$unmerged_status" -eq 1 ]]
assert_source_evidence_failure "$unmerged_receipt" unmerged_index_clean

printf 'qualification-host contract tests: PASS\n'
