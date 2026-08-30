#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CHECKER="$REPO_ROOT/scripts/flywheel-qualification-host.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flywheel-qualification-host.XXXXXXXX")"
SOURCE_ROOT="$TEST_ROOT/source"
SOURCE_BUNDLE="$TEST_ROOT/source.bundle"
BIN_ROOT="$TEST_ROOT/bin"
OS_RELEASE="$TEST_ROOT/os-release"
MEMINFO="$TEST_ROOT/meminfo"

trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$SOURCE_ROOT" "$BIN_ROOT"
git -C "$SOURCE_ROOT" init -q
printf 'qualification fixture\n' >"$SOURCE_ROOT/fixture.txt"
git -C "$SOURCE_ROOT" add fixture.txt
git -C "$SOURCE_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm initial
git -C "$SOURCE_ROOT" bundle create "$SOURCE_BUNDLE" HEAD

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
source_root = sys.argv[2]
bundle_path = pathlib.Path(sys.argv[3])
head = subprocess.check_output(["git", "-C", source_root, "rev-parse", "HEAD"], text=True).strip()
tree = subprocess.check_output(["git", "-C", source_root, "rev-parse", "HEAD^{tree}"], text=True).strip()

assert value["schema"] == "agent-flywheel.qualification-host/v1"
assert value["status"] == "pass"
assert value["summary"] == {"fail": 0, "pass": 9}
assert value["contract"] == {
    "architectures": ["aarch64", "x86_64"],
    "clean_source_identity_required": True,
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
assert value["source"]["clean"] is True
assert all(value["source"]["clean_state_evidence"].values())
assert value["bundle"]["verified"] is True
assert value["bundle"]["source_head"] == head
assert value["bundle"]["sha256"] == hashlib.sha256(bundle_path.read_bytes()).hexdigest()

declared_digest = value.pop("receipt_sha256")
canonical = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
assert declared_digest == hashlib.sha256(canonical.encode()).hexdigest()
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

printf 'qualification-host contract tests: PASS\n'
