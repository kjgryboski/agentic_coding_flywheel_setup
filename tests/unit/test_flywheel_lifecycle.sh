#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flywheel-lifecycle-test.XXXXXXXX")"
test_status=0
trap 'rm -rf -- "$TEST_ROOT"' EXIT
trap 'test_status=$?; printf "flywheel lifecycle test failed at line %s (exit %s)\n" "$LINENO" "$test_status" >&2' ERR

CALLS="$TEST_ROOT/calls"
STATUS_FILE="$TEST_ROOT/status"
PRESENT_FILE="$TEST_ROOT/present"
PROFILE_FILE="$TEST_ROOT/profile"
QUERY_FILE="$TEST_ROOT/query"
printf 'Stopped\n' >"$STATUS_FILE"
printf '1\n' >"$PRESENT_FILE"
printf 'exact\n' >"$PROFILE_FILE"
printf 'ok\n' >"$QUERY_FILE"
: >"$CALLS"

cat >"$TEST_ROOT/limactl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    list)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        [[ "$(cat "$FLYWHEEL_TEST_QUERY_FILE")" == "ok" ]] || exit 44
        [[ "$(cat "$FLYWHEEL_TEST_PRESENT_FILE")" == "1" ]] || exit 0
        status="$(cat "$FLYWHEEL_TEST_STATUS_FILE")"
        cpus=6
        [[ "$(cat "$FLYWHEEL_TEST_PROFILE_FILE")" == "exact" ]] || cpus=4
        printf '{"name":"agent-flywheel-ubuntu2404","status":"%s","vmType":"vz","arch":"aarch64","cpus":%s,"memory":10737418240,"disk":73014444032,"config":{"images":[{"location":"https://cloud-images.ubuntu.com/releases/24.04/release-20260814/ubuntu-24.04-server-cloudimg-arm64.img","arch":"aarch64","digest":"sha256:4a281a921b8d7db952895ab619736f10efe9f63e111fa5b5779ed18f023818aa"}],"plain":true,"mounts":[],"portForwards":[{"ignore":true}]}}\n' "$status" "$cpus"
        ;;
    validate)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        ;;
    start)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        printf '1\n' >"$FLYWHEEL_TEST_PRESENT_FILE"
        printf 'Running\n' >"$FLYWHEEL_TEST_STATUS_FILE"
        ;;
    shell)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        if [[ "$*" == *flywheel-verify-exact-guest-source* ]]; then
            shift
            while (($#)) && [[ "$1" != "--" ]]; do
                shift
            done
            (($#))
            shift
            remote_command=("$@")
            if [[ "${remote_command[0]:-}" == "sudo" ]]; then
                remote_command=("${remote_command[@]:1}")
            fi
            for index in "${!remote_command[@]}"; do
                if [[ "${remote_command[$index]}" == /opt/agent-flywheel-acfs-* \
                    && -n "${FLYWHEEL_TEST_GUEST_ROOT:-}" ]]; then
                    remote_command[$index]="$FLYWHEEL_TEST_GUEST_ROOT"
                fi
            done
            "${remote_command[@]}"
            exit
        fi
        case "$*" in
            *flywheel-qualification-host.sh*)
                /usr/bin/python3 -I - "$FLYWHEEL_STATE_HOME/installation.json" <<'PY'
import hashlib
import json
import os
import sys

installation = json.load(open(sys.argv[1], encoding="utf-8"))
source = installation["source"]
bundle = installation["bundle"]
requirement_ids = [
    "ubuntu_version", "architecture", "bash_runtime", "disk_free", "memory_total",
    "swap_total", "isolation", "source_identity", "bundle_identity",
]
receipt = {
    "schema": "agent-flywheel.qualification-host/v1",
    "observed_at": "2026-08-30T12:00:00Z",
    "contract": {
        "host_identity": "any-compliant-host",
        "ubuntu_version": "24.04",
        "architectures": ["aarch64", "x86_64"],
        "minimum_disk_gib": 20,
        "minimum_memory_gib": 8,
        "minimum_swap_gib": 8,
        "minimum_bash_major": 4,
        "isolation_required": True,
        "clean_source_identity_required": True,
        "critical_source_bytes_required": ["all-tracked-regular-files"],
        "exact_bundle_identity_required": True,
        "receipt_digest": "sha256(canonical-json-without-receipt_sha256+newline)",
    },
    "host": {
        "os": {"id": "ubuntu", "version": "24.04"},
        "architecture": "aarch64",
        "bash_version": "5.2.0",
        "isolation": "qemu",
        "resources": {
            "disk_free_bytes": 30 * 1024**3,
            "memory_total_bytes": 10 * 1024**3,
            "swap_total_bytes": 8 * 1024**3,
        },
    },
    "source": {
        "head": source["head"],
        "tree": source["tree"],
        "requested_root": source["guest_root"],
        "git_paths": {
            "root": source["guest_root"],
            "git_dir": source["guest_root"] + "/.git",
            "common_dir": source["guest_root"] + "/.git",
            "index": source["guest_root"] + "/.git/index",
        },
        "clean": True,
        "clean_state_evidence": {
            "git_repository": True,
            "worktree_clean": True,
            "index_clean": True,
            "untracked_clean": True,
            "index_flags_clean": True,
            "sparse_checkout_disabled": True,
            "unmerged_index_clean": True,
            "critical_source_bytes_match": True,
            "repository_binding_stable": True,
        },
    },
    "bundle": {
        "sha256": bundle["sha256"],
        "source_head": source["head"],
        "verified": True,
    },
    "status": "pass",
    "requirements": [
        {"id": identifier, "status": "pass", "detail": "test evidence"}
        for identifier in requirement_ids
    ],
    "summary": {"pass": 9, "fail": 0},
}
mutation = os.environ.get("FLYWHEEL_TEST_QUALIFICATION_MUTATION", "")
if mutation == "wrong-schema":
    receipt["schema"] = "agent-flywheel.qualification-host/forged"
elif mutation == "extra-field":
    receipt["claim"] = "PARTIAL_SAFE"
elif mutation == "wrong-source":
    receipt["source"]["head"] = "0" * 40
elif mutation == "wrong-bundle":
    receipt["bundle"]["sha256"] = "0" * 64
elif mutation == "inconsistent-summary":
    receipt["summary"] = {"pass": 8, "fail": 1}
canonical = json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
receipt["receipt_sha256"] = hashlib.sha256(canonical.encode()).hexdigest()
if mutation == "bad-digest":
    receipt["receipt_sha256"] = "0" * 64
print(json.dumps(receipt, sort_keys=True, separators=(",", ":")))
PY
                ;;
            *flywheel-partial-safe-doctor.sh*)
                /usr/bin/python3 -I - "$FLYWHEEL_STATE_HOME/installation.json" <<'PY'
import hashlib
import json
import os
import sys

installation = json.load(open(sys.argv[1], encoding="utf-8"))
license_cleared = installation["authority"]["kind"] == "license_clearance"
check_ids = [
    "license_clearance" if license_cleared else "allowlist",
    "target_identity", "base.system", "users.ubuntu", "host.swap_contract",
    "base.filesystem", "cli.modern", "lang.bun/bun", "lang.uv/uv",
    "lang.rust/rustc", "lang.rust/cargo", "lang.go/go",
    "license_scope" if license_cleared else "held_exclusions",
]
if license_cleared:
    check_ids.extend(["expanded_modules", "stack.srps/service", "independent_holds"])
check_ids.append("state")
receipt = {
    "schema": "agent-flywheel.license-cleared-doctor/v1" if license_cleared else "agent-flywheel.partial-safe-doctor/v1",
    "claim": installation["claim"],
    "fully_commissioned": False,
    "status": "pass",
    "source": {
        "head": installation["source"]["head"],
        "tree": installation["source"]["tree"],
    },
    "authority": {
        "kind": installation["authority"]["kind"],
        "sha256": installation["authority"]["sha256"],
    },
    "checks": [
        {"id": identifier, "status": "pass", "detail": "test evidence"}
        for identifier in check_ids
    ],
    "summary": {"pass": len(check_ids), "warn": 0, "fail": 0},
}
mutation = os.environ.get("FLYWHEEL_TEST_DOCTOR_MUTATION", "")
if mutation == "wrong-schema":
    receipt["schema"] = "agent-flywheel.partial-safe-doctor/forged"
elif mutation == "extra-field":
    receipt["installed"] = True
elif mutation == "wrong-claim":
    receipt["claim"] = "FULLY_COMMISSIONED"
elif mutation == "wrong-source":
    receipt["source"]["tree"] = "0" * 40
elif mutation == "wrong-authority":
    receipt["authority"]["sha256"] = "0" * 64
elif mutation == "inconsistent-summary":
    receipt["summary"] = {"pass": len(check_ids) - 1, "warn": 0, "fail": 1}
canonical = json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
receipt["receipt_sha256"] = hashlib.sha256(canonical.encode()).hexdigest()
if mutation == "bad-digest":
    receipt["receipt_sha256"] = "0" * 64
print(json.dumps(receipt, sort_keys=True, separators=(",", ":")))
PY
                ;;
        esac
        ;;
    stop)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        if [[ -n "${FLYWHEEL_TEST_STOP_ENTERED_FILE:-}" ]]; then
            : >"$FLYWHEEL_TEST_STOP_ENTERED_FILE"
            attempts=0
            while [[ ! -e "$FLYWHEEL_TEST_STOP_RELEASE_FILE" ]]; do
                attempts=$((attempts + 1))
                ((attempts < 200)) || exit 88
                sleep 0.05
            done
        fi
        printf 'Stopped\n' >"$FLYWHEEL_TEST_STATUS_FILE"
        ;;
    copy)
        printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
        ;;
    *)
        printf 'unexpected limactl command: %s\n' "$*" >&2
        exit 2
        ;;
esac
SH

cat >"$TEST_ROOT/heavy-run" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FLYWHEEL_TEST_CALLS"
[[ "${1:-}" == "--stateful" && "${2:-}" == "--" ]]
shift 2
"$@"
if [[ -n "${FLYWHEEL_TEST_POST_HEAVY_MUTATE_ROOT:-}" ]]; then
    printf '\n# post-preflight launcher drift\n' >>"$FLYWHEEL_TEST_POST_HEAVY_MUTATE_ROOT/flywheel"
    chmod u+w "$FLYWHEEL_TEST_POST_HEAVY_MUTATE_ROOT/config/flywheel-partial-safe-allowlist.json"
    printf '\n ' >>"$FLYWHEEL_TEST_POST_HEAVY_MUTATE_ROOT/config/flywheel-partial-safe-allowlist.json"
fi
SH

chmod 0755 "$TEST_ROOT/limactl" "$TEST_ROOT/heavy-run"

export FLYWHEEL_LIMACTL="$TEST_ROOT/limactl"
export FLYWHEEL_HEAVY_RUN="$TEST_ROOT/heavy-run"
export FLYWHEEL_STATE_HOME="$TEST_ROOT/state"
export FLYWHEEL_SOURCE_REPO="$REPO_ROOT"
export FLYWHEEL_TEST_CALLS="$CALLS"
export FLYWHEEL_TEST_STATUS_FILE="$STATUS_FILE"
export FLYWHEEL_TEST_PRESENT_FILE="$PRESENT_FILE"
export FLYWHEEL_TEST_PROFILE_FILE="$PROFILE_FILE"
export FLYWHEEL_TEST_QUERY_FILE="$QUERY_FILE"

python3 - "$REPO_ROOT/config/flywheel-partial-safe-allowlist.json" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
contract = value["commissioning_scope"]["qualification_host_contract"]
assert contract == {
    "architectures": ["aarch64", "x86_64"],
    "clean_source_identity_required": True,
    "host_identity": "any-compliant-host",
    "id": "agent-flywheel.qualification-host/v1",
    "isolation_required": True,
    "minimum_bash_major": 4,
    "minimum_disk_gib": 20,
    "ubuntu_version": "24.04",
}
assert "supported_hosts" not in value["commissioning_scope"]
PY

QUALIFICATION_ROOT="$TEST_ROOT/qualification-source"
mkdir -p "$QUALIFICATION_ROOT/config" "$QUALIFICATION_ROOT/.github/workflows" \
    "$QUALIFICATION_ROOT/scripts/lib"
git -C "$QUALIFICATION_ROOT" init -q
printf 'schema_version: 2\n' >"$QUALIFICATION_ROOT/acfs.manifest.yaml"
printf '0.8.0\n' >"$QUALIFICATION_ROOT/VERSION"
printf '# Repository instructions\n' >"$QUALIFICATION_ROOT/AGENTS.md"
printf 'name: test\non: push\njobs: {}\n' >"$QUALIFICATION_ROOT/.github/workflows/test.yml"
cp "$REPO_ROOT/config/flywheel-partial-safe-allowlist.json" \
    "$QUALIFICATION_ROOT/config/flywheel-partial-safe-allowlist.json"
cp "$REPO_ROOT/config/flywheel-lima.yaml" \
    "$QUALIFICATION_ROOT/config/flywheel-lima.yaml"
cp "$REPO_ROOT/flywheel" "$QUALIFICATION_ROOT/flywheel"
cp "$REPO_ROOT/scripts/flywheel-repository-control.py" \
    "$QUALIFICATION_ROOT/scripts/flywheel-repository-control.py"
cp "$REPO_ROOT/scripts/lib/contract.sh" \
    "$QUALIFICATION_ROOT/scripts/lib/contract.sh"
cp "$REPO_ROOT/install.sh" "$QUALIFICATION_ROOT/install.sh"
for guest_entrypoint in \
    flywheel-mac-install-guest.sh \
    flywheel-ensure-swap.sh \
    flywheel-qualification-host.sh \
    flywheel-partial-safe-doctor.sh; do
    cp "$REPO_ROOT/scripts/$guest_entrypoint" \
        "$QUALIFICATION_ROOT/scripts/$guest_entrypoint"
done
git -C "$QUALIFICATION_ROOT" add \
    acfs.manifest.yaml VERSION AGENTS.md flywheel install.sh \
    .github/workflows/test.yml \
    config/flywheel-partial-safe-allowlist.json config/flywheel-lima.yaml \
    scripts/flywheel-repository-control.py \
    scripts/lib/contract.sh \
    scripts/flywheel-mac-install-guest.sh \
    scripts/flywheel-ensure-swap.sh \
    scripts/flywheel-qualification-host.sh \
    scripts/flywheel-partial-safe-doctor.sh
git -C "$QUALIFICATION_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm initial
GUEST_ROOT="$TEST_ROOT/existing-guest-source"
git clone -q "$QUALIFICATION_ROOT" "$GUEST_ROOT"
export FLYWHEEL_TEST_GUEST_ROOT="$GUEST_ROOT"
printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$TEST_ROOT/os-release"
printf 'MemTotal: 10485760 kB\nSwapTotal: 8388608 kB\n' >"$TEST_ROOT/meminfo"
git -C "$QUALIFICATION_ROOT" bundle create "$TEST_ROOT/qualification-source.bundle" HEAD
cat >"$TEST_ROOT/uname" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == "-m" ]] && printf 'aarch64\n' || exec /usr/bin/uname "$@"
SH
cat >"$TEST_ROOT/df" <<'SH'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/mock 100000000 1 60000000 1%% /\n'
SH
cat >"$TEST_ROOT/systemd-detect-virt" <<'SH'
#!/usr/bin/env bash
printf 'qemu\n'
SH
chmod 0755 "$TEST_ROOT/uname" "$TEST_ROOT/df" "$TEST_ROOT/systemd-detect-virt"
qualification_json="$(
    PATH="$TEST_ROOT:$PATH" \
    FLYWHEEL_SOURCE_ROOT="$QUALIFICATION_ROOT" \
    FLYWHEEL_SOURCE_BUNDLE="$TEST_ROOT/qualification-source.bundle" \
    FLYWHEEL_OS_RELEASE_FILE="$TEST_ROOT/os-release" \
    FLYWHEEL_MEMINFO_FILE="$TEST_ROOT/meminfo" \
    FLYWHEEL_BASH_MAJOR=5 \
    FLYWHEEL_BASH_VERSION=5.2.0 \
    "$QUALIFICATION_ROOT/scripts/flywheel-qualification-host.sh" --json
)"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["status"] == "pass"
assert value["summary"] == {"fail":0,"pass":9}
assert value["contract"]["host_identity"] == "any-compliant-host"
assert value["contract"]["architectures"] == ["aarch64","x86_64"]
assert value["contract"]["minimum_disk_gib"] == 20
assert value["contract"]["minimum_memory_gib"] == 8
assert value["contract"]["minimum_swap_gib"] == 8
assert value["source"]["clean"] is True
assert value["bundle"]["verified"] is True
assert len(value["receipt_sha256"]) == 64
' "$qualification_json"

export FLYWHEEL_SOURCE_REPO="$QUALIFICATION_ROOT"
mkdir -p "$FLYWHEEL_STATE_HOME"
chmod 0700 "$FLYWHEEL_STATE_HOME"
printf 'do-not-overwrite\n' >"$TEST_ROOT/symlink-target"
ln -s "$TEST_ROOT/symlink-target" "$FLYWHEEL_STATE_HOME/source-root"
ln -s "$TEST_ROOT/symlink-target" "$FLYWHEEL_STATE_HOME/installation.json"
HOME="$TEST_ROOT/home" "$REPO_ROOT/flywheel" mac install --quiet
[[ ! -L "$FLYWHEEL_STATE_HOME/source-root" ]]
[[ ! -L "$FLYWHEEL_STATE_HOME/installation.json" ]]
[[ "$(<"$TEST_ROOT/symlink-target")" == "do-not-overwrite" ]]
cmp -s "$QUALIFICATION_ROOT/flywheel" "$TEST_ROOT/home/.local/bin/flywheel"
# The installed entrypoint must be able to converge again. Historically it
# tried to install itself onto itself and failed after the guest had succeeded.
HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" mac install --quiet
cmp -s "$QUALIFICATION_ROOT/flywheel" "$TEST_ROOT/home/.local/bin/flywheel"

# Bytes copied after the long guest convergence come from the selected commit,
# not mutable worktree paths that may drift after preflight.
export FLYWHEEL_TEST_POST_HEAVY_MUTATE_ROOT="$QUALIFICATION_ROOT"
HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" mac install --quiet
unset FLYWHEEL_TEST_POST_HEAVY_MUTATE_ROOT
git -C "$QUALIFICATION_ROOT" show HEAD:flywheel >"$TEST_ROOT/committed-flywheel"
cmp -s "$TEST_ROOT/committed-flywheel" "$TEST_ROOT/home/.local/bin/flywheel"
/usr/bin/python3 -I - "$FLYWHEEL_STATE_HOME/installation.json" <<'PY'
import json
import sys

value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["authority"]["sha256"] == "736ce053c42c91b4219cc13dde7a604c33158e1369f3d4d91031672da80f3633"
PY
git -C "$QUALIFICATION_ROOT" show HEAD:flywheel >"$QUALIFICATION_ROOT/flywheel"
chmod 0755 "$QUALIFICATION_ROOT/flywheel"
git -C "$QUALIFICATION_ROOT" show HEAD:config/flywheel-partial-safe-allowlist.json \
    >"$QUALIFICATION_ROOT/config/flywheel-partial-safe-allowlist.json"
chmod 0444 "$QUALIFICATION_ROOT/config/flywheel-partial-safe-allowlist.json"

# Reusing an existing guest checkout must reject index state that hides changed
# executable bytes. The host source remains clean, so this exercises the guest
# boundary rather than the host preflight.
git -C "$GUEST_ROOT" update-index --assume-unchanged \
    scripts/flywheel-mac-install-guest.sh
printf '\nprintf "hidden guest installer executed\\n" >&2\n' \
    >>"$GUEST_ROOT/scripts/flywheel-mac-install-guest.sh"
: >"$CALLS"
hidden_guest_rc=0
HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" mac install --quiet \
    >"$TEST_ROOT/hidden-guest-install.out" 2>&1 || hidden_guest_rc=$?
[[ "$hidden_guest_rc" -ne 0 ]]
grep -F -- 'flywheel-verify-exact-guest-source' "$CALLS" >/dev/null
if grep -F -- 'flywheel-mac-install-guest.sh /opt/agent-flywheel-acfs-' "$CALLS" >/dev/null; then
    printf 'hidden guest installer unexpectedly reached execution\n' >&2
    exit 1
fi
git -C "$GUEST_ROOT" update-index --no-assume-unchanged \
    scripts/flywheel-mac-install-guest.sh
git -C "$GUEST_ROOT" show HEAD:scripts/flywheel-mac-install-guest.sh \
    >"$GUEST_ROOT/scripts/flywheel-mac-install-guest.sh"

# Repository-local Git filters cannot execute or normalize a modified sourced
# dependency during the guest exact-source check.
GUEST_FILTER_SENTINEL="$TEST_ROOT/guest-filter-ran"
GUEST_PROCESS_SENTINEL="$TEST_ROOT/guest-filter-process-ran"
GUEST_DIFF_SENTINEL="$TEST_ROOT/guest-diff-driver-ran"
cat >"$TEST_ROOT/guest-filter" <<SH
#!/bin/sh
printf 'ran\n' >'$GUEST_FILTER_SENTINEL'
cat
SH
cat >"$TEST_ROOT/guest-process" <<SH
#!/bin/sh
printf 'ran\n' >'$GUEST_PROCESS_SENTINEL'
exit 1
SH
cat >"$TEST_ROOT/guest-diff" <<SH
#!/bin/sh
printf 'ran\n' >'$GUEST_DIFF_SENTINEL'
exit 0
SH
chmod 0755 "$TEST_ROOT/guest-filter" "$TEST_ROOT/guest-process" "$TEST_ROOT/guest-diff"
printf 'scripts/lib/contract.sh filter=poison diff=poison\n' >"$GUEST_ROOT/.git/info/attributes"
git -C "$GUEST_ROOT" config filter.poison.clean "$TEST_ROOT/guest-filter"
git -C "$GUEST_ROOT" config filter.poison.process "$TEST_ROOT/guest-process"
git -C "$GUEST_ROOT" config diff.poison.command "$TEST_ROOT/guest-diff"
git -C "$GUEST_ROOT" config diff.poison.textconv "$TEST_ROOT/guest-diff"
printf '# concealed guest contract drift\n' >>"$GUEST_ROOT/scripts/lib/contract.sh"
: >"$CALLS"
filtered_guest_rc=0
HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" mac install --quiet \
    >"$TEST_ROOT/filtered-guest-install.out" 2>&1 || filtered_guest_rc=$?
[[ "$filtered_guest_rc" -ne 0 ]]
[[ ! -e "$GUEST_FILTER_SENTINEL" ]]
[[ ! -e "$GUEST_PROCESS_SENTINEL" ]]
[[ ! -e "$GUEST_DIFF_SENTINEL" ]]
if grep -F -- 'flywheel-mac-install-guest.sh /opt/agent-flywheel-acfs-' "$CALLS" >/dev/null; then
    printf 'filtered guest dependency unexpectedly reached installation\n' >&2
    exit 1
fi
git -C "$GUEST_ROOT" show HEAD:scripts/lib/contract.sh >"$GUEST_ROOT/scripts/lib/contract.sh"
: >"$GUEST_ROOT/.git/info/attributes"
git -C "$GUEST_ROOT" config --unset-all filter.poison.clean
git -C "$GUEST_ROOT" config --unset-all filter.poison.process
git -C "$GUEST_ROOT" config --unset-all diff.poison.command
git -C "$GUEST_ROOT" config --unset-all diff.poison.textconv

python3 - "$FLYWHEEL_STATE_HOME/installation.json" "$QUALIFICATION_ROOT" <<'PY'
import hashlib
import json
import subprocess
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
head = subprocess.check_output(["git", "-C", sys.argv[2], "rev-parse", "HEAD"], text=True).strip()
tree = subprocess.check_output(["git", "-C", sys.argv[2], "rev-parse", "HEAD^{tree}"], text=True).strip()
assert value["schema"] == "agent-flywheel.installation/v1"
assert value["source"]["head"] == head
assert value["source"]["tree"] == tree
assert len(value["bundle"]["sha256"]) == 64
assert value["authority"]["guest_file"] == "/var/lib/agent-flywheel/doctor-allowlist.json"
assert value["modules"]["approved"] == 8
assert len(value["modules"]["approved_ids"]) == 8
assert value["modules"]["independent_holds"] == []
assert value["modules"]["licensing_cleared"] == 0
assert value["modules"]["licensing_pending"] == 27
digest = value.pop("receipt_sha256")
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
assert digest == hashlib.sha256(canonical).hexdigest()
PY

printf 'Stopped\n' >"$STATUS_FILE"
status_rc=0
status_json="$("$REPO_ROOT/flywheel" status --json)" || status_rc=$?
[[ "$status_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["schema"] == "agent-flywheel.status/v2"
assert value["claim"] == "PARTIAL_SAFE"
assert value["status"] == "Stopped"
assert value["readiness"] == "attention"
vm=value["vm"]
assert vm["healthy"] is False
assert vm["exists"] is True
assert vm["name"] == "agent-flywheel-ubuntu2404"
assert vm["status"] == "Stopped"
assert vm["query_status"] == "ok"
assert vm["contract"]["id"] == "agent-flywheel.mac-vm/v1"
assert vm["contract"]["matches"] is True
assert vm["mismatches"] == []
assert vm["resources"] == {
    "architecture":"aarch64",
    "cpus":6,
    "disk_bytes":73014444032,
    "exposed_guest_ports":False,
    "image":{
        "digest":"sha256:4a281a921b8d7db952895ab619736f10efe9f63e111fa5b5779ed18f023818aa",
        "location":"https://cloud-images.ubuntu.com/releases/24.04/release-20260814/ubuntu-24.04-server-cloudimg-arm64.img",
    },
    "memory_bytes":10737418240,
    "mount_count":0,
    "plain":True,
    "vm_type":"vz",
}
assert value["source"]["clean"] is True
assert value["source"]["matches_installation"] is True
assert value["installation"]["status"] == "recorded"
assert value["installation"]["matches_current_authority"] is True
assert value["modules"]["approved_count"] == 8
assert value["modules"]["pending_licensing_approvals"] == 27
assert value["repository_rollout"] == {"status":"not_connected"}
assert any(item["code"] == "vm_not_running" for item in value["blockers"])
' "$status_json"

"$REPO_ROOT/flywheel" start --quiet
grep -F -- '--stateful -- '"$TEST_ROOT/limactl"' start --tty=false agent-flywheel-ubuntu2404' "$CALLS" >/dev/null

running_json="$("$REPO_ROOT/flywheel" status --json)"
[[ "$running_json" == "$("$REPO_ROOT/flywheel" status --json)" ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["readiness"] == "ready"
assert value["qualification"]["status"] == "pass"
assert value["doctor"]["status"] == "pass"
assert [item["code"] for item in value["blockers"]] == ["receipt_not_connected"]
' "$running_json"
running_text="$("$REPO_ROOT/flywheel" status)"
[[ "$running_text" == *'Flywheel: ready'* ]]
[[ "$running_text" == *'VM: agent-flywheel-ubuntu2404 (Running)'* ]]
[[ "$running_text" == *'VM exists: yes'* ]]
[[ "$running_text" == *'VM resources: vz/aarch64, 6 CPU, 10 GiB memory, 68 GiB disk, plain=true'* ]]
[[ "$running_text" == *'VM contract: match'* ]]
[[ "$running_text" == *'VM mismatches: none'* ]]
[[ "$running_text" == *'Modules: 8 approved; 27 licensing approvals pending'* ]]
[[ "$running_text" == *'Qualification: pass'* ]]
[[ "$running_text" == *'Doctor: pass'* ]]
[[ "$running_text" == *'Repository rollout: not_connected'* ]]
[[ "$running_text" == *'Blocker [repository_rollout]: receipt_not_connected'* ]]

# Fresh qualification and doctor receipts are accepted only when their exact
# schema, digest, installed source/bundle/claim, rows, and summaries agree.
for mutation in wrong-schema extra-field wrong-source wrong-bundle inconsistent-summary bad-digest; do
    export FLYWHEEL_TEST_QUALIFICATION_MUTATION="$mutation"
    forged_status_rc=0
    forged_status_json="$("$REPO_ROOT/flywheel" status --json)" || forged_status_rc=$?
    [[ "$forged_status_rc" -eq 1 ]]
    /usr/bin/python3 -I - "$forged_status_json" "$mutation" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
assert value["readiness"] == "attention", (sys.argv[2], value)
assert value["qualification"]["status"] == "invalid", (sys.argv[2], value)
assert value["doctor"]["status"] == "pass", (sys.argv[2], value)
PY
    unset FLYWHEEL_TEST_QUALIFICATION_MUTATION
done
for mutation in wrong-schema extra-field wrong-claim wrong-source wrong-authority inconsistent-summary bad-digest; do
    export FLYWHEEL_TEST_DOCTOR_MUTATION="$mutation"
    forged_status_rc=0
    forged_status_json="$("$REPO_ROOT/flywheel" status --json)" || forged_status_rc=$?
    [[ "$forged_status_rc" -eq 1 ]]
    /usr/bin/python3 -I - "$forged_status_json" "$mutation" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
assert value["readiness"] == "attention", (sys.argv[2], value)
assert value["qualification"]["status"] == "pass", (sys.argv[2], value)
assert value["doctor"]["status"] == "invalid", (sys.argv[2], value)
PY
    unset FLYWHEEL_TEST_DOCTOR_MUTATION
done
grep -F -- '/bin/bash -p /opt/agent-flywheel-acfs-' "$CALLS" >/dev/null
if grep -E -- '(^|[[:space:]])bash -p /opt/agent-flywheel-acfs-' "$CALLS" >/dev/null; then
    printf 'guest entrypoint was launched through PATH instead of /bin/bash\n' >&2
    exit 1
fi

# Qualification and doctor each repeat the exact guest-source check immediately
# before invoking their committed entrypoint.
git -C "$GUEST_ROOT" update-index --assume-unchanged \
    scripts/flywheel-qualification-host.sh
printf '\nprintf "hidden qualification executed\\n" >&2\n' \
    >>"$GUEST_ROOT/scripts/flywheel-qualification-host.sh"
: >"$CALLS"
hidden_qualification_status_rc=0
hidden_qualification_status_json="$("$REPO_ROOT/flywheel" status --json)" \
    || hidden_qualification_status_rc=$?
[[ "$hidden_qualification_status_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["qualification"]["status"] == "not_run"
assert value["doctor"]["status"] == "not_run"
' "$hidden_qualification_status_json"
if grep -F -- '/scripts/flywheel-qualification-host.sh' "$CALLS" >/dev/null \
    || grep -F -- '/scripts/flywheel-partial-safe-doctor.sh' "$CALLS" >/dev/null; then
    printf 'hidden guest qualification unexpectedly reached execution\n' >&2
    exit 1
fi
git -C "$GUEST_ROOT" update-index --no-assume-unchanged \
    scripts/flywheel-qualification-host.sh
git -C "$GUEST_ROOT" show HEAD:scripts/flywheel-qualification-host.sh \
    >"$GUEST_ROOT/scripts/flywheel-qualification-host.sh"

git -C "$GUEST_ROOT" update-index --skip-worktree \
    scripts/flywheel-partial-safe-doctor.sh
printf '\nprintf "hidden doctor executed\\n" >&2\n' \
    >>"$GUEST_ROOT/scripts/flywheel-partial-safe-doctor.sh"
: >"$CALLS"
hidden_doctor_rc=0
"$REPO_ROOT/flywheel" doctor --json \
    >"$TEST_ROOT/hidden-guest-doctor.out" 2>&1 || hidden_doctor_rc=$?
[[ "$hidden_doctor_rc" -ne 0 ]]
if grep -F -- '/scripts/flywheel-partial-safe-doctor.sh' "$CALLS" >/dev/null; then
    printf 'hidden guest doctor unexpectedly reached execution\n' >&2
    exit 1
fi
git -C "$GUEST_ROOT" update-index --no-skip-worktree \
    scripts/flywheel-partial-safe-doctor.sh
git -C "$GUEST_ROOT" show HEAD:scripts/flywheel-partial-safe-doctor.sh \
    >"$GUEST_ROOT/scripts/flywheel-partial-safe-doctor.sh"

# Every mutating lifecycle command, including stop, shares one kernel-held
# lock. Contenders cannot steal it while the current owner is paused in Lima.
STOP_ENTERED_FILE="$TEST_ROOT/stop-entered"
STOP_RELEASE_FILE="$TEST_ROOT/stop-release"
export FLYWHEEL_TEST_STOP_ENTERED_FILE="$STOP_ENTERED_FILE"
export FLYWHEEL_TEST_STOP_RELEASE_FILE="$STOP_RELEASE_FILE"
: >"$CALLS"
printf 'Running\n' >"$STATUS_FILE"
"$REPO_ROOT/flywheel" stop --quiet >"$TEST_ROOT/stop-holder.out" 2>&1 &
stop_holder_pid=$!
attempts=0
while [[ ! -e "$STOP_ENTERED_FILE" ]]; do
    attempts=$((attempts + 1))
    ((attempts < 100)) || {
        printf 'stop holder did not enter the mocked Lima stop\n' >&2
        exit 1
    }
    sleep 0.05
done
kill -0 "$stop_holder_pid" 2>/dev/null

for conflicting_command in stop start; do
    conflict_rc=0
    "$REPO_ROOT/flywheel" "$conflicting_command" --quiet \
        >"$TEST_ROOT/conflict-$conflicting_command.out" 2>&1 || conflict_rc=$?
    [[ "$conflict_rc" -eq 5 ]]
done
install_conflict_rc=0
HOME="$TEST_ROOT/home" "$REPO_ROOT/flywheel" mac install --quiet \
    >"$TEST_ROOT/conflict-install.out" 2>&1 || install_conflict_rc=$?
[[ "$install_conflict_rc" -eq 5 ]]
if grep -F -- '--stateful --' "$CALLS" >/dev/null; then
    printf 'conflicting install unexpectedly entered the heavy lifecycle guard\n' >&2
    exit 1
fi

contender_pids=()
index=1
while ((index <= 8)); do
    (
        contender_rc=0
        "$REPO_ROOT/flywheel" stop --quiet \
            >"$TEST_ROOT/contender-$index.out" 2>&1 || contender_rc=$?
        printf '%s\n' "$contender_rc" >"$TEST_ROOT/contender-$index.rc"
    ) &
    contender_pids+=("$!")
    index=$((index + 1))
done
for contender_pid in "${contender_pids[@]}"; do
    wait "$contender_pid"
done
index=1
while ((index <= 8)); do
    [[ "$(<"$TEST_ROOT/contender-$index.rc")" == "5" ]]
    index=$((index + 1))
done
[[ "$(grep -c '^stop agent-flywheel-ubuntu2404$' "$CALLS")" -eq 1 ]]
: >"$STOP_RELEASE_FILE"
wait "$stop_holder_pid"
[[ "$(<"$STATUS_FILE")" == "Stopped" ]]
unset FLYWHEEL_TEST_STOP_ENTERED_FILE FLYWHEEL_TEST_STOP_RELEASE_FILE

# Class-7 multi-process TOCTOU regression, stressed ten times. T1 owns the
# kernel lock and is blocked inside the real stop path. TERM must not clean up
# and return; while T1 is still alive, T2 must observe conflict and must not
# enter the mutating Lima stop. Only T1's eventual process exit releases it.
signal_round=1
while ((signal_round <= 10)); do
    SIGNAL_STOP_ENTERED_FILE="$TEST_ROOT/signal-stop-entered-$signal_round"
    SIGNAL_STOP_RELEASE_FILE="$TEST_ROOT/signal-stop-release-$signal_round"
    export FLYWHEEL_TEST_STOP_ENTERED_FILE="$SIGNAL_STOP_ENTERED_FILE"
    export FLYWHEEL_TEST_STOP_RELEASE_FILE="$SIGNAL_STOP_RELEASE_FILE"
    : >"$CALLS"
    printf 'Running\n' >"$STATUS_FILE"
    "$REPO_ROOT/flywheel" stop --quiet \
        >"$TEST_ROOT/signal-holder-$signal_round.out" 2>&1 &
    signal_holder_pid=$!
    attempts=0
    while [[ ! -e "$SIGNAL_STOP_ENTERED_FILE" ]]; do
        attempts=$((attempts + 1))
        ((attempts < 100)) || {
            printf 'signal holder did not enter mocked Lima stop in round %s\n' \
                "$signal_round" >&2
            exit 1
        }
        sleep 0.05
    done

    kill -TERM "$signal_holder_pid"
    kill -0 "$signal_holder_pid" 2>/dev/null
    signal_contender_rc=0
    "$REPO_ROOT/flywheel" stop --quiet \
        >"$TEST_ROOT/signal-contender-$signal_round.out" 2>&1 \
        || signal_contender_rc=$?
    [[ "$signal_contender_rc" -eq 5 ]]
    [[ "$(grep -c '^stop agent-flywheel-ubuntu2404$' "$CALLS")" -eq 1 ]]
    [[ "$(<"$STATUS_FILE")" == "Running" ]]

    : >"$SIGNAL_STOP_RELEASE_FILE"
    signal_holder_rc=0
    wait "$signal_holder_pid" || signal_holder_rc=$?
    [[ "$signal_holder_rc" -eq 143 ]]
    [[ "$(<"$STATUS_FILE")" == "Stopped" ]]
    signal_round=$((signal_round + 1))
done
unset FLYWHEEL_TEST_STOP_ENTERED_FILE FLYWHEEL_TEST_STOP_RELEASE_FILE

# PID-shaped stale metadata has no ownership authority. Only the kernel flock
# matters, so PID reuse cannot cause a false conflict.
printf '{"owner_pid":%s,"schema":"agent-flywheel.lifecycle-lock/v1"}\n' "$$" \
    >"$FLYWHEEL_STATE_HOME/locks/lifecycle.lock/owner.lock"
printf 'Running\n' >"$STATUS_FILE"
"$REPO_ROOT/flywheel" stop --quiet
[[ "$(<"$STATUS_FILE")" == "Stopped" ]]

# A live kernel owner blocks stop; an abrupt owner death releases the lock even
# though its metadata file remains.
printf 'Running\n' >"$STATUS_FILE"
python3 - \
    "$FLYWHEEL_STATE_HOME/locks/lifecycle.lock/owner.lock" \
    "$TEST_ROOT/external-lock-ready" <<'PY' &
import fcntl
import os
import sys
import time

descriptor = os.open(sys.argv[1], os.O_RDWR | os.O_NOFOLLOW)
fcntl.flock(descriptor, fcntl.LOCK_EX)
os.ftruncate(descriptor, 0)
os.write(descriptor, b'{"schema":"agent-flywheel.lifecycle-lock/v1","owner_pid":999999}\n')
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    handle.write("ready\n")
time.sleep(60)
PY
external_lock_pid=$!
attempts=0
while [[ ! -s "$TEST_ROOT/external-lock-ready" ]]; do
    attempts=$((attempts + 1))
    ((attempts < 100)) || {
        printf 'external lock helper did not become ready\n' >&2
        exit 1
    }
    sleep 0.05
done
external_conflict_rc=0
"$REPO_ROOT/flywheel" stop --quiet \
    >"$TEST_ROOT/external-conflict.out" 2>&1 || external_conflict_rc=$?
[[ "$external_conflict_rc" -eq 5 ]]
kill "$external_lock_pid"
wait "$external_lock_pid" 2>/dev/null || true
"$REPO_ROOT/flywheel" stop --quiet
[[ "$(<"$STATUS_FILE")" == "Stopped" ]]
printf 'Running\n' >"$STATUS_FILE"

printf '{"schema":"agent-flywheel.repository-rollout/v1","status":"pass","scope":"live-repository-rollout","repository":"synthetic/local","bookclub_eligible":true}\n' \
    >"$TEST_ROOT/rollout.json"
rollout_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/rollout.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
rollout=value["repository_rollout"]
assert rollout["status"] == "invalid"
assert "unbound generic repository rollout receipts are not trusted" in rollout["error"]
assert [item["code"] for item in value["blockers"]] == ["receipt_invalid"]
' "$rollout_json"

cp "$REPO_ROOT/tests/unit/fixtures/ops-github-admission-synthetic-202040d1.json" \
    "$TEST_ROOT/synthetic-pilot.json"
synthetic_status_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/synthetic-pilot.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
rollout=value["repository_rollout"]
assert rollout["status"] == "evidence_connected"
assert rollout["schema"] == "ops-steward.github-admission-synthetic-pilot-receipt/v1"
assert rollout["declared_status"] == "pass"
assert rollout["scope"] == "synthetic-pilot-only"
assert rollout["repository"] == "kjgryboski/ops-steward"
assert rollout["bookclub_eligible"] is True
assert rollout["external_mutation"] is False
assert rollout["git"]["clean"] is True
assert rollout["git"]["head"] == "202040d1b72183225dfdfc665be78ad429eba3ff"
assert rollout["git"]["tree"] == "32be2a7b7b2940e45de2d2e847fbb9b14866c962"
assert rollout["receipt_sha256"] == "e01f5ca3f3ab55da1a2cf932f4643d6d0a68cac73c13d22b4baff02c3df9c58e"
assert rollout["artifact_sha256"] == "6a6232d3c98a56d6740f3382353cae785882d7ede2c51a2b28a0a0ef263544aa"
assert rollout["tests"]["run"] == 10
assert {field: rollout["tests"][field] for field in ("failures","errors","skipped")} == {
    "failures":0,"errors":0,"skipped":0,
}
assert all(rollout["claims"][claim] == "PASS" for claim in (
    "authenticated_webhook_ingestion",
    "duplicate_delivery",
    "forced_peer_first_concurrency_100_iterations",
    "one_create_zero_duplicate_updates_revision_one",
    "component_restart_retained_replay_zero_provider_io",
    "failure_closure_and_ambiguous_recovery",
))
assert rollout["claims"]["live_postgres_restart"] == "NOT_RUN"
assert rollout["claims"]["live_github_publication"] == "NOT_RUN"
assert [item["code"] for item in value["blockers"]] == ["live_rollout_not_proven"]
' "$synthetic_status_json"
synthetic_status_text="$("$REPO_ROOT/flywheel" status --rollout-receipt "$TEST_ROOT/synthetic-pilot.json")"
[[ "$synthetic_status_text" == *'Flywheel: ready'* ]]
[[ "$synthetic_status_text" == *'Repository rollout: evidence_connected'* ]]
[[ "$synthetic_status_text" == *'Blocker [repository_rollout]: live_rollout_not_proven'* ]]

python3 - "$TEST_ROOT/synthetic-pilot.json" "$TEST_ROOT/contradictory-pilot.json" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["bookclub_eligible"] = False
value.pop("receipt_sha256")
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["receipt_sha256"] = hashlib.sha256(canonical).hexdigest()
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    handle.write("\n")
PY
contradictory_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/contradictory-pilot.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "verdict and BookClub eligibility contradict" in value["repository_rollout"]["error"]
' "$contradictory_json"

python3 - "$TEST_ROOT/synthetic-pilot.json" "$TEST_ROOT/malformed-pilot.json" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["git"]["head"] = "A" * 40
value.pop("receipt_sha256")
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["receipt_sha256"] = hashlib.sha256(canonical).hexdigest()
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    handle.write("\n")
PY
malformed_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/malformed-pilot.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "exact lowercase Git object IDs" in value["repository_rollout"]["error"]
' "$malformed_json"

python3 - "$TEST_ROOT/synthetic-pilot.json" "$TEST_ROOT/unproven-pilot.json" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["claims"]["duplicate_delivery"] = "UNPROVEN"
value.pop("receipt_sha256")
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["receipt_sha256"] = hashlib.sha256(canonical).hexdigest()
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    handle.write("\n")
PY
unproven_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/unproven-pilot.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "claim outcomes contradict" in value["repository_rollout"]["error"]
' "$unproven_json"

ln -s "$TEST_ROOT/rollout.json" "$TEST_ROOT/rollout-link.json"
linked_rollout_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/rollout-link.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert [item["code"] for item in value["blockers"]] == ["receipt_invalid"]
' "$linked_rollout_json"

doctor_json="$("$REPO_ROOT/flywheel" doctor --json)"
python3 -c 'import json,sys; value=json.loads(sys.argv[1]); assert value["status"] == "pass"' "$doctor_json"
grep -F -- 'scripts/flywheel-partial-safe-doctor.sh --json' "$CALLS" >/dev/null
doctor_text="$("$REPO_ROOT/flywheel" doctor)"
python3 -c 'import json,sys; value=json.loads(sys.argv[1]); assert value["status"] == "pass"' "$doctor_text"
grep -E -- 'scripts/flywheel-partial-safe-doctor\.sh$' "$CALLS" >/dev/null

capabilities_json="$("$REPO_ROOT/flywheel" capabilities --json)"
[[ "$capabilities_json" == "$("$REPO_ROOT/flywheel" capabilities --json)" ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["schema"] == "agent-flywheel.capabilities/v1"
assert value["exit_codes"]["5"] == "operation_conflict"
assert value["feature_flags"]["portable_qualification_host"] is True
assert any(item["command"] == "flywheel status --json" for item in value["commands"])
assert any(item["command"] == "flywheel repository inspect PATH --json" for item in value["commands"])
' "$capabilities_json"
"$REPO_ROOT/flywheel" robot-docs guide | grep -F 'flywheel status --json --rollout-receipt FILE' >/dev/null

inspection_json="$("$REPO_ROOT/flywheel" repository inspect "$QUALIFICATION_ROOT" --json)"
[[ "$inspection_json" == "$("$REPO_ROOT/flywheel" repository inspect "$QUALIFICATION_ROOT" --json)" ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["schema"] == "agent-flywheel.repository-inspection/v1"
assert value["status"] == "ready_for_bounded_setup_pr"
assert value["mutation_authorized"] is False
assert value["repository"]["clean"] is True
assert value["guidance"]["root_agents"]["path"] == "AGENTS.md"
assert value["guidance"]["unresolved_acfs_new"] == []
assert value["automation"]["github_workflows"] == [".github/workflows/test.yml"]
assert value["admission"]["live_rollout_eligible"] is False
assert len(value["inspection_sha256"]) == 64
' "$inspection_json"

# Read-only repository inspection must not execute repository-configured hooks.
cat >"$TEST_ROOT/fsmonitor-hook" <<'SH'
#!/usr/bin/env bash
: >"$FLYWHEEL_TEST_FSMONITOR_MARKER"
printf '{}\n'
SH
chmod 0755 "$TEST_ROOT/fsmonitor-hook"
export FLYWHEEL_TEST_FSMONITOR_MARKER="$TEST_ROOT/fsmonitor-ran"

# Host Git probes are hermetic even when the caller injects repository,
# alternate-index, configuration-count, object-store, and trace variables.
ambient_inspection_json="$(
    GIT_DIR="$TEST_ROOT/ambient-git-dir" \
    GIT_WORK_TREE="$TEST_ROOT/ambient-work-tree" \
    GIT_INDEX_FILE="$TEST_ROOT/ambient-index" \
    GIT_OBJECT_DIRECTORY="$TEST_ROOT/ambient-objects" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$TEST_ROOT/ambient-alternates" \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=core.fsmonitor \
    GIT_CONFIG_VALUE_0="$TEST_ROOT/fsmonitor-hook" \
    GIT_TRACE="$TEST_ROOT/ambient-git-trace" \
    "$REPO_ROOT/flywheel" repository inspect "$QUALIFICATION_ROOT" --json
)"
[[ "$ambient_inspection_json" == "$inspection_json" ]]
[[ ! -e "$FLYWHEEL_TEST_FSMONITOR_MARKER" ]]
[[ ! -e "$TEST_ROOT/ambient-git-trace" ]]

git -C "$QUALIFICATION_ROOT" config core.fsmonitor "$TEST_ROOT/fsmonitor-hook"
"$REPO_ROOT/flywheel" repository inspect "$QUALIFICATION_ROOT" --json >/dev/null
[[ ! -e "$FLYWHEEL_TEST_FSMONITOR_MARKER" ]]
git -C "$QUALIFICATION_ROOT" config --unset core.fsmonitor

# Direct repository and rollout commands never import working-tree validator
# bytes. Hidden and ordinary validator drift both fail before Python executes.
export FLYWHEEL_TEST_DIRECT_VALIDATOR_MARKER="$TEST_ROOT/direct-validator-ran"
git -C "$QUALIFICATION_ROOT" update-index --assume-unchanged \
    scripts/flywheel-repository-control.py
cat >>"$QUALIFICATION_ROOT/scripts/flywheel-repository-control.py" <<'PY'
with open(os.environ["FLYWHEEL_TEST_DIRECT_VALIDATOR_MARKER"], "w", encoding="utf-8") as handle:
    handle.write("unsafe")
PY
hidden_direct_rc=0
hidden_direct_error="$("$REPO_ROOT/flywheel" repository inspect \
    "$QUALIFICATION_ROOT" --json 2>&1)" || hidden_direct_rc=$?
[[ "$hidden_direct_rc" -eq 2 ]]
[[ "$hidden_direct_error" == *'unsafe assume-unchanged, skip-worktree, or unmerged index flags'* ]]
[[ ! -e "$FLYWHEEL_TEST_DIRECT_VALIDATOR_MARKER" ]]
git -C "$QUALIFICATION_ROOT" update-index --no-assume-unchanged \
    scripts/flywheel-repository-control.py
git -C "$QUALIFICATION_ROOT" show HEAD:scripts/flywheel-repository-control.py \
    >"$QUALIFICATION_ROOT/scripts/flywheel-repository-control.py"

cat >>"$QUALIFICATION_ROOT/scripts/flywheel-repository-control.py" <<'PY'
with open(os.environ["FLYWHEEL_TEST_DIRECT_VALIDATOR_MARKER"], "w", encoding="utf-8") as handle:
    handle.write("unsafe")
PY
mutable_direct_rc=0
mutable_direct_error="$("$REPO_ROOT/flywheel" rollout plan \
    "$TEST_ROOT/not-read-while-validator-is-mutable.json" --json 2>&1)" \
    || mutable_direct_rc=$?
[[ "$mutable_direct_rc" -eq 2 ]]
[[ "$mutable_direct_error" == *'ACFS source checkout has uncommitted changes'* ]]
[[ ! -e "$FLYWHEEL_TEST_DIRECT_VALIDATOR_MARKER" ]]
git -C "$QUALIFICATION_ROOT" show HEAD:scripts/flywheel-repository-control.py \
    >"$QUALIFICATION_ROOT/scripts/flywheel-repository-control.py"

# Isolated Python execution prevents current-directory module shadowing.
mkdir -p "$TEST_ROOT/import-trap"
export FLYWHEEL_TEST_CWD_IMPORT_MARKER="$TEST_ROOT/cwd-import-ran"
cat >"$TEST_ROOT/import-trap/datetime.py" <<'PY'
import os
with open(os.environ["FLYWHEEL_TEST_CWD_IMPORT_MARKER"], "w", encoding="utf-8") as handle:
    handle.write("unsafe")
PY
(
    cd "$TEST_ROOT/import-trap"
    "$REPO_ROOT/flywheel" repository inspect "$QUALIFICATION_ROOT" --json >/dev/null
)
[[ ! -e "$TEST_ROOT/cwd-import-ran" ]]

# Hidden index state is never accepted as a clean target.
git -C "$QUALIFICATION_ROOT" update-index --assume-unchanged VERSION
printf 'hidden drift\n' >"$QUALIFICATION_ROOT/VERSION"
hidden_target_rc=0
hidden_target_error="$("$REPO_ROOT/flywheel" repository inspect "$QUALIFICATION_ROOT" --json 2>&1)" \
    || hidden_target_rc=$?
[[ "$hidden_target_rc" -eq 2 ]]
[[ "$hidden_target_error" == *'unsafe assume-unchanged, skip-worktree, or unmerged index flags'* ]]
git -C "$QUALIFICATION_ROOT" update-index --no-assume-unchanged VERSION
printf '0.8.0\n' >"$QUALIFICATION_ROOT/VERSION"
git -C "$QUALIFICATION_ROOT" update-index --skip-worktree AGENTS.md
skip_target_rc=0
skip_target_error="$("$REPO_ROOT/flywheel" repository inspect "$QUALIFICATION_ROOT" --json 2>&1)" \
    || skip_target_rc=$?
[[ "$skip_target_rc" -eq 2 ]]
[[ "$skip_target_error" == *'unsafe assume-unchanged, skip-worktree, or unmerged index flags'* ]]
git -C "$QUALIFICATION_ROOT" update-index --no-skip-worktree AGENTS.md

# GitHub origin identities are deliberately narrower than general Git URLs.
python3 -I - "$REPO_ROOT/scripts/flywheel-repository-control.py" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("flywheel_repository_control", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
assert module.canonical_github_repository("https://github.com/Owner/repo.git") == "owner/repo"
assert module.canonical_github_repository("git@github.com:Owner/repo.git") == "owner/repo"
assert module.canonical_github_repository("ssh://git@github.com/Owner/repo.git") == "owner/repo"
for candidate in (
    "https://github.com:bogus/owner/repo.git",
    "git://attacker@github.com/owner/repo.git",
    "ssh://github.com/owner/repo.git",
    "https://github.com/./repo.git",
    "https://github.com/../repo.git",
    "https://github.com//owner/repo.git",
    "https://github.com/owner/repo.git/",
):
    try:
        module.canonical_github_repository(candidate)
    except module.ControlError:
        continue
    raise AssertionError(f"unsafe GitHub origin accepted: {candidate}")
PY

FORGED_OPS_SOURCE="$TEST_ROOT/ops-source"
OPS_SOURCE="$FORGED_OPS_SOURCE"
mkdir -p \
    "$OPS_SOURCE/scripts" \
    "$OPS_SOURCE/tests" \
    "$OPS_SOURCE/src/ops_steward"
git -C "$OPS_SOURCE" init -q -b main
git -C "$OPS_SOURCE" remote add origin https://github.com/kjgryboski/ops-steward.git
printf 'pilot producer fixture\n' >"$OPS_SOURCE/scripts/run-github-admission-synthetic-pilot.py"
printf 'pilot test fixture\n' >"$OPS_SOURCE/tests/test_github_admission_synthetic_pilot.py"
printf 'producer fixture\n' >"$OPS_SOURCE/src/ops_steward/github_admission_producer.py"
printf 'store fixture\n' >"$OPS_SOURCE/src/ops_steward/github_admission_store.py"
printf 'webhook fixture\n' >"$OPS_SOURCE/src/ops_steward/github_admission_webhook.py"
git -C "$OPS_SOURCE" add .
git -C "$OPS_SOURCE" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm pilot-source

TARGET_ROOT="$TEST_ROOT/bookclub-target"
mkdir -p "$TARGET_ROOT"
git -C "$TARGET_ROOT" init -q -b main
git -C "$TARGET_ROOT" remote add origin https://github.com/example/bookclub.git
printf '# Repository instructions\n' >"$TARGET_ROOT/AGENTS.md"
printf '# BookClub fixture\n' >"$TARGET_ROOT/README.md"
git -C "$TARGET_ROOT" add AGENTS.md README.md
git -C "$TARGET_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm initial
git -C "$TARGET_ROOT" update-ref refs/remotes/origin/main HEAD

python3 - \
    "$REPO_ROOT/tests/unit/fixtures/ops-github-admission-synthetic-202040d1.json" \
    "$OPS_SOURCE" \
    "$TEST_ROOT/bound-pilot.json" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

template_path, source_path, output_path = sys.argv[1:]
source = pathlib.Path(source_path)
with open(template_path, encoding="utf-8") as handle:
    value = json.load(handle)
value["git"] = {
    "clean": True,
    "head": subprocess.check_output(["git", "-C", source_path, "rev-parse", "HEAD"], text=True).strip(),
    "tree": subprocess.check_output(["git", "-C", source_path, "rev-parse", "HEAD^{tree}"], text=True).strip(),
}
value["evidence_sha256"] = {
    relative: hashlib.sha256((source / relative).read_bytes()).hexdigest()
    for relative in value["evidence_sha256"]
}
value.pop("receipt_sha256")
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["receipt_sha256"] = hashlib.sha256(canonical).hexdigest()
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    handle.write("\n")
PY

forged_pilot_rc=0
forged_pilot_error="$("$REPO_ROOT/flywheel" repository eligibility "$TARGET_ROOT" \
    --pilot-receipt "$TEST_ROOT/bound-pilot.json" \
    --pilot-source "$OPS_SOURCE" \
    --target-repository example/bookclub \
    --json 2>&1)" || forged_pilot_rc=$?
[[ "$forged_pilot_rc" -eq 2 ]]
[[ "$forged_pilot_error" == *'not the approved producer-sealed content address'* ]]

OPS_SOURCE="${ACFS_TEST_TRUSTED_OPS_SOURCE:-}"
if [[ -n "$OPS_SOURCE" \
    && "$(git -C "$OPS_SOURCE" rev-parse HEAD 2>/dev/null || true)" == "202040d1b72183225dfdfc665be78ad429eba3ff" ]]; then
cp "$REPO_ROOT/tests/unit/fixtures/ops-github-admission-synthetic-202040d1.json" \
    "$TEST_ROOT/bound-pilot.json"
eligibility_json="$("$REPO_ROOT/flywheel" repository eligibility "$TARGET_ROOT" \
    --pilot-receipt "$TEST_ROOT/bound-pilot.json" \
    --pilot-source "$OPS_SOURCE" \
    --target-repository example/bookclub \
    --json)"
[[ "$eligibility_json" == "$("$REPO_ROOT/flywheel" repository eligibility "$TARGET_ROOT" \
    --pilot-receipt "$TEST_ROOT/bound-pilot.json" \
    --pilot-source "$OPS_SOURCE" \
    --target-repository example/bookclub \
    --json)" ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["schema"] == "agent-flywheel.repository-live-pilot-eligibility/v1"
assert value["status"] == "eligible"
assert value["outcome"] == "eligible_for_separately_authorized_live_pilot"
assert value["mutation_authorized"] is False
assert value["live_rollout_passed"] is False
assert value["synthetic_pilot_accepted"] is True
assert value["pilot"]["receipt"]["repository"] == "kjgryboski/ops-steward"
assert value["pilot"]["receipt"]["tests"]["run"] == 10
assert value["pilot"]["source"]["clean"] is True
assert value["pilot"]["source"]["evidence_verified"] is True
assert value["target"]["repository"] == "example/bookclub"
assert value["target"]["branch"] == "main"
assert value["target"]["head"] == value["target"]["upstream"]["head"]
assert value["target"]["tree"] == value["target"]["upstream"]["tree"]
assert value["target"]["divergence"] == {"ahead":0,"behind":0}
assert value["target"]["instructions"]["path"] == "AGENTS.md"
assert len(value["target"]["instructions"]["sha256"]) == 64
assert len(value["eligibility_sha256"]) == 64
' "$eligibility_json"
printf '%s\n' "$eligibility_json" >"$TEST_ROOT/eligibility.json"
eligibility_status="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/eligibility.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
rollout=value["repository_rollout"]
assert rollout["status"] == "evidence_connected"
assert rollout["scope"] == "live-pilot-eligibility-only"
assert rollout["repository"] == "example/bookclub"
assert rollout["mutation_authorized"] is False
assert rollout["live_rollout_passed"] is False
assert [item["code"] for item in value["blockers"]] == ["live_rollout_not_proven"]
' "$eligibility_status"

python3 - "$TEST_ROOT/eligibility.json" "$TEST_ROOT/forged-eligibility.json" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
receipt = value["pilot"]["receipt"]
receipt["git"]["head"] = "f" * 40
receipt.pop("receipt_sha256")
receipt_source = (json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
receipt["receipt_sha256"] = hashlib.sha256(receipt_source).hexdigest()
receipt_artifact = (json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()
value["pilot"]["artifact_sha256"] = hashlib.sha256(receipt_artifact).hexdigest()
value.pop("eligibility_sha256")
eligibility_source = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
value["eligibility_sha256"] = hashlib.sha256(eligibility_source).hexdigest()
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY
forged_eligibility_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/forged-eligibility.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "not the approved producer-sealed content address" in value["repository_rollout"]["error"]
' "$forged_eligibility_status"

python3 - "$TEST_ROOT/eligibility.json" "$TEST_ROOT/missing-source-eligibility.json" "$TEST_ROOT/missing-target-eligibility.json" <<'PY'
import hashlib
import json
import sys

def write_with_digest(value, path):
    value.pop("eligibility_sha256")
    canonical = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    value["eligibility_sha256"] = hashlib.sha256(canonical).hexdigest()
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(value, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")

with open(sys.argv[1], encoding="utf-8") as handle:
    source_missing = json.load(handle)
source_missing["pilot"]["source"]["root"] += "-missing"
write_with_digest(source_missing, sys.argv[2])
with open(sys.argv[1], encoding="utf-8") as handle:
    target_missing = json.load(handle)
target_missing["target"]["root"] += "-missing"
write_with_digest(target_missing, sys.argv[3])
PY
for missing_receipt in \
    "$TEST_ROOT/missing-source-eligibility.json" \
    "$TEST_ROOT/missing-target-eligibility.json"; do
    missing_status="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$missing_receipt")"
    python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert [item["code"] for item in value["blockers"]] == ["receipt_invalid"]
' "$missing_status"
done

printf 'target drift\n' >"$TARGET_ROOT/drift.txt"
target_dirty_status="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/eligibility.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "target repository is dirty" in value["repository_rollout"]["error"]
' "$target_dirty_status"
git -C "$TARGET_ROOT" add drift.txt
git -C "$TARGET_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm target-drift
target_drift_rc=0
target_drift_error="$("$REPO_ROOT/flywheel" repository eligibility "$TARGET_ROOT" \
    --pilot-receipt "$TEST_ROOT/bound-pilot.json" \
    --pilot-source "$OPS_SOURCE" \
    --target-repository example/bookclub \
    --json 2>&1)" || target_drift_rc=$?
[[ "$target_drift_rc" -eq 2 ]]
[[ "$target_drift_error" == *'target repository has drifted from the locally observed origin/main'* ]]
target_head_drift_status="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/eligibility.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "target repository has drifted from the locally observed origin/main" in value["repository_rollout"]["error"]
' "$target_head_drift_status"

git -C "$TARGET_ROOT" update-ref refs/remotes/origin/main HEAD
eligibility_after_head="$("$REPO_ROOT/flywheel" repository eligibility "$TARGET_ROOT" \
    --pilot-receipt "$TEST_ROOT/bound-pilot.json" \
    --pilot-source "$OPS_SOURCE" \
    --target-repository example/bookclub \
    --json)"
printf '%s\n' "$eligibility_after_head" >"$TEST_ROOT/eligibility-after-head.json"
git -C "$TARGET_ROOT" remote set-url origin https://github.com/example/other.git
target_remote_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/eligibility-after-head.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "target origin identifies example/other, expected example/bookclub" in value["repository_rollout"]["error"]
' "$target_remote_status"
git -C "$TARGET_ROOT" remote set-url origin https://github.com/example/bookclub.git

git -C "$TARGET_ROOT" update-index --assume-unchanged AGENTS.md
printf '# Drifted repository instructions\n' >"$TARGET_ROOT/AGENTS.md"
target_instructions_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/eligibility-after-head.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "unsafe assume-unchanged, skip-worktree, or unmerged index flags" in value["repository_rollout"]["error"]
' "$target_instructions_status"

python3 - "$TEST_ROOT/eligibility-after-head.json" "$TEST_ROOT/source-drift-eligibility.json" "$FORGED_OPS_SOURCE" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["pilot"]["source"]["root"] = sys.argv[3]
value.pop("eligibility_sha256")
canonical = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
value["eligibility_sha256"] = hashlib.sha256(canonical).hexdigest()
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY
source_drift_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/source-drift-eligibility.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "Ops pilot source has drifted from the sealed receipt" in value["repository_rollout"]["error"]
' "$source_drift_status"
fi

python3 - "$TEST_ROOT/rollout-inventory.json" "$QUALIFICATION_ROOT" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({
        "schema": "agent-flywheel.rollout-inventory/v1",
        "repositories": [{"path": sys.argv[2], "cohort": "pilot"}],
    }, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY
plan_json="$("$REPO_ROOT/flywheel" rollout plan "$TEST_ROOT/rollout-inventory.json" --json)"
[[ "$plan_json" == "$("$REPO_ROOT/flywheel" rollout plan "$TEST_ROOT/rollout-inventory.json" --json)" ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["schema"] == "agent-flywheel.progressive-rollout-plan/v1"
assert value["status"] == "ready_for_setup_prs"
assert value["execution_status"] == "plan_only"
assert value["mutation_authorized"] is False
assert value["repository_count"] == 1
assert value["cohorts"][0]["cohort"] == "pilot"
assert value["cohorts"][0]["live_rollout_eligible"] is False
assert len(value["plan_sha256"]) == 64
' "$plan_json"
printf '%s\n' "$plan_json" >"$TEST_ROOT/rollout-plan.json"
plan_status_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/rollout-plan.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
rollout=value["repository_rollout"]
assert rollout["status"] == "evidence_connected"
assert rollout["schema"] == "agent-flywheel.progressive-rollout-plan/v1"
assert rollout["scope"] == "plan-only"
assert rollout["repository_count"] == 1
assert rollout["repository"]["name"] == "qualification-source"
assert rollout["repositories"] == [rollout["repository"]]
assert rollout["setup_pr_eligible"] is True
assert rollout["live_rollout_eligible"] is False
assert rollout["bookclub_eligible"] is None
assert [item["code"] for item in value["blockers"]] == ["live_rollout_not_proven"]
' "$plan_status_json"
python3 - "$TEST_ROOT/rollout-plan.json" "$TEST_ROOT/tampered-rollout-plan.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["repository_count"] = 2
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY
tampered_plan_status_json="$("$REPO_ROOT/flywheel" status --json --rollout-receipt "$TEST_ROOT/tampered-rollout-plan.json")"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert [item["code"] for item in value["blockers"]] == ["receipt_invalid"]
' "$tampered_plan_status_json"

git -C "$QUALIFICATION_ROOT" update-index --assume-unchanged \
    scripts/flywheel-repository-control.py
cat >>"$QUALIFICATION_ROOT/scripts/flywheel-repository-control.py" <<'PY'
with open(os.environ["FLYWHEEL_TEST_HIDDEN_VALIDATOR_MARKER"], "w", encoding="utf-8") as handle:
    handle.write("executed")
PY
export FLYWHEEL_TEST_HIDDEN_VALIDATOR_MARKER="$TEST_ROOT/hidden-validator-ran"
hidden_validator_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/rollout-plan.json")" || true
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "clean exact source" in value["repository_rollout"]["error"]
' "$hidden_validator_status"
[[ ! -e "$FLYWHEEL_TEST_HIDDEN_VALIDATOR_MARKER" ]]
git -C "$QUALIFICATION_ROOT" update-index --no-assume-unchanged \
    scripts/flywheel-repository-control.py
cp "$REPO_ROOT/scripts/flywheel-repository-control.py" \
    "$QUALIFICATION_ROOT/scripts/flywheel-repository-control.py"

printf 'validator trust drift\n' >"$QUALIFICATION_ROOT/validator-trust-drift.txt"
# Installation remains the one lifecycle command that requires a clean current
# source. It must refuse before locking, staging, or entering the heavy guard.
: >"$CALLS"
dirty_install_rc=0
HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" mac install --quiet \
    >"$TEST_ROOT/dirty-install.out" 2>&1 || dirty_install_rc=$?
[[ "$dirty_install_rc" -eq 2 ]]
if grep -F -- '--stateful --' "$CALLS" >/dev/null; then
    printf 'dirty install unexpectedly entered the heavy lifecycle guard\n' >&2
    exit 1
fi
dirty_validator_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/rollout-plan.json")" || true
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["repository_rollout"]["status"] == "invalid"
assert "requires the clean exact source recorded by the installation receipt" in value["repository_rollout"]["error"]
' "$dirty_validator_status"
git -C "$QUALIFICATION_ROOT" add validator-trust-drift.txt
git -C "$QUALIFICATION_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm validator-source-drift
drifted_validator_status="$("$REPO_ROOT/flywheel" status --json \
    --rollout-receipt "$TEST_ROOT/rollout-plan.json")" || true
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["source"]["clean"] is True, value
assert value["source"]["matches_installation"] is False, value
assert value["repository_rollout"]["status"] == "invalid", value
assert "requires the clean exact source recorded by the installation receipt" in value["repository_rollout"]["error"], value
' "$drifted_validator_status"

# An advanced clean checkout whose authority differs from the installation is
# a lifecycle blocker while that checkout is present. Installed work remains
# bound to its receipt, but the mismatch cannot be reported as ready.
RECORDED_HEAD="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source"]["head"])' \
    "$FLYWHEEL_STATE_HOME/installation.json")"
RECORDED_GUEST_ROOT="/opt/agent-flywheel-acfs-$RECORDED_HEAD"
cp "$REPO_ROOT/config/flywheel-license-clearance.json" \
    "$QUALIFICATION_ROOT/config/flywheel-license-clearance.json"
git -C "$QUALIFICATION_ROOT" add config/flywheel-license-clearance.json
git -C "$QUALIFICATION_ROOT" -c user.name=Flywheel -c user.email=flywheel.invalid@example.test \
    commit -qm advanced-checkout-authority
: >"$CALLS"
advanced_status_rc=0
advanced_status_json="$(HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" status --json)" \
    || advanced_status_rc=$?
[[ "$advanced_status_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["readiness"] == "attention"
assert value["installation"]["status"] == "recorded"
assert value["installation"]["matches_current_authority"] is False
assert value["source"]["clean"] is True
assert value["source"]["matches_installation"] is False
assert value["installed_source"]["head"] == sys.argv[2]
assert value["qualification"]["status"] == "pass"
assert value["doctor"]["status"] == "pass"
assert [item["code"] for item in value["blockers"]] == ["current_authority_mismatch", "receipt_not_connected"]
' "$advanced_status_json" "$RECORDED_HEAD"
HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" doctor --json >/dev/null
grep -F -- "$RECORDED_GUEST_ROOT/scripts/flywheel-qualification-host.sh" "$CALLS" >/dev/null
grep -F -- 'ACFS_PARTIAL_SAFE_ALLOWLIST_FILE=/var/lib/agent-flywheel/doctor-allowlist.json' "$CALLS" >/dev/null
if grep -F -- 'ACFS_LICENSE_CLEARANCE_FILE=' "$CALLS" >/dev/null; then
    printf 'advanced checkout authority incorrectly replaced the installed authority\n' >&2
    exit 1
fi

# Moving or removing the original checkout cannot strand status or doctor.
# The installed launcher continues from the exact validated receipt snapshot.
MOVED_QUALIFICATION_ROOT="$TEST_ROOT/qualification-source-moved"
RETAINED_DELETED_ROOT="$TEST_ROOT/qualification-source-retained"
mv "$QUALIFICATION_ROOT" "$MOVED_QUALIFICATION_ROOT"
printf '%s\n' "$MOVED_QUALIFICATION_ROOT" >"$FLYWHEEL_STATE_HOME/source-root"
unset FLYWHEEL_SOURCE_REPO
moved_status_rc=0
moved_status_json="$(HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" status --json)" \
    || moved_status_rc=$?
[[ "$moved_status_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["readiness"] == "attention"
assert value["source"]["root"].endswith("qualification-source-moved")
assert value["source"]["matches_installation"] is False
assert value["installed_source"]["head"] == sys.argv[2]
assert [item["code"] for item in value["blockers"]] == ["current_authority_mismatch", "receipt_not_connected"]
' "$moved_status_json" "$RECORDED_HEAD"
HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" doctor --json >/dev/null

mv "$MOVED_QUALIFICATION_ROOT" "$RETAINED_DELETED_ROOT"
deleted_status_json="$(HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" status --json)"
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["readiness"] == "ready"
assert value["source"] == {"clean":None,"head":None,"matches_installation":None,"root":None,"tree":None}
assert value["installed_source"]["head"] == sys.argv[2]
assert value["qualification"]["status"] == "pass"
assert value["doctor"]["status"] == "pass"
assert [item["code"] for item in value["blockers"]] == ["receipt_not_connected"]
' "$deleted_status_json" "$RECORDED_HEAD"
HOME="$TEST_ROOT/home" "$TEST_ROOT/home/.local/bin/flywheel" doctor --json >/dev/null

mv "$RETAINED_DELETED_ROOT" "$QUALIFICATION_ROOT"
printf '%s\n' "$QUALIFICATION_ROOT" >"$FLYWHEEL_STATE_HOME/source-root"
export FLYWHEEL_SOURCE_REPO="$QUALIFICATION_ROOT"

# State reads are nofollow, nonblocking, and bounded. Unsafe receipts fail
# closed and cannot select a guest source or authority.
VALID_INSTALL_RECEIPT="$TEST_ROOT/installation-valid.json"
mv "$FLYWHEEL_STATE_HOME/installation.json" "$VALID_INSTALL_RECEIPT"
ln -s "$TEST_ROOT/symlink-target" "$FLYWHEEL_STATE_HOME/installation.json"
: >"$CALLS"
unsafe_status_rc=0
unsafe_status_json="$("$REPO_ROOT/flywheel" status --json)" || unsafe_status_rc=$?
[[ "$unsafe_status_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["installation"]["status"] == "receipt_invalid"
assert any(item["code"] == "installation_receipt_invalid" for item in value["blockers"])
assert value["qualification"]["status"] == "not_run"
assert value["doctor"]["status"] == "not_run"
' "$unsafe_status_json"
unsafe_doctor_rc=0
"$REPO_ROOT/flywheel" doctor --json >"$TEST_ROOT/unsafe-doctor.out" 2>&1 || unsafe_doctor_rc=$?
[[ "$unsafe_doctor_rc" -eq 2 ]]
if grep -F -- 'flywheel-partial-safe-doctor.sh' "$CALLS" >/dev/null; then
    printf 'unsafe receipt unexpectedly selected a guest doctor\n' >&2
    exit 1
fi
mv "$FLYWHEEL_STATE_HOME/installation.json" "$TEST_ROOT/installation-symlink"
mv "$VALID_INSTALL_RECEIPT" "$FLYWHEEL_STATE_HOME/installation.json"

mv "$FLYWHEEL_STATE_HOME/installation.json" "$VALID_INSTALL_RECEIPT"
python3 - "$FLYWHEEL_STATE_HOME/installation.json" <<'PY'
import sys
with open(sys.argv[1], "wb") as handle:
    handle.write(b"x" * (64 * 1024 + 1))
PY
oversized_status_rc=0
oversized_status_json="$("$REPO_ROOT/flywheel" status --json)" || oversized_status_rc=$?
[[ "$oversized_status_rc" -eq 1 ]]
python3 -c 'import json,sys; assert json.loads(sys.argv[1])["installation"]["status"] == "receipt_invalid"' \
    "$oversized_status_json"
mv "$FLYWHEEL_STATE_HOME/installation.json" "$TEST_ROOT/installation-oversized"
mv "$VALID_INSTALL_RECEIPT" "$FLYWHEEL_STATE_HOME/installation.json"

mv "$FLYWHEEL_STATE_HOME/installation.json" "$VALID_INSTALL_RECEIPT"
mkfifo "$FLYWHEEL_STATE_HOME/installation.json"
fifo_status_rc=0
fifo_status_json="$("$REPO_ROOT/flywheel" status --json)" || fifo_status_rc=$?
[[ "$fifo_status_rc" -eq 1 ]]
python3 -c 'import json,sys; assert json.loads(sys.argv[1])["installation"]["status"] == "receipt_invalid"' \
    "$fifo_status_json"
mv "$FLYWHEEL_STATE_HOME/installation.json" "$TEST_ROOT/installation-fifo"
mv "$VALID_INSTALL_RECEIPT" "$FLYWHEEL_STATE_HOME/installation.json"

typo_rc=0
typo_error="$("$REPO_ROOT/flywheel" statsu 2>&1)" || typo_rc=$?
[[ "$typo_rc" -eq 2 ]]
[[ "$typo_error" == *'did you mean: flywheel status --json'* ]]

# A recomputed self-hash does not make user-edited module or authority claims
# authoritative. Every semantic field remains bound to the compiled authority.
SEMANTIC_VALID_RECEIPT="$TEST_ROOT/installation-semantic-valid.json"
cp "$FLYWHEEL_STATE_HOME/installation.json" "$SEMANTIC_VALID_RECEIPT"
for mutation in authority-sha claim approved-ids independent-holds licensing-cleared licensing-pending; do
    /usr/bin/python3 -I - "$SEMANTIC_VALID_RECEIPT" "$FLYWHEEL_STATE_HOME/installation.json" "$mutation" <<'PY'
import hashlib
import json
import sys

source_path, destination_path, mutation = sys.argv[1:]
value = json.load(open(source_path, encoding="utf-8"))
if mutation == "authority-sha":
    value["authority"]["sha256"] = "0" * 64
elif mutation == "claim":
    value["claim"] = "LICENSE_CLEARED_PARTIAL"
elif mutation == "approved-ids":
    value["modules"]["approved_ids"].append("stack.forged")
    value["modules"]["approved"] += 1
elif mutation == "independent-holds":
    value["modules"]["independent_holds"].append("stack.forged_hold")
elif mutation == "licensing-cleared":
    value["modules"]["licensing_cleared"] = 1
elif mutation == "licensing-pending":
    value["modules"]["licensing_pending"] = 26
value.pop("receipt_sha256", None)
canonical = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
value["receipt_sha256"] = hashlib.sha256(canonical.encode()).hexdigest()
with open(destination_path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    handle.write("\n")
PY
    semantic_status_rc=0
    semantic_status_json="$("$REPO_ROOT/flywheel" status --json)" || semantic_status_rc=$?
    [[ "$semantic_status_rc" -eq 1 ]]
    /usr/bin/python3 -I - "$semantic_status_json" "$mutation" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
assert value["installation"]["status"] == "receipt_invalid", (sys.argv[2], value)
assert any(item["code"] == "installation_receipt_invalid" for item in value["blockers"])
PY
done
cp "$SEMANTIC_VALID_RECEIPT" "$FLYWHEEL_STATE_HOME/installation.json"

python3 - "$FLYWHEEL_STATE_HOME/installation.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
value["modules"]["approved"] = 9
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(value, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY
tampered_rc=0
tampered_json="$("$REPO_ROOT/flywheel" status --json)" || tampered_rc=$?
[[ "$tampered_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
assert value["installation"]["status"] == "receipt_invalid"
assert any(item["code"] == "installation_receipt_invalid" for item in value["blockers"])
' "$tampered_json"

"$REPO_ROOT/flywheel" stop --quiet
grep -F -- 'stop agent-flywheel-ubuntu2404' "$CALLS" >/dev/null

# A genuinely absent named VM is created from the canonical pinned template.
: >"$CALLS"
printf '0\n' >"$PRESENT_FILE"
printf 'Stopped\n' >"$STATUS_FILE"
printf 'exact\n' >"$PROFILE_FILE"
printf 'ok\n' >"$QUERY_FILE"
"$REPO_ROOT/flywheel" start --quiet
grep -E -- 'validate .*/config/flywheel-lima\.yaml$' "$CALLS" >/dev/null
grep -E -- '--stateful -- .*/limactl start --tty=false --name=agent-flywheel-ubuntu2404 .*/config/flywheel-lima\.yaml$' "$CALLS" >/dev/null
[[ "$(<"$PRESENT_FILE")" == "1" ]]
[[ "$(<"$STATUS_FILE")" == "Running" ]]

# An inventory query failure is not treated as absence and cannot create a VM.
: >"$CALLS"
printf 'failed\n' >"$QUERY_FILE"
query_rc=0
query_error="$("$REPO_ROOT/flywheel" start --quiet 2>&1)" || query_rc=$?
[[ "$query_rc" -eq 3 ]]
[[ "$query_error" == *'cannot query Lima VM inventory; no VM was created or changed'* ]]
if grep -F -- '--stateful --' "$CALLS" >/dev/null; then
    printf 'query failure unexpectedly entered the heavy lifecycle guard\n' >&2
    exit 1
fi

# Existing resource drift is visible and blocks start without replacing the VM.
: >"$CALLS"
printf 'ok\n' >"$QUERY_FILE"
printf '1\n' >"$PRESENT_FILE"
printf 'Stopped\n' >"$STATUS_FILE"
printf 'drift\n' >"$PROFILE_FILE"
drift_rc=0
drift_error="$("$REPO_ROOT/flywheel" start --quiet 2>&1)" || drift_rc=$?
[[ "$drift_rc" -eq 2 ]]
[[ "$drift_error" == *'does not match the Flywheel contract (["cpus"]); it was not changed'* ]]
if grep -F -- '--stateful --' "$CALLS" >/dev/null; then
    printf 'resource drift unexpectedly entered the heavy lifecycle guard\n' >&2
    exit 1
fi
drift_status_rc=0
drift_status_json="$("$REPO_ROOT/flywheel" status --json)" || drift_status_rc=$?
[[ "$drift_status_rc" -eq 1 ]]
python3 -c '
import json,sys
value=json.loads(sys.argv[1])
vm=value["vm"]
assert vm["exists"] is True
assert vm["resources"]["cpus"] == 4
assert vm["contract"]["matches"] is False
assert vm["mismatches"] == ["cpus"]
assert any(item["code"] == "vm_contract_drift" for item in value["blockers"])
' "$drift_status_json"
drift_status_text_rc=0
drift_status_text="$("$REPO_ROOT/flywheel" status 2>&1)" || drift_status_text_rc=$?
[[ "$drift_status_text_rc" -eq 1 ]]
[[ "$drift_status_text" == *'VM contract: mismatch'* ]]
[[ "$drift_status_text" == *'VM mismatches: cpus'* ]]

# Stop remains available during resource drift and does not repair or replace it.
: >"$CALLS"
printf 'Running\n' >"$STATUS_FILE"
"$REPO_ROOT/flywheel" stop --quiet
grep -F -- 'stop agent-flywheel-ubuntu2404' "$CALLS" >/dev/null
[[ "$(<"$STATUS_FILE")" == "Stopped" ]]
[[ "$(<"$PROFILE_FILE")" == "drift" ]]

printf 'flywheel lifecycle tests: PASS\n'
