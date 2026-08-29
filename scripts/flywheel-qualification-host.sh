#!/usr/bin/env bash
set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
umask 022

SOURCE_ROOT="${FLYWHEEL_SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
MIN_DISK_GIB="${FLYWHEEL_MIN_DISK_GIB:-20}"
FORMAT="text"

usage() {
    printf 'Usage: %s [--json]\n' "${0##*/}"
}

while (($#)); do
    case "$1" in
        --json) FORMAT="json" ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

checks=()
failures=0

record() {
    local id="$1"
    local status="$2"
    local detail="$3"
    checks+=("$id"$'\t'"$status"$'\t'"$detail")
    [[ "$status" == "pass" ]] || failures=$((failures + 1))
}

os_id=""
os_version=""
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    os_id="${ID:-}"
    os_version="${VERSION_ID:-}"
fi
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

bash_major="${BASH_VERSINFO[0]:-0}"
if ((bash_major >= 4)); then
    record bash_runtime pass "bash ${BASH_VERSION:-unknown}"
else
    record bash_runtime fail "Bash 4+ required"
fi

disk_kib="$(df -Pk "$SOURCE_ROOT" 2>/dev/null | awk 'NR == 2 {print $4}')"
required_kib=$((MIN_DISK_GIB * 1024 * 1024))
if [[ "$disk_kib" =~ ^[0-9]+$ ]] && ((disk_kib >= required_kib)); then
    record disk_free pass "$((disk_kib / 1024 / 1024)) GiB free"
else
    record disk_free fail "at least ${MIN_DISK_GIB} GiB free required"
fi

virtualization="$(systemd-detect-virt 2>/dev/null || true)"
if [[ -n "$virtualization" && "$virtualization" != "none" ]]; then
    record isolation pass "$virtualization"
else
    record isolation fail "a VM or isolated qualification host is required"
fi

if [[ -d "$SOURCE_ROOT/.git" || -f "$SOURCE_ROOT/.git" ]] \
    && git -C "$SOURCE_ROOT" rev-parse --verify HEAD >/dev/null 2>&1 \
    && git -C "$SOURCE_ROOT" diff --quiet \
    && git -C "$SOURCE_ROOT" diff --cached --quiet \
    && [[ -z "$(git -C "$SOURCE_ROOT" ls-files --others --exclude-standard)" ]]; then
    record source_identity pass "$(git -C "$SOURCE_ROOT" rev-parse HEAD)/$(git -C "$SOURCE_ROOT" rev-parse 'HEAD^{tree}')"
else
    record source_identity fail "source checkout is missing or dirty"
fi

if [[ "$FORMAT" == "json" ]]; then
    printf '%s\n' "${checks[@]}" | python3 -c '
import json, sys
rows=[]
for line in sys.stdin:
    line=line.rstrip("\n")
    if not line:
        continue
    identifier,status,detail=line.split("\t",2)
    rows.append({"id":identifier,"status":status,"detail":detail})
failures=sum(row["status"] != "pass" for row in rows)
print(json.dumps({
    "schema":"agent-flywheel.qualification-host/v1",
    "status":"pass" if failures == 0 else "fail",
    "requirements":rows,
    "summary":{"pass":len(rows)-failures,"fail":failures},
},sort_keys=True,separators=(",",":")))
'
else
    for item in "${checks[@]}"; do
        IFS=$'\t' read -r id status detail <<<"$item"
        printf '%-18s %-4s %s\n' "$id" "$status" "$detail"
    done
fi

((failures == 0))
