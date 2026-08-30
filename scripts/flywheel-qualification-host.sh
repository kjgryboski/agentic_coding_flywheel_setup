#!/usr/bin/env bash
set -euo pipefail
umask 022

SOURCE_ROOT="${FLYWHEEL_SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
SOURCE_BUNDLE="${FLYWHEEL_SOURCE_BUNDLE:-}"
MIN_DISK_GIB="${FLYWHEEL_MIN_DISK_GIB:-20}"
MIN_MEMORY_GIB="${FLYWHEEL_MIN_MEMORY_GIB:-8}"
MIN_SWAP_GIB="${FLYWHEEL_MIN_SWAP_GIB:-8}"
OS_RELEASE_FILE="${FLYWHEEL_OS_RELEASE_FILE:-/etc/os-release}"
MEMINFO_FILE="${FLYWHEEL_MEMINFO_FILE:-/proc/meminfo}"
OBSERVED_AT="${FLYWHEEL_OBSERVED_AT:-}"
FORMAT="text"

usage() {
    printf 'Usage: %s [--json] [--bundle PATH]\n' "${0##*/}"
}

while (($#)); do
    case "$1" in
        --json)
            FORMAT="json"
            ;;
        --bundle)
            (($# >= 2)) || { printf '%s\n' '--bundle requires a path' >&2; exit 2; }
            SOURCE_BUNDLE="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

for threshold in "$MIN_DISK_GIB" "$MIN_MEMORY_GIB" "$MIN_SWAP_GIB"; do
    if [[ ! "$threshold" =~ ^[1-9][0-9]*$ ]]; then
        printf 'Qualification thresholds must be positive whole GiB values.\n' >&2
        exit 2
    fi
done

if [[ -z "$OBSERVED_AT" ]]; then
    OBSERVED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
fi

checks=()
failures=0

record() {
    local id="$1"
    local status="$2"
    local detail="$3"
    detail="${detail//$'\t'/ }"
    detail="${detail//$'\n'/ }"
    checks+=("$id"$'\t'"$status"$'\t'"$detail")
    [[ "$status" == "pass" ]] || failures=$((failures + 1))
}

read_release_value() {
    local wanted="$1"
    local key=""
    local value=""
    [[ -r "$OS_RELEASE_FILE" ]] || return 1
    while IFS='=' read -r key value; do
        if [[ "$key" == "$wanted" ]]; then
            if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
                value="${value:1:${#value}-2}"
            fi
            printf '%s\n' "$value"
            return 0
        fi
    done <"$OS_RELEASE_FILE"
    return 1
}

read_meminfo_kib() {
    local wanted="$1"
    [[ -r "$MEMINFO_FILE" ]] || return 1
    awk -v wanted="$wanted" '$1 == wanted ":" && $2 ~ /^[0-9]+$/ { print $2; exit }' \
        "$MEMINFO_FILE"
}

sha256_file() {
    /usr/bin/python3 -I - "$1" <<'PY'
import hashlib
import os
import pathlib
import stat
import sys

digest = hashlib.sha256()
path = pathlib.Path(sys.argv[1])
flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
descriptor = os.open(path, flags)
with os.fdopen(descriptor, "rb") as handle:
    before = os.fstat(handle.fileno())
    if not stat.S_ISREG(before.st_mode):
        raise OSError(f"not a regular file: {path}")
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
    after = os.fstat(handle.fileno())
    identity_before = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
    identity_after = (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
    if identity_before != identity_after:
        raise OSError(f"file changed while being hashed: {path}")
print(digest.hexdigest())
PY
}

sha256_stdin() {
    /usr/bin/python3 -I -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}

canonical_path() {
    /usr/bin/python3 -I - "$1" <<'PY'
import pathlib
import sys

print(pathlib.Path(sys.argv[1]).resolve(strict=False))
PY
}

os_id=""
os_version=""
os_id="$(read_release_value ID 2>/dev/null || true)"
os_version="$(read_release_value VERSION_ID 2>/dev/null || true)"
if [[ "$os_id" == "ubuntu" && "$os_version" == "24.04" ]]; then
    record ubuntu_version pass "Ubuntu 24.04"
else
    record ubuntu_version fail "expected Ubuntu 24.04; observed ${os_id:-unknown} ${os_version:-unknown}"
fi

arch="$(uname -m 2>/dev/null || true)"
case "$arch" in
    x86_64|aarch64) record architecture pass "$arch" ;;
    *) record architecture fail "unsupported architecture ${arch:-unknown}" ;;
esac

bash_major="${FLYWHEEL_BASH_MAJOR:-${BASH_VERSINFO[0]:-0}}"
bash_version="${FLYWHEEL_BASH_VERSION:-${BASH_VERSION:-unknown}}"
if [[ "$bash_major" =~ ^[0-9]+$ ]] && ((bash_major >= 4)); then
    record bash_runtime pass "bash $bash_version"
else
    record bash_runtime fail "Bash 4+ required"
fi

disk_kib="$(df -Pk -- "$SOURCE_ROOT" 2>/dev/null | awk 'END {print $4}')"
required_disk_kib=$((MIN_DISK_GIB * 1024 * 1024))
if [[ "$disk_kib" =~ ^[0-9]+$ ]] && ((disk_kib >= required_disk_kib)); then
    record disk_free pass "$((disk_kib / 1024 / 1024)) GiB free"
else
    record disk_free fail "at least ${MIN_DISK_GIB} GiB free required"
fi

memory_kib="$(read_meminfo_kib MemTotal 2>/dev/null || true)"
required_memory_kib=$((MIN_MEMORY_GIB * 1024 * 1024))
if [[ "$memory_kib" =~ ^[0-9]+$ ]] && ((memory_kib >= required_memory_kib)); then
    record memory_total pass "$((memory_kib / 1024 / 1024)) GiB total"
else
    record memory_total fail "at least ${MIN_MEMORY_GIB} GiB memory required"
fi

swap_kib="$(read_meminfo_kib SwapTotal 2>/dev/null || true)"
required_swap_kib=$((MIN_SWAP_GIB * 1024 * 1024))
# Linux excludes a small mkswap header from /proc/meminfo. A provisioned
# 8 GiB swapfile therefore reports a few KiB below 8 GiB of usable capacity.
swap_metadata_tolerance_kib=1024
if [[ "$swap_kib" =~ ^[0-9]+$ ]] \
    && ((swap_kib + swap_metadata_tolerance_kib >= required_swap_kib)); then
    record swap_total pass "$swap_kib KiB usable; ${MIN_SWAP_GIB} GiB provisioned threshold"
else
    record swap_total fail "at least ${MIN_SWAP_GIB} GiB swap required"
fi

virtualization="$(systemd-detect-virt 2>/dev/null || true)"
virtualization="${virtualization%%$'\n'*}"
if [[ -n "$virtualization" && "$virtualization" != "none" ]]; then
    record isolation pass "$virtualization"
else
    record isolation fail "a VM, container, or equivalent isolated host is required"
fi

if [[ -d "$SOURCE_ROOT" ]]; then
    SOURCE_ROOT="$(cd -- "$SOURCE_ROOT" && pwd -P)"
fi
source_requested="$SOURCE_ROOT"
safe_git_path="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
git_binary=""
for candidate in /usr/bin/git /opt/homebrew/bin/git /usr/local/bin/git; do
    if [[ -x "$candidate" ]]; then
        git_binary="$candidate"
        break
    fi
done
git_environment=(
    /usr/bin/env -i
    "PATH=$safe_git_path"
    "HOME=/"
    "LANG=C"
    "LC_ALL=C"
    "TZ=UTC"
    "GIT_ATTR_NOSYSTEM=1"
    "GIT_CONFIG_NOSYSTEM=1"
    "GIT_CONFIG_GLOBAL=/dev/null"
    "GIT_CONFIG_SYSTEM=/dev/null"
    "GIT_EXTERNAL_DIFF="
    "GIT_LITERAL_PATHSPECS=1"
    "GIT_NO_REPLACE_OBJECTS=1"
    "GIT_OPTIONAL_LOCKS=0"
    "GIT_TERMINAL_PROMPT=0"
)
git_source=(
    "${git_environment[@]}"
    "$git_binary"
    -c "safe.directory=$SOURCE_ROOT"
    -c core.fsmonitor=false
    -c core.untrackedCache=false
    -c core.hooksPath=/dev/null
    -c diff.external=
    -c interactive.diffFilter=
    -C "$SOURCE_ROOT"
)

tracked_regular_files_match() {
    local entry=""
    local metadata=""
    local mode=""
    local object_type=""
    local object_id=""
    local relative_path=""
    local regular_count=0
    [[ "$source_head" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || return 1
    while IFS= read -r -d '' entry; do
        [[ "$entry" == *$'\t'* ]] || return 1
        metadata="${entry%%$'\t'*}"
        relative_path="${entry#*$'\t'}"
        read -r mode object_type object_id <<<"$metadata"
        [[ "$relative_path" != /* \
            && "$relative_path" != ".." \
            && "$relative_path" != ../* \
            && "$relative_path" != */../* \
            && "$relative_path" != */.. ]] || return 1
        case "$mode" in
            100644|100755)
                [[ "$object_type" == "blob" \
                    && "$object_id" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ \
                    && -f "$SOURCE_ROOT/$relative_path" \
                    && ! -L "$SOURCE_ROOT/$relative_path" ]] || return 1
                "${git_source[@]}" cat-file blob "$object_id" \
                    | /usr/bin/cmp -s - "$SOURCE_ROOT/$relative_path" \
                    || return 1
                regular_count=$((regular_count + 1))
                ;;
        esac
    done < <("${git_source[@]}" ls-tree -r -z --full-tree "$source_head")
    ((regular_count > 0))
}
source_head=""
source_tree=""
source_repository=false
source_worktree_clean=false
source_index_clean=false
source_untracked_clean=false
source_index_flags_clean=false
source_sparse_clean=false
source_unmerged_clean=false
source_critical_bytes_match=false
source_repository_binding_stable=false
source_git_dir=""
source_common_dir=""
source_index_path=""
source_clean=false
if [[ -n "$git_binary" && ( -d "$SOURCE_ROOT/.git" || -f "$SOURCE_ROOT/.git" ) ]] \
    && "${git_source[@]}" rev-parse --verify HEAD >/dev/null 2>&1; then
    observed_root="$("${git_source[@]}" rev-parse --path-format=absolute --show-toplevel 2>/dev/null || true)"
    observed_git_dir="$("${git_source[@]}" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
    observed_common_dir="$("${git_source[@]}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    observed_index_path="$("${git_source[@]}" rev-parse --path-format=absolute --git-path index 2>/dev/null || true)"
    observed_root="$(canonical_path "$observed_root" 2>/dev/null || true)"
    source_git_dir="$(canonical_path "$observed_git_dir" 2>/dev/null || true)"
    source_common_dir="$(canonical_path "$observed_common_dir" 2>/dev/null || true)"
    source_index_path="$(canonical_path "$observed_index_path" 2>/dev/null || true)"
    if [[ "$observed_root" == "$SOURCE_ROOT" \
        && "$source_git_dir" == /* \
        && "$source_common_dir" == /* \
        && "$source_index_path" == /* ]]; then
        source_repository=true
        source_head="$("${git_source[@]}" rev-parse HEAD 2>/dev/null || true)"
        source_tree="$("${git_source[@]}" rev-parse 'HEAD^{tree}' 2>/dev/null || true)"
        tracked_regular_files_match && source_worktree_clean=true
        "${git_source[@]}" diff --cached --quiet --no-ext-diff --no-textconv >/dev/null 2>&1 \
            && source_index_clean=true
        if "${git_source[@]}" ls-files --others --exclude-standard -z 2>/dev/null \
            | /usr/bin/python3 -I -c 'import sys; raise SystemExit(1 if sys.stdin.buffer.read(1) else 0)'; then
            source_untracked_clean=true
        fi
        if "${git_source[@]}" ls-files -v -z --cached 2>/dev/null \
            | /usr/bin/python3 -I -c '
import sys
records = [item for item in sys.stdin.buffer.read().split(b"\0") if item]
raise SystemExit(0 if all(len(item) >= 3 and item[:2] == b"H " for item in records) else 1)
'; then
            source_index_flags_clean=true
        fi
        if "${git_source[@]}" ls-files -u -z 2>/dev/null \
            | /usr/bin/python3 -I -c 'import sys; raise SystemExit(1 if sys.stdin.buffer.read(1) else 0)'; then
            source_unmerged_clean=true
        fi
        sparse_value=""
        if sparse_value="$("${git_source[@]}" config --bool --get core.sparseCheckout 2>/dev/null)"; then
            [[ "$sparse_value" == "false" ]] && source_sparse_clean=true
        else
            sparse_status=$?
            [[ "$sparse_status" -eq 1 ]] && source_sparse_clean=true
        fi

        source_critical_bytes_match="$source_worktree_clean"
        checker_path="$(canonical_path "${BASH_SOURCE[0]}" 2>/dev/null || true)"
        if [[ "$checker_path" != "$SOURCE_ROOT/scripts/flywheel-qualification-host.sh" ]]; then
            source_critical_bytes_match=false
        fi

        final_root="$("${git_source[@]}" rev-parse --path-format=absolute --show-toplevel 2>/dev/null || true)"
        final_git_dir="$("${git_source[@]}" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
        final_common_dir="$("${git_source[@]}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
        final_index_path="$("${git_source[@]}" rev-parse --path-format=absolute --git-path index 2>/dev/null || true)"
        final_root="$(canonical_path "$final_root" 2>/dev/null || true)"
        final_git_dir="$(canonical_path "$final_git_dir" 2>/dev/null || true)"
        final_common_dir="$(canonical_path "$final_common_dir" 2>/dev/null || true)"
        final_index_path="$(canonical_path "$final_index_path" 2>/dev/null || true)"
        final_head="$("${git_source[@]}" rev-parse HEAD 2>/dev/null || true)"
        final_tree="$("${git_source[@]}" rev-parse 'HEAD^{tree}' 2>/dev/null || true)"
        tracked_regular_files_match || source_worktree_clean=false
        "${git_source[@]}" diff --cached --quiet --no-ext-diff --no-textconv >/dev/null 2>&1 \
            || source_index_clean=false
        if ! "${git_source[@]}" ls-files --others --exclude-standard -z 2>/dev/null \
            | /usr/bin/python3 -I -c 'import sys; raise SystemExit(1 if sys.stdin.buffer.read(1) else 0)'; then
            source_untracked_clean=false
        fi
        if ! "${git_source[@]}" ls-files -v -z --cached 2>/dev/null \
            | /usr/bin/python3 -I -c '
import sys
records = [item for item in sys.stdin.buffer.read().split(b"\0") if item]
raise SystemExit(0 if all(len(item) >= 3 and item[:2] == b"H " for item in records) else 1)
'; then
            source_index_flags_clean=false
        fi
        if ! "${git_source[@]}" ls-files -u -z 2>/dev/null \
            | /usr/bin/python3 -I -c 'import sys; raise SystemExit(1 if sys.stdin.buffer.read(1) else 0)'; then
            source_unmerged_clean=false
        fi
        final_sparse_value=""
        if final_sparse_value="$("${git_source[@]}" config --bool --get core.sparseCheckout 2>/dev/null)"; then
            [[ "$final_sparse_value" == "false" ]] || source_sparse_clean=false
        else
            final_sparse_status=$?
            [[ "$final_sparse_status" -eq 1 ]] || source_sparse_clean=false
        fi
        tracked_regular_files_match || source_critical_bytes_match=false
        if [[ "$final_root" == "$SOURCE_ROOT" \
            && "$final_git_dir" == "$source_git_dir" \
            && "$final_common_dir" == "$source_common_dir" \
            && "$final_index_path" == "$source_index_path" \
            && "$final_head" == "$source_head" \
            && "$final_tree" == "$source_tree" ]]; then
            source_repository_binding_stable=true
        fi
    fi
fi
if [[ "$source_repository" == "true" \
    && "$source_head" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ \
    && "$source_tree" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ \
    && "$source_worktree_clean" == "true" \
    && "$source_index_clean" == "true" \
    && "$source_untracked_clean" == "true" \
    && "$source_index_flags_clean" == "true" \
    && "$source_sparse_clean" == "true" \
    && "$source_unmerged_clean" == "true" \
    && "$source_critical_bytes_match" == "true" \
    && "$source_repository_binding_stable" == "true" ]]; then
    source_clean=true
    record source_identity pass "$source_head/$source_tree; clean checkout"
else
    record source_identity fail "source checkout is missing, invalid, or dirty"
fi

if [[ -z "$SOURCE_BUNDLE" && -n "$source_head" ]]; then
    inferred_bundle="/var/tmp/agent-flywheel-acfs-$source_head.bundle"
    [[ -f "$inferred_bundle" && ! -L "$inferred_bundle" ]] && SOURCE_BUNDLE="$inferred_bundle"
fi

bundle_sha256=""
bundle_head=""
bundle_valid=false
if [[ -n "$SOURCE_BUNDLE" && -f "$SOURCE_BUNDLE" && ! -L "$SOURCE_BUNDLE" \
    && -r "$SOURCE_BUNDLE" && -n "$source_head" ]] \
    && "${git_source[@]}" bundle verify "$SOURCE_BUNDLE" >/dev/null 2>&1; then
    bundle_sha256="$(sha256_file "$SOURCE_BUNDLE" 2>/dev/null || true)"
    bundle_head="$("${git_source[@]}" bundle list-heads "$SOURCE_BUNDLE" 2>/dev/null \
        | awk -v expected="$source_head" '$1 == expected { print $1; exit }')"
    if [[ "$bundle_sha256" =~ ^[0-9a-f]{64}$ && "$bundle_head" == "$source_head" ]]; then
        bundle_valid=true
    fi
fi
if [[ "$bundle_valid" == "true" ]]; then
    record bundle_identity pass "$bundle_sha256; contains source HEAD $bundle_head"
else
    record bundle_identity fail "a regular verified Git bundle containing the exact source HEAD is required"
fi

disk_kib="${disk_kib:-0}"
memory_kib="${memory_kib:-0}"
swap_kib="${swap_kib:-0}"

if [[ "$FORMAT" == "json" ]]; then
    printf '%s\n' "${checks[@]}" | /usr/bin/python3 -I -c '
import hashlib
import json
import sys

(
    observed_at,
    minimum_disk_gib,
    minimum_memory_gib,
    minimum_swap_gib,
    os_id,
    os_version,
    architecture,
    bash_version,
    isolation,
    disk_kib,
    memory_kib,
    swap_kib,
    source_head,
    source_tree,
    source_requested,
    source_git_dir,
    source_common_dir,
    source_index_path,
    source_repository,
    source_worktree_clean,
    source_index_clean,
    source_untracked_clean,
    source_index_flags_clean,
    source_sparse_clean,
    source_unmerged_clean,
    source_critical_bytes_match,
    source_repository_binding_stable,
    source_clean,
    bundle_sha256,
    bundle_head,
    bundle_valid,
) = sys.argv[1:]

rows = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    identifier, status, detail = line.split("\t", 2)
    rows.append({"id": identifier, "status": status, "detail": detail})

def as_bool(value):
    return value == "true"

def kib_to_bytes(value):
    return int(value) * 1024 if value.isdigit() else 0

failures = sum(row["status"] != "pass" for row in rows)
receipt = {
    "schema": "agent-flywheel.qualification-host/v1",
    "observed_at": observed_at,
    "contract": {
        "host_identity": "any-compliant-host",
        "ubuntu_version": "24.04",
        "architectures": ["aarch64", "x86_64"],
        "minimum_disk_gib": int(minimum_disk_gib),
        "minimum_memory_gib": int(minimum_memory_gib),
        "minimum_swap_gib": int(minimum_swap_gib),
        "minimum_bash_major": 4,
        "isolation_required": True,
        "clean_source_identity_required": True,
        "critical_source_bytes_required": ["all-tracked-regular-files"],
        "exact_bundle_identity_required": True,
        "receipt_digest": "sha256(canonical-json-without-receipt_sha256+newline)",
    },
    "host": {
        "os": {"id": os_id, "version": os_version},
        "architecture": architecture,
        "bash_version": bash_version,
        "isolation": isolation,
        "resources": {
            "disk_free_bytes": kib_to_bytes(disk_kib),
            "memory_total_bytes": kib_to_bytes(memory_kib),
            "swap_total_bytes": kib_to_bytes(swap_kib),
        },
    },
    "source": {
        "head": source_head or None,
        "tree": source_tree or None,
        "requested_root": source_requested,
        "git_paths": {
            "root": source_requested,
            "git_dir": source_git_dir or None,
            "common_dir": source_common_dir or None,
            "index": source_index_path or None,
        },
        "clean": as_bool(source_clean),
        "clean_state_evidence": {
            "git_repository": as_bool(source_repository),
            "worktree_clean": as_bool(source_worktree_clean),
            "index_clean": as_bool(source_index_clean),
            "untracked_clean": as_bool(source_untracked_clean),
            "index_flags_clean": as_bool(source_index_flags_clean),
            "sparse_checkout_disabled": as_bool(source_sparse_clean),
            "unmerged_index_clean": as_bool(source_unmerged_clean),
            "critical_source_bytes_match": as_bool(source_critical_bytes_match),
            "repository_binding_stable": as_bool(source_repository_binding_stable),
        },
    },
    "bundle": {
        "sha256": bundle_sha256 or None,
        "source_head": bundle_head or None,
        "verified": as_bool(bundle_valid),
    },
    "status": "pass" if failures == 0 else "fail",
    "requirements": rows,
    "summary": {"pass": len(rows) - failures, "fail": failures},
}
canonical = json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
receipt["receipt_sha256"] = hashlib.sha256((canonical + "\n").encode()).hexdigest()
print(json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=False))
' \
        "$OBSERVED_AT" "$MIN_DISK_GIB" "$MIN_MEMORY_GIB" "$MIN_SWAP_GIB" \
        "$os_id" "$os_version" "$arch" "$bash_version" "$virtualization" \
        "$disk_kib" "$memory_kib" "$swap_kib" \
        "$source_head" "$source_tree" "$source_requested" "$source_git_dir" \
        "$source_common_dir" "$source_index_path" "$source_repository" \
        "$source_worktree_clean" "$source_index_clean" "$source_untracked_clean" \
        "$source_index_flags_clean" "$source_sparse_clean" "$source_unmerged_clean" \
        "$source_critical_bytes_match" "$source_repository_binding_stable" "$source_clean" \
        "$bundle_sha256" "$bundle_head" "$bundle_valid"
else
    for item in "${checks[@]}"; do
        IFS=$'\t' read -r id status detail <<<"$item"
        printf '%-18s %-4s %s\n' "$id" "$status" "$detail"
    done
fi

((failures == 0))
