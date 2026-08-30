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
    python3 - "$1" <<'PY'
import hashlib
import pathlib
import sys

digest = hashlib.sha256()
with pathlib.Path(sys.argv[1]).open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
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
if [[ "$swap_kib" =~ ^[0-9]+$ ]] && ((swap_kib >= required_swap_kib)); then
    record swap_total pass "$((swap_kib / 1024 / 1024)) GiB total"
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

git_source=(git -c "safe.directory=$SOURCE_ROOT" -C "$SOURCE_ROOT")
source_head=""
source_tree=""
source_repository=false
source_worktree_clean=false
source_index_clean=false
source_untracked_clean=false
source_clean=false
if [[ ( -d "$SOURCE_ROOT/.git" || -f "$SOURCE_ROOT/.git" ) ]] \
    && "${git_source[@]}" rev-parse --verify HEAD >/dev/null 2>&1; then
    source_repository=true
    source_head="$("${git_source[@]}" rev-parse HEAD 2>/dev/null || true)"
    source_tree="$("${git_source[@]}" rev-parse 'HEAD^{tree}' 2>/dev/null || true)"
    "${git_source[@]}" diff --quiet >/dev/null 2>&1 && source_worktree_clean=true
    "${git_source[@]}" diff --cached --quiet >/dev/null 2>&1 && source_index_clean=true
    if "${git_source[@]}" ls-files --others --exclude-standard -z 2>/dev/null \
        | python3 -c 'import sys; raise SystemExit(1 if sys.stdin.buffer.read(1) else 0)'; then
        source_untracked_clean=true
    fi
fi
if [[ "$source_repository" == "true" \
    && "$source_head" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ \
    && "$source_tree" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ \
    && "$source_worktree_clean" == "true" \
    && "$source_index_clean" == "true" \
    && "$source_untracked_clean" == "true" ]]; then
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
    printf '%s\n' "${checks[@]}" | python3 -c '
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
    source_repository,
    source_worktree_clean,
    source_index_clean,
    source_untracked_clean,
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
        "clean": as_bool(source_clean),
        "clean_state_evidence": {
            "git_repository": as_bool(source_repository),
            "worktree_clean": as_bool(source_worktree_clean),
            "index_clean": as_bool(source_index_clean),
            "untracked_clean": as_bool(source_untracked_clean),
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
        "$source_head" "$source_tree" "$source_repository" "$source_worktree_clean" \
        "$source_index_clean" "$source_untracked_clean" "$source_clean" \
        "$bundle_sha256" "$bundle_head" "$bundle_valid"
else
    for item in "${checks[@]}"; do
        IFS=$'\t' read -r id status detail <<<"$item"
        printf '%-18s %-4s %s\n' "$id" "$status" "$detail"
    done
fi

((failures == 0))
