#!/usr/bin/env python3
"""Read-only repository onboarding inspection and rollout planning."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
from typing import Any


INSPECTION_SCHEMA = "agent-flywheel.repository-inspection/v1"
INVENTORY_SCHEMA = "agent-flywheel.rollout-inventory/v1"
PLAN_SCHEMA = "agent-flywheel.progressive-rollout-plan/v1"
COHORT_ORDER = {"pilot": 0, "low-risk": 1, "standard": 2, "critical": 3}


class ControlError(ValueError):
    """An actionable input or repository error."""


def canonical_bytes(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def content_digest(value: object) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


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


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(65536):
            digest.update(block)
    return digest.hexdigest()


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
    status_records = [item for item in git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all").split("\0") if item]
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
        root_agents_receipt = {
            "path": "AGENTS.md",
            "sha256": sha256_file(root_agents),
            "size": root_agents.stat().st_size,
        }

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


def read_inventory(path: pathlib.Path) -> tuple[dict[str, Any], str]:
    if not path.is_absolute():
        path = path.resolve()
    if path.is_symlink() or not path.is_file():
        raise ControlError(f"Rollout inventory must be a regular file: {path}")
    raw = path.read_bytes()
    if len(raw) > 1024 * 1024:
        raise ControlError("Rollout inventory exceeds 1 MiB")
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


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    subparsers = value.add_subparsers(dest="command", required=True)
    inspect = subparsers.add_parser("inspect", help="inspect one repository without mutation")
    inspect.add_argument("path")
    inspect.add_argument("--json", action="store_true")
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
