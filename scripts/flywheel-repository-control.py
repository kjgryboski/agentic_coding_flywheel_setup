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
RECEIPT_MAXIMUM_BYTES = 4 * 1024 * 1024


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
        parsed = urllib.parse.urlsplit(candidate)
        if parsed.hostname != "github.com" or parsed.password or parsed.query or parsed.fragment:
            raise ControlError("origin must be an uncredentialed GitHub repository URL")
        if parsed.scheme in {"http", "https"} and parsed.username is not None:
            raise ControlError("origin must not contain credentials")
        if parsed.scheme == "ssh" and parsed.username not in {None, "git"}:
            raise ControlError("origin SSH user must be git")
        if parsed.scheme not in {"http", "https", "ssh", "git"}:
            raise ControlError("origin must use HTTPS, SSH, or the Git protocol")
        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) != 2:
            raise ControlError("origin must identify exactly one GitHub owner/repository")
        owner, repository = parts
        if repository.endswith(".git"):
            repository = repository[:-4]
    return normalize_repository_name(f"{owner}/{repository}")


def normalize_repository_name(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ControlError("repository identity must be OWNER/REPOSITORY")
    return value.casefold()


def git(root: pathlib.Path, *arguments: str) -> str:
    try:
        completed = subprocess.run(
            ["git", "-C", str(root), *arguments],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ControlError(f"Git inspection failed for {root}: {error}") from error
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise ControlError(f"Git inspection failed for {root}: {detail or 'unknown error'}")
    if len(completed.stdout) > 16 * 1024 * 1024:
        raise ControlError(f"Git inspection output exceeds 16 MiB for {root}")
    return completed.stdout.decode("utf-8", errors="replace")


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
        "artifact_sha256": hashlib.sha256(raw).hexdigest(),
    }


def bind_pilot_source(pilot: dict[str, Any], candidate: str) -> dict[str, Any]:
    requested = pathlib.Path(candidate).expanduser().resolve(strict=True)
    probe = requested if requested.is_dir() else requested.parent
    root = pathlib.Path(git(probe, "rev-parse", "--show-toplevel").strip()).resolve(strict=True)
    head = git(root, "rev-parse", "HEAD").strip()
    tree = git(root, "rev-parse", "HEAD^{tree}").strip()
    status_output = git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all")
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
        git(root, "rev-parse", "HEAD").strip(),
        git(root, "rev-parse", "HEAD^{tree}").strip(),
        git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all"),
        git(root, "remote", "get-url", "origin").strip(),
    )
    if final_identity != (head, tree, status_output, remote_url):
        raise ControlError("Ops pilot source changed while it was being verified")
    return {
        "root": str(root),
        "repository": remote_repository,
        "remote_url": remote_url,
        "head": head,
        "tree": tree,
        "clean": True,
        "evidence_verified": True,
    }


def validate_plan_receipt(raw: bytes, value: dict[str, Any]) -> dict[str, Any]:
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
        or any(not isinstance(item, dict) or not isinstance(item.get("repository"), dict) for item in cohorts)
    ):
        raise ControlError("progressive rollout plan content binding is invalid")
    repositories = [item["repository"] for item in cohorts]
    return {
        "status": "evidence_connected",
        "artifact_sha256": hashlib.sha256(raw).hexdigest(),
        "schema": PLAN_SCHEMA,
        "declared_status": value.get("status"),
        "scope": "plan-only",
        "execution_status": value.get("execution_status"),
        "mutation_authorized": value.get("mutation_authorized"),
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
        "root", "repository", "remote_url", "head", "tree", "clean", "evidence_verified",
    }, "repository eligibility pilot source")
    if (
        not isinstance(source.get("root"), str)
        or not isinstance(source.get("remote_url"), str)
        or source.get("repository") != OPS_REPOSITORY
        or pilot.get("artifact_sha256") != validated_pilot["artifact_sha256"]
        or not is_hex(source.get("head"), 40)
        or not is_hex(source.get("tree"), 40)
        or source.get("clean") is not True
        or source.get("evidence_verified") is not True
    ):
        raise ControlError("repository eligibility pilot binding is invalid")
    if canonical_github_repository(source["remote_url"]) != OPS_REPOSITORY:
        raise ControlError("repository eligibility pilot source origin is invalid")
    observed_source = bind_pilot_source(validated_pilot, source.get("root", ""))
    if observed_source != source:
        raise ControlError("repository eligibility pilot source binding has drifted")

    exact_keys(target, {
        "name", "root", "repository", "remote", "branch", "canonical_branch", "head", "tree",
        "clean", "divergence", "upstream", "instructions", "inspection_sha256",
    }, "repository eligibility target")
    remote = target.get("remote")
    divergence = target.get("divergence")
    upstream = target.get("upstream")
    instructions = target.get("instructions")
    if not all(isinstance(item, dict) for item in (remote, divergence, upstream, instructions)):
        raise ControlError("repository eligibility target bindings must be objects")
    exact_keys(remote, {"name", "url", "repository"}, "repository eligibility target remote")
    exact_keys(divergence, {"ahead", "behind"}, "repository eligibility target divergence")
    exact_keys(upstream, {"ref", "head", "tree", "observed_locally"}, "repository eligibility upstream")
    exact_keys(instructions, {"path", "sha256", "size"}, "repository eligibility instructions")
    if (
        not isinstance(target.get("name"), str)
        or not isinstance(target.get("root"), str)
        or not isinstance(target.get("repository"), str)
        or not isinstance(remote.get("url"), str)
        or target.get("repository") != remote.get("repository")
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
    if canonical_github_repository(remote.get("url", "")) != target.get("repository"):
        raise ControlError("repository eligibility target origin contradicts its repository identity")
    observed_target = bind_target_repository(target.get("root", ""), target.get("repository", ""))
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
    requested = pathlib.Path(candidate).expanduser().resolve(strict=True)
    probe = requested if requested.is_dir() else requested.parent
    root = pathlib.Path(git(probe, "rev-parse", "--show-toplevel").strip()).resolve(strict=True)
    head = git(root, "rev-parse", "HEAD").strip()
    tree = git(root, "rev-parse", "HEAD^{tree}").strip()
    branch = git(root, "symbolic-ref", "--quiet", "--short", "HEAD").strip() if _has_branch(root) else None
    status_output = git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all")
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
        git(root, "rev-parse", "HEAD").strip(),
        git(root, "rev-parse", "HEAD^{tree}").strip(),
        git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all"),
    )
    if final_identity != (head, tree, status_output):
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
            "root": str(root),
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
    completed = subprocess.run(
        ["git", "-C", str(root), "symbolic-ref", "--quiet", "HEAD"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
    )
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

    remote_url = git(root, "remote", "get-url", "origin").strip()
    observed_target_repository = canonical_github_repository(remote_url)
    if observed_target_repository != target_repository:
        raise ControlError(
            f"target origin identifies {observed_target_repository}, expected {target_repository}"
        )
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
        git(root, "rev-parse", "HEAD").strip(),
        git(root, "rev-parse", "HEAD^{tree}").strip(),
        git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all"),
        git(root, "symbolic-ref", "--quiet", "--short", "HEAD").strip(),
        git(root, "remote", "get-url", "origin").strip(),
        git(root, "rev-parse", "--verify", upstream_ref).strip(),
        git(root, "rev-parse", f"{upstream_ref}^{{tree}}").strip(),
        tuple(git(root, "rev-list", "--left-right", "--count", f"HEAD...{upstream_ref}").split()),
    )
    expected_identity = (
        repository["head"], repository["tree"], "", "main", remote_url,
        upstream_head, upstream_tree, (str(ahead), str(behind)),
    )
    if final_identity != expected_identity:
        raise ControlError("target repository changed while eligibility was being evaluated")
    return {
        "name": repository["name"],
        "root": repository["root"],
        "repository": target_repository,
        "remote": {"name": "origin", "url": remote_url, "repository": target_repository},
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
