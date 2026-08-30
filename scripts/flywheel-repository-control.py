#!/usr/bin/env python3
"""Read-only repository onboarding inspection and rollout planning."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import urllib.parse
from typing import Any


INSPECTION_SCHEMA = "agent-flywheel.repository-inspection/v1"
INVENTORY_SCHEMA = "agent-flywheel.rollout-inventory/v1"
PLAN_SCHEMA = "agent-flywheel.progressive-rollout-plan/v1"
ELIGIBILITY_SCHEMA = "agent-flywheel.repository-live-pilot-eligibility/v1"
OPS_PILOT_SCHEMA = "ops-steward.github-admission-synthetic-pilot-receipt/v1"
GENERIC_ROLLOUT_SCHEMA = "agent-flywheel.repository-rollout/v1"
COHORT_ORDER = {"pilot": 0, "low-risk": 1, "standard": 2, "critical": 3}
OPS_REPOSITORY = "kjgryboski/ops-steward"
OPS_PILOT_CHECKS = (
    "test_github_admission_synthetic_pilot.AdmissionSyntheticPilotTests."
    "test_authenticated_webhook_duplicate_and_publication_run_end_to_end",
    "test_github_admission_producer.AdmissionProducerTests."
    "test_two_simultaneous_identical_requests_repeat_100_with_exact_replay",
    "test_github_admission_producer.AdmissionProducerTests."
    "test_accepted_claimant_replays_when_idempotent_peer_wins_delivery_lock",
    "test_github_admission_synthetic_pilot.AdmissionSyntheticPilotTests."
    "test_new_producer_replays_retained_success_without_provider_reads_or_writes",
    "test_github_admission_producer.AdmissionProducerTests."
    "test_conflicting_nonce_and_stale_heartbeat_perform_zero_writes",
    "test_github_admission_synthetic_pilot.AdmissionSyntheticPilotTests."
    "test_convergence_lock_timeout_fails_closed_before_provider_inventory",
    "test_github_admission_producer.AdmissionProducerTests."
    "test_nonce_result_store_failure_stays_fail_closed",
    "test_github_admission_producer.AdmissionProducerTests."
    "test_ambiguous_create_is_not_retried_and_exactly_one_match_is_adopted",
    "test_github_admission_producer.AdmissionProducerTests."
    "test_ambiguous_recovery_rejects_incomplete_or_drifted_inventory",
    "test_github_admission_producer.AdmissionProducerTests."
    "test_untrusted_or_incomplete_inventories_have_zero_writes_and_stable_failure_evidence",
)
OPS_SYNTHETIC_CLAIMS = (
    "authenticated_webhook_ingestion",
    "duplicate_delivery",
    "forced_peer_first_concurrency_100_iterations",
    "one_create_zero_duplicate_updates_revision_one",
    "component_restart_retained_replay_zero_provider_io",
    "failure_closure_and_ambiguous_recovery",
)
OPS_LIVE_CLAIMS = ("live_postgres_restart", "live_github_publication")
OPS_EVIDENCE_FILES = (
    "scripts/run-github-admission-synthetic-pilot.py",
    "tests/test_github_admission_synthetic_pilot.py",
    "src/ops_steward/github_admission_producer.py",
    "src/ops_steward/github_admission_store.py",
    "src/ops_steward/github_admission_webhook.py",
)
OPS_PILOT_ARTIFACT_SHA256 = "6a6232d3c98a56d6740f3382353cae785882d7ede2c51a2b28a0a0ef263544aa"
OPS_PILOT_RECEIPT_SHA256 = "e01f5ca3f3ab55da1a2cf932f4643d6d0a68cac73c13d22b4baff02c3df9c58e"
OPS_PILOT_HEAD = "202040d1b72183225dfdfc665be78ad429eba3ff"
OPS_PILOT_TREE = "32be2a7b7b2940e45de2d2e847fbb9b14866c962"
OPS_PILOT_EVIDENCE_SHA256 = {
    "scripts/run-github-admission-synthetic-pilot.py":
        "e6660fc3f76fffc2a647d5914cdc0efef9e5265aeaa2bd5f964ce856c7470866",
    "tests/test_github_admission_synthetic_pilot.py":
        "d30f6ecaa83a869f5492bae33ee5e1586ba35d87f1ce09e361eb1867f770eeca",
    "src/ops_steward/github_admission_producer.py":
        "45e3e9882ff8821d331c6c81e66b00c6fa7a7ba5e0e56758d100efc239ba8d31",
    "src/ops_steward/github_admission_store.py":
        "415483996b507dff06db3095e4b894455cadb342c8b8484c37e95d54bef59efa",
    "src/ops_steward/github_admission_webhook.py":
        "bfdda916f4d268bbb280434c4a7406ed9ee03465d237208927c6fd1f028ece32",
}
RECEIPT_MAXIMUM_BYTES = 4 * 1024 * 1024
SAFE_EXECUTION_PATH = os.pathsep.join((
    "/usr/bin", "/bin", "/usr/sbin", "/sbin", "/usr/local/bin", "/opt/homebrew/bin",
))


class ControlError(ValueError):
    """An actionable input or repository error."""


def canonical_bytes(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def content_digest(value: object) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def is_hex(value: object, length: int) -> bool:
    return (
        isinstance(value, str)
        and len(value) == length
        and all(character in "0123456789abcdef" for character in value)
    )


def exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    observed = set(value)
    if observed == expected:
        return
    missing = sorted(expected - observed)
    unexpected = sorted(observed - expected)
    details = []
    if missing:
        details.append(f"missing {', '.join(missing)}")
    if unexpected:
        details.append(f"unexpected {', '.join(unexpected)}")
    raise ControlError(f"{label} fields are invalid ({'; '.join(details)})")


def read_json_document(path: pathlib.Path, label: str) -> tuple[bytes, dict[str, Any]]:
    raw = stable_read(path, RECEIPT_MAXIMUM_BYTES, label)
    try:
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ControlError(f"{label} is not valid JSON: {error}") from error
    if not isinstance(value, dict):
        raise ControlError(f"{label} root must be an object")
    return raw, value


def canonical_github_repository(remote: str) -> str:
    candidate = remote.strip()
    scp_match = re.fullmatch(r"git@github\.com:([^/]+)/([^/]+?)(?:\.git)?", candidate)
    if scp_match:
        owner, repository = scp_match.groups()
    else:
        try:
            parsed = urllib.parse.urlsplit(candidate)
            port = parsed.port
        except ValueError as error:
            raise ControlError("origin has an invalid port") from error
        if parsed.hostname != "github.com" or parsed.password or parsed.query or parsed.fragment:
            raise ControlError("origin must be an uncredentialed GitHub repository URL")
        if parsed.scheme == "https":
            if parsed.username is not None or port is not None:
                raise ControlError("origin HTTPS URL must not contain credentials or a port")
        elif parsed.scheme == "ssh":
            if parsed.username != "git" or port not in {None, 22}:
                raise ControlError("origin SSH URL must use git@github.com and port 22")
        else:
            raise ControlError("origin must use canonical HTTPS or SSH")
        if not re.fullmatch(r"/[^/]+/[^/]+", parsed.path):
            raise ControlError("origin must identify exactly one GitHub owner/repository")
        owner, repository = parsed.path[1:].split("/")
        if repository.endswith(".git"):
            repository = repository[:-4]
    return normalize_repository_name(f"{owner}/{repository}")


def normalize_repository_name(value: str) -> str:
    parts = value.split("/")
    if len(parts) != 2:
        raise ControlError("repository identity must be OWNER/REPOSITORY")
    owner, repository = parts
    owner_valid = bool(
        len(owner) <= 39
        and re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?", owner)
    )
    repository_valid = bool(
        len(repository) <= 100
        and repository not in {".", ".."}
        and re.fullmatch(r"[A-Za-z0-9._-]+", repository)
    )
    if not owner_valid or not repository_valid:
        raise ControlError("repository identity must be a canonical GitHub OWNER/REPOSITORY")
    return f"{owner}/{repository}".casefold()


def git_environment() -> dict[str, str]:
    # Deliberately construct, rather than inherit, the child environment. Git
    # has a broad GIT_* environment API: repository, worktree, index, object,
    # namespace, config-injection, transport, and trace variables can all alter
    # an otherwise read-only inspection. Only the fixed controls below cross
    # the trust boundary.
    environment = {
        "PATH": SAFE_EXECUTION_PATH,
        "HOME": os.path.abspath(os.sep),
        "LANG": "C",
        "LC_ALL": "C",
        "TZ": "UTC",
        "GIT_ATTR_NOSYSTEM": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_SYSTEM": os.devnull,
        "GIT_EXTERNAL_DIFF": "",
        "GIT_LITERAL_PATHSPECS": "1",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_TERMINAL_PROMPT": "0",
    }
    return environment


def git_command(root: pathlib.Path, *arguments: str) -> list[str]:
    git_binary = shutil.which("git", path=SAFE_EXECUTION_PATH)
    if not git_binary:
        raise ControlError("Git is unavailable on the trusted execution path")
    return [
        git_binary,
        "-c", "core.fsmonitor=false",
        "-c", "core.untrackedCache=false",
        "-c", f"core.hooksPath={os.devnull}",
        "-c", "diff.external=",
        "-c", "interactive.diffFilter=",
        "-C", str(root),
        *arguments,
    ]


def git_result(root: pathlib.Path, *arguments: str, timeout: int = 15) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            git_command(root, *arguments),
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            env=git_environment(),
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ControlError(f"Git inspection failed for {root}: {error}") from error


def git(root: pathlib.Path, *arguments: str) -> str:
    completed = git_result(root, *arguments)
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise ControlError(f"Git inspection failed for {root}: {detail or 'unknown error'}")
    if len(completed.stdout) > 16 * 1024 * 1024:
        raise ControlError(f"Git inspection output exceeds 16 MiB for {root}")
    return completed.stdout.decode("utf-8", errors="replace")


def _absolute_git_path(root: pathlib.Path, option: str, *arguments: str) -> str:
    observed = git(root, "rev-parse", "--path-format=absolute", option, *arguments).strip()
    if not observed or "\0" in observed or "\n" in observed or not os.path.isabs(observed):
        raise ControlError(f"Git returned an invalid {option} path for {root}")
    return str(pathlib.Path(observed).resolve(strict=False))


def repository_binding(root: pathlib.Path) -> dict[str, str]:
    observed_root = _absolute_git_path(root, "--show-toplevel")
    return {
        "root": observed_root,
        "git_dir": _absolute_git_path(root, "--git-dir"),
        "common_dir": _absolute_git_path(root, "--git-common-dir"),
        "index": _absolute_git_path(root, "--git-path", "index"),
    }


def resolve_repository(candidate: str) -> tuple[pathlib.Path, pathlib.Path, dict[str, str]]:
    requested = pathlib.Path(candidate).expanduser().resolve(strict=True)
    probe = requested if requested.is_dir() else requested.parent
    root_text = git(probe, "rev-parse", "--path-format=absolute", "--show-toplevel").strip()
    if not root_text or "\0" in root_text or "\n" in root_text or not os.path.isabs(root_text):
        raise ControlError("Git returned an invalid repository root")
    root = pathlib.Path(root_text).resolve(strict=True)
    if not root.is_dir():
        raise ControlError(f"repository root is not a directory: {root}")
    try:
        requested.relative_to(root)
    except ValueError as error:
        raise ControlError(f"requested path is outside the returned repository root: {requested}") from error
    binding = repository_binding(root)
    if binding["root"] != str(root):
        raise ControlError("repository root changed while Git paths were being bound")
    return requested, root, binding


def validate_git_paths(value: object, expected_root: str, label: str) -> dict[str, str]:
    if not isinstance(value, dict):
        raise ControlError(f"{label} must be an object")
    exact_keys(value, {"root", "git_dir", "common_dir", "index"}, label)
    for field in ("root", "git_dir", "common_dir", "index"):
        observed = value.get(field)
        if (
            not isinstance(observed, str)
            or not observed
            or "\0" in observed
            or "\n" in observed
            or not os.path.isabs(observed)
            or str(pathlib.Path(observed).resolve(strict=False)) != observed
        ):
            raise ControlError(f"{label}.{field} must be a canonical absolute path")
    if value["root"] != expected_root:
        raise ControlError(f"{label}.root contradicts its repository root")
    return value


def validate_requested_path(requested: object, root: object, label: str) -> tuple[str, str]:
    for observed, field in ((requested, "requested_path"), (root, "root")):
        if (
            not isinstance(observed, str)
            or not observed
            or "\0" in observed
            or "\n" in observed
            or not os.path.isabs(observed)
            or str(pathlib.Path(observed).resolve(strict=False)) != observed
        ):
            raise ControlError(f"{label}.{field} must be a canonical absolute path")
    try:
        pathlib.Path(requested).relative_to(pathlib.Path(root))
    except ValueError as error:
        raise ControlError(f"{label}.requested_path is outside its repository root") from error
    return requested, root


def _git_config_values(root: pathlib.Path, key: str) -> list[str]:
    completed = git_result(root, "config", "--get-all", key)
    if completed.returncode == 1:
        return []
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise ControlError(f"Git could not read {key}: {detail or 'unknown error'}")
    try:
        output = completed.stdout.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ControlError(f"Git {key} is not valid UTF-8") from error
    values = output.splitlines()
    if any(not item or "\0" in item for item in values):
        raise ControlError(f"Git {key} contains an empty or unsafe value")
    return values


def _one_git_output_line(root: pathlib.Path, label: str, *arguments: str) -> str:
    output = git(root, *arguments)
    values = output.splitlines()
    if len(values) != 1 or not values[0] or "\0" in values[0]:
        raise ControlError(f"{label} must resolve to exactly one URL")
    return values[0]


def bind_origin(root: pathlib.Path, expected_repository: str) -> dict[str, str]:
    configured_fetch = _git_config_values(root, "remote.origin.url")
    if len(configured_fetch) != 1:
        raise ControlError("origin must configure exactly one fetch URL")
    configured_push = _git_config_values(root, "remote.origin.pushurl")
    if len(configured_push) > 1:
        raise ControlError("origin must not configure multiple push URLs")
    if _git_config_values(root, "remote.origin.mirror"):
        raise ControlError("origin mirror configuration is not permitted")

    fetch_url = _one_git_output_line(root, "origin fetch", "remote", "get-url", "--all", "origin")
    push_url = _one_git_output_line(
        root, "origin effective push", "remote", "get-url", "--push", "--all", "origin"
    )
    expected_fetch_url = configured_fetch[0]
    expected_push_url = configured_push[0] if configured_push else expected_fetch_url
    if fetch_url != expected_fetch_url or push_url != expected_push_url:
        raise ControlError("origin URL rewriting is not permitted for eligibility binding")

    fetch_repository = canonical_github_repository(fetch_url)
    push_repository = canonical_github_repository(push_url)
    if fetch_repository != expected_repository or push_repository != expected_repository:
        raise ControlError(
            "origin fetch and push destinations must both identify " + expected_repository
        )
    return {
        "name": "origin",
        "fetch_url": fetch_url,
        "fetch_repository": fetch_repository,
        "push_url": push_url,
        "push_repository": push_repository,
    }


def repository_status(root: pathlib.Path) -> str:
    flags = git(root, "ls-files", "-v", "-z", "--cached")
    unsafe = []
    for record in (item for item in flags.split("\0") if item):
        if len(record) < 3 or record[1] != " " or record[0] != "H":
            unsafe.append(record[2:] if len(record) >= 3 else record)
    if unsafe:
        raise ControlError(
            "repository has unsafe assume-unchanged, skip-worktree, or unmerged index flags: "
            + ", ".join(sorted(unsafe)[:10])
        )
    return git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all")


def stable_read(path: pathlib.Path, maximum_bytes: int, label: str) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise ControlError(f"{label} is unavailable or unsafe: {path}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise ControlError(f"{label} must be a regular file: {path}")
        if before.st_size > maximum_bytes:
            raise ControlError(f"{label} exceeds {maximum_bytes} bytes: {path}")
        chunks: list[bytes] = []
        remaining = before.st_size
        while remaining:
            block = os.read(descriptor, min(65536, remaining))
            if not block:
                raise ControlError(f"{label} ended while being read: {path}")
            chunks.append(block)
            remaining -= len(block)
        if os.read(descriptor, 1):
            raise ControlError(f"{label} grew while being read: {path}")
        after = os.fstat(descriptor)
        identity_before = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
        identity_after = (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
        if identity_after != identity_before:
            raise ControlError(f"{label} changed while being read: {path}")
        return b"".join(chunks)
    finally:
        os.close(descriptor)


def validate_synthetic_pilot(raw: bytes, value: dict[str, Any]) -> dict[str, Any]:
    exact_keys(value, {
        "schema", "verdict", "qualification_scope", "bookclub_eligible",
        "external_mutation", "repository", "git", "executed_at", "duration_ms",
        "tests", "claims", "evidence_sha256", "receipt_sha256",
    }, "synthetic pilot receipt")
    if value.get("schema") != OPS_PILOT_SCHEMA:
        raise ControlError(f"synthetic pilot receipt schema must be {OPS_PILOT_SCHEMA}")
    if raw != canonical_bytes(value):
        raise ControlError("synthetic pilot receipt must use canonical JSON encoding")

    receipt_sha256 = value.get("receipt_sha256")
    digest_source = dict(value)
    digest_source.pop("receipt_sha256")
    if not is_hex(receipt_sha256, 64) or receipt_sha256 != content_digest(digest_source):
        raise ControlError("synthetic pilot canonical receipt digest is invalid")

    verdict = value.get("verdict")
    if verdict not in {"PASS", "FAIL"}:
        raise ControlError("synthetic pilot verdict must be PASS or FAIL")
    passed = verdict == "PASS"
    if value.get("qualification_scope") != "synthetic-pilot-only":
        raise ControlError("synthetic pilot qualification scope is invalid")
    if value.get("bookclub_eligible") is not passed:
        raise ControlError("synthetic pilot verdict and BookClub eligibility contradict")
    if value.get("external_mutation") is not False:
        raise ControlError("synthetic pilot must declare external_mutation=false")
    if value.get("repository") != OPS_REPOSITORY:
        raise ControlError(f"synthetic pilot repository must be {OPS_REPOSITORY}")

    git_value = value.get("git")
    if not isinstance(git_value, dict):
        raise ControlError("synthetic pilot Git identity must be an object")
    exact_keys(git_value, {"head", "tree", "clean"}, "synthetic pilot Git identity")
    if not is_hex(git_value.get("head"), 40) or not is_hex(git_value.get("tree"), 40):
        raise ControlError("synthetic pilot head and tree must be exact lowercase Git object IDs")
    if git_value.get("clean") is not True:
        raise ControlError("synthetic pilot source must be clean")

    executed_at = value.get("executed_at")
    if not isinstance(executed_at, str):
        raise ControlError("synthetic pilot executed_at must be an RFC3339 UTC timestamp")
    try:
        parsed_time = datetime.datetime.strptime(executed_at, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise ControlError("synthetic pilot executed_at must use YYYY-MM-DDTHH:MM:SSZ") from error
    if parsed_time.strftime("%Y-%m-%dT%H:%M:%SZ") != executed_at:
        raise ControlError("synthetic pilot executed_at is not canonical")
    duration_ms = value.get("duration_ms")
    if isinstance(duration_ms, bool) or not isinstance(duration_ms, int) or duration_ms < 0:
        raise ControlError("synthetic pilot duration_ms must be a non-negative integer")

    tests = value.get("tests")
    if not isinstance(tests, dict):
        raise ControlError("synthetic pilot tests must be an object")
    exact_keys(tests, {"selected", "run", "failures", "errors", "skipped"}, "synthetic pilot tests")
    if tests.get("selected") != list(OPS_PILOT_CHECKS):
        raise ControlError("synthetic pilot selected tests do not match the producer contract")
    for field in ("run", "failures", "errors", "skipped"):
        observed = tests.get(field)
        if isinstance(observed, bool) or not isinstance(observed, int) or observed < 0:
            raise ControlError(f"synthetic pilot tests.{field} must be a non-negative integer")
    if tests["run"] != len(OPS_PILOT_CHECKS):
        raise ControlError("synthetic pilot did not run every required test")
    if tests["failures"] + tests["errors"] + tests["skipped"] > tests["run"]:
        raise ControlError("synthetic pilot test totals are inconsistent")
    if passed and any(tests[field] != 0 for field in ("failures", "errors", "skipped")):
        raise ControlError("passing synthetic pilot must have zero failures, errors, and skips")
    if not passed and tests["failures"] + tests["errors"] == 0:
        raise ControlError("failed synthetic pilot must report a failure or error")

    claims = value.get("claims")
    if not isinstance(claims, dict):
        raise ControlError("synthetic pilot claims must be an object")
    exact_keys(claims, set(OPS_SYNTHETIC_CLAIMS + OPS_LIVE_CLAIMS), "synthetic pilot claims")
    expected_synthetic_claim = "PASS" if passed else "UNPROVEN"
    if any(claims.get(claim) != expected_synthetic_claim for claim in OPS_SYNTHETIC_CLAIMS):
        raise ControlError("synthetic pilot claim outcomes contradict its verdict")
    if any(claims.get(claim) != "NOT_RUN" for claim in OPS_LIVE_CLAIMS):
        raise ControlError("synthetic pilot must leave live PostgreSQL and GitHub claims NOT_RUN")

    evidence = value.get("evidence_sha256")
    if not isinstance(evidence, dict):
        raise ControlError("synthetic pilot evidence_sha256 must be an object")
    exact_keys(evidence, set(OPS_EVIDENCE_FILES), "synthetic pilot evidence")
    if any(not is_hex(evidence.get(path), 64) for path in OPS_EVIDENCE_FILES):
        raise ControlError("synthetic pilot evidence digests must be lowercase SHA-256 values")

    artifact_sha256 = hashlib.sha256(raw).hexdigest()
    if (
        artifact_sha256 != OPS_PILOT_ARTIFACT_SHA256
        or receipt_sha256 != OPS_PILOT_RECEIPT_SHA256
        or git_value != {"head": OPS_PILOT_HEAD, "tree": OPS_PILOT_TREE, "clean": True}
        or evidence != OPS_PILOT_EVIDENCE_SHA256
    ):
        raise ControlError(
            "synthetic pilot is not the approved producer-sealed content address"
        )

    return {
        "status": "evidence_connected",
        "schema": OPS_PILOT_SCHEMA,
        "declared_status": "pass" if passed else "fail",
        "scope": "synthetic-pilot-only",
        "repository": OPS_REPOSITORY,
        "bookclub_eligible": passed,
        "external_mutation": False,
        "git": git_value,
        "executed_at": executed_at,
        "tests": tests,
        "claims": claims,
        "evidence_sha256": evidence,
        "receipt_sha256": receipt_sha256,
        "artifact_sha256": artifact_sha256,
    }


def bind_pilot_source(pilot: dict[str, Any], candidate: str) -> dict[str, Any]:
    requested, root, git_paths = resolve_repository(candidate)
    head = git(root, "rev-parse", "HEAD").strip()
    tree = git(root, "rev-parse", "HEAD^{tree}").strip()
    status_output = repository_status(root)
    remote_url = git(root, "remote", "get-url", "origin").strip()
    remote_repository = canonical_github_repository(remote_url)
    if status_output:
        raise ControlError("Ops pilot source is dirty")
    if (head, tree) != (pilot["git"]["head"], pilot["git"]["tree"]):
        raise ControlError("Ops pilot source has drifted from the sealed receipt")
    if remote_repository != OPS_REPOSITORY:
        raise ControlError(f"Ops pilot source origin must identify {OPS_REPOSITORY}")
    for relative_path, expected_sha256 in pilot["evidence_sha256"].items():
        evidence_path = root.joinpath(*pathlib.PurePosixPath(relative_path).parts)
        observed_sha256 = hashlib.sha256(
            stable_read(evidence_path, RECEIPT_MAXIMUM_BYTES, f"Ops evidence {relative_path}")
        ).hexdigest()
        if observed_sha256 != expected_sha256:
            raise ControlError(f"Ops pilot evidence has drifted: {relative_path}")
    final_identity = (
        repository_binding(root),
        git(root, "rev-parse", "HEAD").strip(),
        git(root, "rev-parse", "HEAD^{tree}").strip(),
        repository_status(root),
        git(root, "remote", "get-url", "origin").strip(),
    )
    if final_identity != (git_paths, head, tree, status_output, remote_url):
        raise ControlError("Ops pilot source changed while it was being verified")
    return {
        "requested_path": str(requested),
        "root": str(root),
        "git_paths": git_paths,
        "repository": remote_repository,
        "remote_url": remote_url,
        "head": head,
        "tree": tree,
        "clean": True,
        "evidence_verified": True,
    }


def validate_plan_receipt(raw: bytes, value: dict[str, Any]) -> dict[str, Any]:
    exact_keys(value, {
        "schema", "status", "execution_status", "mutation_authorized", "inventory_sha256",
        "repository_count", "repositories_requiring_attention", "cohorts",
        "promotion_contract", "plan_sha256",
    }, "progressive rollout plan")
    if value.get("schema") != PLAN_SCHEMA:
        raise ControlError(f"progressive rollout plan schema must be {PLAN_SCHEMA}")
    if value.get("status") not in {"attention", "ready_for_setup_prs"}:
        raise ControlError("progressive rollout plan status is invalid")
    if value.get("execution_status") != "plan_only":
        raise ControlError("progressive rollout plan must declare execution_status=plan_only")
    if value.get("mutation_authorized") is not False:
        raise ControlError("progressive rollout plan must declare mutation_authorized=false")
    if not is_hex(value.get("inventory_sha256"), 64):
        raise ControlError("progressive rollout plan inventory digest is invalid")

    plan_digest = value.get("plan_sha256")
    digest_source = dict(value)
    digest_source.pop("plan_sha256", None)
    cohorts = value.get("cohorts")
    if (
        not is_hex(plan_digest, 64)
        or plan_digest != content_digest(digest_source)
        or raw != canonical_bytes(value)
        or not isinstance(cohorts, list)
        or not cohorts
        or len(cohorts) > 100
    ):
        raise ControlError("progressive rollout plan content binding is invalid")

    repository_count = value.get("repository_count")
    attention = value.get("repositories_requiring_attention")
    if (
        isinstance(repository_count, bool)
        or not isinstance(repository_count, int)
        or repository_count != len(cohorts)
        or not isinstance(attention, list)
        or any(not isinstance(item, str) or not item or "\0" in item for item in attention)
    ):
        raise ControlError("progressive rollout plan repository totals are invalid")
    expected_promotion_contract = {
        "pilot": "accepted exact-head pilot evidence",
        "low-risk": "pilot accepted",
        "standard": "pilot and low-risk cohort accepted",
        "critical": "all earlier cohorts accepted with rollback evidence",
    }
    promotion_contract = value.get("promotion_contract")
    if not isinstance(promotion_contract, dict):
        raise ControlError("progressive rollout promotion contract must be an object")
    exact_keys(promotion_contract, set(expected_promotion_contract), "progressive rollout promotion contract")
    if promotion_contract != expected_promotion_contract:
        raise ControlError("progressive rollout promotion contract is invalid")

    roots: set[str] = set()
    validated_rows: list[dict[str, Any]] = []
    pilot_count = 0
    for index, row in enumerate(cohorts):
        if not isinstance(row, dict):
            raise ControlError(f"progressive rollout cohort {index} must be an object")
        exact_keys(row, {
            "cohort", "cohort_order", "repository", "inspection_sha256", "setup_pr_eligible",
            "live_rollout_eligible", "required_gate",
        }, f"progressive rollout cohort {index}")
        cohort = row.get("cohort")
        repository = row.get("repository")
        if cohort not in COHORT_ORDER or not isinstance(repository, dict):
            raise ControlError(f"progressive rollout cohort {index} identity is invalid")
        exact_keys(repository, {
            "name", "requested_path", "root", "git_paths", "head", "tree", "branch", "clean",
            "change_record_count",
        }, f"progressive rollout cohort {index} repository")
        name = repository.get("name")
        requested_path = repository.get("requested_path")
        root = repository.get("root")
        branch = repository.get("branch")
        change_count = repository.get("change_record_count")
        if (
            not isinstance(name, str)
            or not name
            or any(character in name for character in ("\0", "\n", "/"))
            or not isinstance(requested_path, str)
            or not isinstance(root, str)
            or pathlib.Path(root).name != name
            or (branch is not None and (
                not isinstance(branch, str) or not branch or "\0" in branch or "\n" in branch
            ))
            or not is_hex(repository.get("head"), 40)
            or not is_hex(repository.get("tree"), 40)
            or not isinstance(repository.get("clean"), bool)
            or isinstance(change_count, bool)
            or not isinstance(change_count, int)
            or change_count < 0
            or repository.get("clean") is not (change_count == 0)
        ):
            raise ControlError(f"progressive rollout cohort {index} repository is invalid")
        validate_requested_path(
            requested_path, root, f"progressive rollout cohort {index} repository"
        )
        validate_git_paths(
            repository.get("git_paths"), root, f"progressive rollout cohort {index} Git paths"
        )
        if root in roots:
            raise ControlError("progressive rollout plan repeats a repository root")
        roots.add(root)
        pilot_count += cohort == "pilot"
        setup_pr_eligible = row.get("setup_pr_eligible")
        cohort_order = row.get("cohort_order")
        if (
            isinstance(cohort_order, bool)
            or not isinstance(cohort_order, int)
            or cohort_order != COHORT_ORDER[cohort]
            or not is_hex(row.get("inspection_sha256"), 64)
            or not isinstance(setup_pr_eligible, bool)
            or (setup_pr_eligible and repository.get("clean") is not True)
            or row.get("live_rollout_eligible") is not False
            or row.get("required_gate") != _required_gate(cohort)
        ):
            raise ControlError(f"progressive rollout cohort {index} claims are invalid")
        validated_rows.append(row)
    if pilot_count != 1:
        raise ControlError("progressive rollout plan must contain exactly one pilot")
    expected_order = sorted(
        validated_rows,
        key=lambda row: (
            row["cohort_order"], row["repository"]["name"].casefold(), row["repository"]["root"]
        ),
    )
    if validated_rows != expected_order:
        raise ControlError("progressive rollout cohorts are not in canonical order")
    expected_attention = [
        row["repository"]["name"] for row in validated_rows if row["setup_pr_eligible"] is False
    ]
    expected_status = "attention" if expected_attention else "ready_for_setup_prs"
    if attention != expected_attention or value["status"] != expected_status:
        raise ControlError("progressive rollout attention summary contradicts its cohorts")

    repositories = [item["repository"] for item in cohorts]
    return {
        "status": "evidence_connected",
        "artifact_sha256": hashlib.sha256(raw).hexdigest(),
        "schema": PLAN_SCHEMA,
        "declared_status": value["status"],
        "scope": "plan-only",
        "execution_status": "plan_only",
        "mutation_authorized": False,
        "repository": repositories[0] if len(repositories) == 1 else None,
        "repositories": repositories,
        "repository_count": len(repositories),
        "setup_pr_eligible": all(item.get("setup_pr_eligible") is True for item in cohorts),
        "live_rollout_eligible": False,
        "bookclub_eligible": None,
    }


def validate_eligibility_receipt(raw: bytes, value: dict[str, Any]) -> dict[str, Any]:
    exact_keys(value, {
        "schema", "status", "outcome", "mutation_authorized", "live_rollout_passed",
        "synthetic_pilot_accepted", "pilot", "target", "eligibility_sha256",
    }, "repository eligibility receipt")
    digest_source = dict(value)
    eligibility_sha256 = digest_source.pop("eligibility_sha256")
    if (
        not is_hex(eligibility_sha256, 64)
        or eligibility_sha256 != content_digest(digest_source)
        or raw != canonical_bytes(value)
    ):
        raise ControlError("repository eligibility content binding is invalid")
    if (
        value.get("schema") != ELIGIBILITY_SCHEMA
        or value.get("status") != "eligible"
        or value.get("outcome") != "eligible_for_separately_authorized_live_pilot"
        or value.get("mutation_authorized") is not False
        or value.get("live_rollout_passed") is not False
        or value.get("synthetic_pilot_accepted") is not True
    ):
        raise ControlError("repository eligibility claims are invalid")

    pilot = value.get("pilot")
    target = value.get("target")
    if not isinstance(pilot, dict) or not isinstance(target, dict):
        raise ControlError("repository eligibility pilot and target must be objects")
    exact_keys(pilot, {"receipt", "artifact_sha256", "source"}, "repository eligibility pilot")
    embedded_receipt = pilot.get("receipt")
    source = pilot.get("source")
    if not isinstance(embedded_receipt, dict) or not isinstance(source, dict):
        raise ControlError("repository eligibility pilot receipt and source must be objects")
    validated_pilot = validate_synthetic_pilot(canonical_bytes(embedded_receipt), embedded_receipt)
    if validated_pilot["declared_status"] != "pass":
        raise ControlError("repository eligibility embedded pilot did not pass")
    exact_keys(source, {
        "requested_path", "root", "git_paths", "repository", "remote_url", "head", "tree",
        "clean", "evidence_verified",
    }, "repository eligibility pilot source")
    if (
        not isinstance(source.get("requested_path"), str)
        or not isinstance(source.get("root"), str)
        or not isinstance(source.get("remote_url"), str)
        or source.get("repository") != OPS_REPOSITORY
        or pilot.get("artifact_sha256") != validated_pilot["artifact_sha256"]
        or not is_hex(source.get("head"), 40)
        or not is_hex(source.get("tree"), 40)
        or source.get("clean") is not True
        or source.get("evidence_verified") is not True
    ):
        raise ControlError("repository eligibility pilot binding is invalid")
    validate_requested_path(
        source.get("requested_path"), source.get("root"), "repository eligibility pilot source"
    )
    validate_git_paths(source.get("git_paths"), source["root"], "repository eligibility pilot Git paths")
    if canonical_github_repository(source["remote_url"]) != OPS_REPOSITORY:
        raise ControlError("repository eligibility pilot source origin is invalid")
    observed_source = bind_pilot_source(validated_pilot, source.get("requested_path", ""))
    if observed_source != source:
        raise ControlError("repository eligibility pilot source binding has drifted")

    exact_keys(target, {
        "name", "requested_path", "root", "git_paths", "repository", "remote", "branch",
        "canonical_branch", "head", "tree", "clean", "divergence", "upstream",
        "instructions", "inspection_sha256",
    }, "repository eligibility target")
    remote = target.get("remote")
    divergence = target.get("divergence")
    upstream = target.get("upstream")
    instructions = target.get("instructions")
    if not all(isinstance(item, dict) for item in (remote, divergence, upstream, instructions)):
        raise ControlError("repository eligibility target bindings must be objects")
    exact_keys(remote, {
        "name", "fetch_url", "fetch_repository", "push_url", "push_repository",
    }, "repository eligibility target remote")
    exact_keys(divergence, {"ahead", "behind"}, "repository eligibility target divergence")
    exact_keys(upstream, {"ref", "head", "tree", "observed_locally"}, "repository eligibility upstream")
    exact_keys(instructions, {"path", "sha256", "size"}, "repository eligibility instructions")
    if (
        not isinstance(target.get("name"), str)
        or not isinstance(target.get("requested_path"), str)
        or not isinstance(target.get("root"), str)
        or not isinstance(target.get("repository"), str)
        or not isinstance(remote.get("fetch_url"), str)
        or not isinstance(remote.get("push_url"), str)
        or target.get("repository") != remote.get("fetch_repository")
        or target.get("repository") != remote.get("push_repository")
        or remote.get("name") != "origin"
        or target.get("branch") != "main"
        or target.get("canonical_branch") != "main"
        or target.get("clean") is not True
        or divergence != {"ahead": 0, "behind": 0}
        or upstream.get("ref") != "refs/remotes/origin/main"
        or upstream.get("observed_locally") is not True
        or target.get("head") != upstream.get("head")
        or target.get("tree") != upstream.get("tree")
        or not is_hex(target.get("head"), 40)
        or not is_hex(target.get("tree"), 40)
        or not is_hex(target.get("inspection_sha256"), 64)
        or instructions.get("path") != "AGENTS.md"
        or not is_hex(instructions.get("sha256"), 64)
        or isinstance(instructions.get("size"), bool)
        or not isinstance(instructions.get("size"), int)
        or instructions.get("size", -1) < 0
    ):
        raise ControlError("repository eligibility target identity is invalid")
    validate_requested_path(
        target.get("requested_path"), target.get("root"), "repository eligibility target"
    )
    validate_git_paths(target.get("git_paths"), target["root"], "repository eligibility target Git paths")
    if (
        canonical_github_repository(remote.get("fetch_url", "")) != target.get("repository")
        or canonical_github_repository(remote.get("push_url", "")) != target.get("repository")
    ):
        raise ControlError("repository eligibility target origin contradicts its repository identity")
    observed_target = bind_target_repository(
        target.get("requested_path", ""), target.get("repository", "")
    )
    if observed_target != target:
        raise ControlError("repository eligibility target binding has drifted")

    return {
        "status": "evidence_connected",
        "schema": ELIGIBILITY_SCHEMA,
        "declared_status": "eligible",
        "scope": "live-pilot-eligibility-only",
        "mutation_authorized": False,
        "live_rollout_passed": False,
        "synthetic_pilot_accepted": True,
        "repository": target["repository"],
        "target": target,
        "pilot": pilot,
        "eligibility_sha256": eligibility_sha256,
        "artifact_sha256": hashlib.sha256(raw).hexdigest(),
        "bookclub_eligible": None,
    }


def consume_rollout_receipt(candidate: str) -> dict[str, Any]:
    path = pathlib.Path(candidate).expanduser()
    if not path.is_absolute():
        path = pathlib.Path(os.path.abspath(path))
    raw, value = read_json_document(path, "repository rollout receipt")
    schema = value.get("schema")
    if schema == GENERIC_ROLLOUT_SCHEMA:
        raise ControlError(
            "unbound generic repository rollout receipts are not trusted; "
            "use a producer-sealed pilot, eligibility, or progressive-plan receipt"
        )
    if schema == OPS_PILOT_SCHEMA:
        return validate_synthetic_pilot(raw, value)
    if schema == PLAN_SCHEMA:
        return validate_plan_receipt(raw, value)
    if schema == ELIGIBILITY_SCHEMA:
        return validate_eligibility_receipt(raw, value)
    raise ControlError("unsupported repository rollout receipt schema")


def repository_files(root: pathlib.Path) -> list[str]:
    output = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
    paths = sorted({item for item in output.split("\0") if item})
    if len(paths) > 100_000:
        raise ControlError(f"Repository inventory exceeds 100,000 files for {root}")
    return paths


def inspect_repository(candidate: str) -> dict[str, Any]:
    requested, root, git_paths = resolve_repository(candidate)
    head = git(root, "rev-parse", "HEAD").strip()
    tree = git(root, "rev-parse", "HEAD^{tree}").strip()
    branch = git(root, "symbolic-ref", "--quiet", "--short", "HEAD").strip() if _has_branch(root) else None
    status_output = repository_status(root)
    status_records = [item for item in status_output.split("\0") if item]
    files = repository_files(root)
    agents_files = [path for path in files if pathlib.PurePosixPath(path).name == "AGENTS.md"]
    unresolved = [path for path in files if path.endswith(".acfs-new")]
    workflows = [
        path
        for path in files
        if path.startswith(".github/workflows/") and pathlib.PurePosixPath(path).suffix in {".yaml", ".yml"}
    ]
    automation = [
        path
        for path in files
        if path in {".pre-commit-config.yaml", ".pre-commit-config.yml", "lefthook.yml", "lefthook.yaml"}
        or path.startswith(".husky/")
    ]
    root_agents = root / "AGENTS.md"
    root_agents_receipt = None
    if root_agents.is_file() and not root_agents.is_symlink():
        root_agents_raw = stable_read(root_agents, 4 * 1024 * 1024, "AGENTS.md")
        root_agents_receipt = {
            "path": "AGENTS.md",
            "sha256": hashlib.sha256(root_agents_raw).hexdigest(),
            "size": len(root_agents_raw),
        }

    final_identity = (
        repository_binding(root),
        git(root, "rev-parse", "HEAD").strip(),
        git(root, "rev-parse", "HEAD^{tree}").strip(),
        repository_status(root),
    )
    if final_identity != (git_paths, head, tree, status_output):
        raise ControlError(f"Repository changed while being inspected: {root}")

    clean = not status_records
    setup_pr_eligible = clean and not unresolved
    actions: list[dict[str, str]] = []
    if not clean:
        actions.append({"code": "preserve_dirty_state", "action": "Preserve or commit local changes before onboarding."})
    if unresolved:
        actions.append({"code": "resolve_acfs_new", "action": "Reconcile every .acfs-new file before onboarding."})
    if root_agents_receipt:
        actions.append({"code": "reconcile_guidance", "action": "Reconcile the existing root AGENTS.md; do not overwrite it."})
    else:
        actions.append({"code": "propose_guidance", "action": "Propose a bounded root AGENTS.md in the setup PR."})
    actions.append({"code": "qualify_admission", "action": "Attach passing admission evidence before any live rollout."})

    value: dict[str, Any] = {
        "schema": INSPECTION_SCHEMA,
        "status": "ready_for_bounded_setup_pr" if setup_pr_eligible else "attention",
        "mutation_authorized": False,
        "repository": {
            "name": root.name,
            "requested_path": str(requested),
            "root": str(root),
            "git_paths": git_paths,
            "head": head,
            "tree": tree,
            "branch": branch,
            "clean": clean,
            "change_record_count": len(status_records),
        },
        "guidance": {
            "root_agents": root_agents_receipt,
            "agents_files": agents_files,
            "unresolved_acfs_new": unresolved,
        },
        "automation": {
            "github_workflows": workflows,
            "local_hook_configs": automation,
        },
        "admission": {
            "setup_pr_eligible": setup_pr_eligible,
            "live_rollout_eligible": False,
            "reason": "Live rollout requires separately attached passing admission evidence.",
        },
        "recommended_actions": actions,
    }
    value["inspection_sha256"] = content_digest(value)
    return value


def _has_branch(root: pathlib.Path) -> bool:
    completed = git_result(root, "symbolic-ref", "--quiet", "HEAD", timeout=5)
    return completed.returncode == 0


def bind_target_repository(target_path: str, expected_target_repository: str) -> dict[str, Any]:
    target_repository = normalize_repository_name(expected_target_repository)
    inspection = inspect_repository(target_path)
    repository = inspection["repository"]
    root = pathlib.Path(repository["root"])
    if repository["clean"] is not True:
        raise ControlError("target repository is dirty")
    if repository["branch"] != "main":
        raise ControlError("target repository must be checked out on canonical branch main")
    if inspection["guidance"]["unresolved_acfs_new"]:
        raise ControlError("target repository has unresolved .acfs-new files")
    instructions = inspection["guidance"]["root_agents"]
    if not isinstance(instructions, dict):
        raise ControlError("target repository needs a stable root AGENTS.md instructions digest")

    origin = bind_origin(root, target_repository)
    upstream_ref = "refs/remotes/origin/main"
    upstream_head = git(root, "rev-parse", "--verify", upstream_ref).strip()
    upstream_tree = git(root, "rev-parse", f"{upstream_ref}^{{tree}}").strip()
    divergence_fields = git(root, "rev-list", "--left-right", "--count", f"HEAD...{upstream_ref}").split()
    if len(divergence_fields) != 2 or any(not field.isdigit() for field in divergence_fields):
        raise ControlError("target repository divergence result is invalid")
    ahead, behind = (int(field) for field in divergence_fields)
    if ahead or behind or repository["head"] != upstream_head or repository["tree"] != upstream_tree:
        raise ControlError("target repository has drifted from the locally observed origin/main")

    final_identity = (
        repository_binding(root),
        git(root, "rev-parse", "HEAD").strip(),
        git(root, "rev-parse", "HEAD^{tree}").strip(),
        repository_status(root),
        git(root, "symbolic-ref", "--quiet", "--short", "HEAD").strip(),
        bind_origin(root, target_repository),
        git(root, "rev-parse", "--verify", upstream_ref).strip(),
        git(root, "rev-parse", f"{upstream_ref}^{{tree}}").strip(),
        tuple(git(root, "rev-list", "--left-right", "--count", f"HEAD...{upstream_ref}").split()),
    )
    expected_identity = (
        repository["git_paths"], repository["head"], repository["tree"], "", "main", origin,
        upstream_head, upstream_tree, (str(ahead), str(behind)),
    )
    if final_identity != expected_identity:
        raise ControlError("target repository changed while eligibility was being evaluated")
    return {
        "name": repository["name"],
        "requested_path": repository["requested_path"],
        "root": repository["root"],
        "git_paths": repository["git_paths"],
        "repository": target_repository,
        "remote": origin,
        "branch": "main",
        "canonical_branch": "main",
        "head": repository["head"],
        "tree": repository["tree"],
        "clean": True,
        "divergence": {"ahead": 0, "behind": 0},
        "upstream": {
            "ref": upstream_ref,
            "head": upstream_head,
            "tree": upstream_tree,
            "observed_locally": True,
        },
        "instructions": instructions,
        "inspection_sha256": inspection["inspection_sha256"],
    }


def build_live_pilot_eligibility(
    target_path: str,
    pilot_receipt_path: str,
    pilot_source_path: str,
    expected_target_repository: str,
) -> dict[str, Any]:
    pilot_path = pathlib.Path(pilot_receipt_path).expanduser()
    if not pilot_path.is_absolute():
        pilot_path = pathlib.Path(os.path.abspath(pilot_path))
    pilot_raw, pilot_value = read_json_document(pilot_path, "Ops synthetic pilot receipt")
    pilot = validate_synthetic_pilot(pilot_raw, pilot_value)
    if pilot["declared_status"] != "pass":
        raise ControlError("Ops synthetic pilot receipt is valid but did not pass")
    pilot_source = bind_pilot_source(pilot, pilot_source_path)
    target = bind_target_repository(target_path, expected_target_repository)

    value: dict[str, Any] = {
        "schema": ELIGIBILITY_SCHEMA,
        "status": "eligible",
        "outcome": "eligible_for_separately_authorized_live_pilot",
        "mutation_authorized": False,
        "live_rollout_passed": False,
        "synthetic_pilot_accepted": True,
        "pilot": {
            "receipt": pilot_value,
            "artifact_sha256": pilot["artifact_sha256"],
            "source": pilot_source,
        },
        "target": target,
    }
    value["eligibility_sha256"] = content_digest(value)
    return value


def read_inventory(path: pathlib.Path) -> tuple[dict[str, Any], str]:
    if not path.is_absolute():
        path = pathlib.Path(os.path.abspath(path))
    raw = stable_read(path, 1024 * 1024, "rollout inventory")
    try:
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ControlError(f"Rollout inventory is not valid JSON: {error}") from error
    if not isinstance(value, dict) or value.get("schema") != INVENTORY_SCHEMA:
        raise ControlError(f"Rollout inventory schema must be {INVENTORY_SCHEMA}")
    repositories = value.get("repositories")
    if not isinstance(repositories, list) or not repositories:
        raise ControlError("Rollout inventory repositories must be a non-empty array")
    if len(repositories) > 100:
        raise ControlError("Rollout inventory cannot exceed 100 repositories")
    return value, hashlib.sha256(raw).hexdigest()


def build_rollout_plan(inventory_path: str) -> dict[str, Any]:
    inventory, inventory_sha256 = read_inventory(pathlib.Path(inventory_path))
    rows: list[dict[str, Any]] = []
    roots: set[str] = set()
    pilots = 0
    for index, item in enumerate(inventory["repositories"]):
        if not isinstance(item, dict):
            raise ControlError(f"Repository entry {index} must be an object")
        path = item.get("path")
        cohort = item.get("cohort")
        if not isinstance(path, str) or not path:
            raise ControlError(f"Repository entry {index} needs a path")
        if cohort not in COHORT_ORDER:
            raise ControlError(f"Repository entry {index} cohort must be pilot, low-risk, standard, or critical")
        pilots += cohort == "pilot"
        inspection = inspect_repository(path)
        root = inspection["repository"]["root"]
        if root in roots:
            raise ControlError(f"Rollout inventory repeats repository root: {root}")
        roots.add(root)
        rows.append({
            "cohort": cohort,
            "cohort_order": COHORT_ORDER[cohort],
            "repository": inspection["repository"],
            "inspection_sha256": inspection["inspection_sha256"],
            "setup_pr_eligible": inspection["admission"]["setup_pr_eligible"],
            "live_rollout_eligible": False,
            "required_gate": _required_gate(cohort),
        })
    if pilots != 1:
        raise ControlError(f"Progressive rollout requires exactly one pilot repository; observed {pilots}")
    rows.sort(key=lambda row: (row["cohort_order"], row["repository"]["name"].casefold(), row["repository"]["root"]))
    attention = [row["repository"]["name"] for row in rows if not row["setup_pr_eligible"]]
    value: dict[str, Any] = {
        "schema": PLAN_SCHEMA,
        "status": "attention" if attention else "ready_for_setup_prs",
        "execution_status": "plan_only",
        "mutation_authorized": False,
        "inventory_sha256": inventory_sha256,
        "repository_count": len(rows),
        "repositories_requiring_attention": attention,
        "cohorts": rows,
        "promotion_contract": {
            "pilot": "accepted exact-head pilot evidence",
            "low-risk": "pilot accepted",
            "standard": "pilot and low-risk cohort accepted",
            "critical": "all earlier cohorts accepted with rollback evidence",
        },
    }
    value["plan_sha256"] = content_digest(value)
    return value


def _required_gate(cohort: str) -> str:
    return {
        "pilot": "synthetic pilot accepted and live mutation explicitly authorized",
        "low-risk": "pilot accepted",
        "standard": "low-risk cohort accepted",
        "critical": "standard cohort accepted with rollback evidence",
    }[cohort]


def render_inspection(value: dict[str, Any]) -> str:
    repository = value["repository"]
    guidance = value["guidance"]
    lines = [
        f"Repository: {repository['name']}",
        f"Status: {value['status']}",
        f"Source: {repository['head']}/{repository['tree']}",
        f"Clean: {str(repository['clean']).lower()}",
        f"Root AGENTS.md: {'present' if guidance['root_agents'] else 'absent'}",
        f"Unresolved .acfs-new: {len(guidance['unresolved_acfs_new'])}",
        "Mutation authorized: false",
    ]
    lines.extend(f"Next: {item['action']}" for item in value["recommended_actions"])
    return "\n".join(lines)


def render_plan(value: dict[str, Any]) -> str:
    lines = [
        f"Progressive rollout: {value['status']}",
        f"Repositories: {value['repository_count']}",
        "Execution: plan only; mutation authorized: false",
    ]
    for row in value["cohorts"]:
        lines.append(
            f"{row['cohort']}: {row['repository']['name']} — "
            f"{'setup-ready' if row['setup_pr_eligible'] else 'attention'} — gate: {row['required_gate']}"
        )
    return "\n".join(lines)


def render_eligibility(value: dict[str, Any]) -> str:
    target = value["target"]
    pilot = value["pilot"]
    receipt = pilot["receipt"]
    return "\n".join([
        f"Repository: {target['repository']}",
        f"Eligibility: {value['outcome']}",
        f"Target: {target['head']}/{target['tree']}",
        f"Ops pilot: {pilot['source']['head']}/{pilot['source']['tree']}",
        f"Pilot receipt: {receipt['receipt_sha256']}",
        "Mutation authorized: false",
        "Live rollout passed: false",
    ])


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    subparsers = value.add_subparsers(dest="command", required=True)
    inspect = subparsers.add_parser("inspect", help="inspect one repository without mutation")
    inspect.add_argument("path")
    inspect.add_argument("--json", action="store_true")
    eligibility = subparsers.add_parser(
        "eligibility",
        help="bind a passing Ops synthetic pilot to one exact clean canonical-main target",
    )
    eligibility.add_argument("path")
    eligibility.add_argument("--pilot-receipt", required=True)
    eligibility.add_argument("--pilot-source", required=True)
    eligibility.add_argument("--target-repository", required=True)
    eligibility.add_argument("--json", action="store_true")
    plan = subparsers.add_parser("plan", help="build a progressive rollout plan from an inventory")
    plan.add_argument("inventory")
    plan.add_argument("--json", action="store_true")
    return value


def main() -> int:
    arguments = parser().parse_args()
    try:
        if arguments.command == "inspect":
            value = inspect_repository(arguments.path)
            output = canonical_bytes(value).decode().rstrip() if arguments.json else render_inspection(value)
        elif arguments.command == "eligibility":
            value = build_live_pilot_eligibility(
                arguments.path,
                arguments.pilot_receipt,
                arguments.pilot_source,
                arguments.target_repository,
            )
            output = canonical_bytes(value).decode().rstrip() if arguments.json else render_eligibility(value)
        else:
            value = build_rollout_plan(arguments.inventory)
            output = canonical_bytes(value).decode().rstrip() if arguments.json else render_plan(value)
    except (ControlError, OSError, RuntimeError) as error:
        print(f"Flywheel repository control: {error}", file=sys.stderr)
        return 2
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
