# ACFS Workflow Templates

Ready-to-use GitHub Actions workflow templates for ACFS-owned tool repositories.

## Available Templates

| Template | Use Case |
|----------|----------|
| `notify-acfs-workflow.yml` | Full repository-dispatch workflow with checksum comparison and dry-run support |
| `validate-acfs-workflow.yml` | Validation workflow for checking a tool repo's ACFS integration |
| `notify-acfs-root.yml` | Repos with `install.sh` at repository root |
| `notify-acfs-scripts.yml` | Repos with `install.sh` in `scripts/` directory |

## Quick Setup

1. **Create PAT**: Generate a Personal Access Token with `contents:read` on the `agentic_coding_flywheel_setup` repo

2. **Add Secret**: In your tool repo, create a secret named `ACFS_REPO_DISPATCH_TOKEN` with the PAT value

3. **Copy Template**: Copy the appropriate template to `.github/workflows/notify-acfs.yml`

4. **Test**: Trigger the workflow manually or push a change to your install script

## Which Template to Use

Check your `checksums.yaml` entry to see the installer path:

```yaml
# Root install.sh → use notify-acfs-root.yml
ntm:
  url: "https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh"

# Commissioning exception: Agent Mail is on HOLD and has no admitted upstream
# notification/install route until its exact-source/auth/state contract passes.
# Do not substitute refs/heads/main or a published binary installer here.

# Immutable root installer identity used by the admitted beads_rust contract.
br:
  url: "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/7eaf34b76927b4deadc913889f50fb06a8f803d7/install.sh"
```

## Full Documentation

See `acfs/docs/repo-dispatch-setup.md` for complete setup instructions, troubleshooting, and security considerations.
