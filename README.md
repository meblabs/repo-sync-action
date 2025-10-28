# repo-sync-action

Composite GitHub Action to sync repos commits

Automated **commit-level sync** between a “core” repository and one or more
installation/target repositories.

`repo-sync-action` cherry-picks _only_ the new commits that are missing in the target branch **after** the most recent commit already present. Commits from the core repository that were previously skipped or not included will **not** be synchronized retroactively.

This approach preserves the original Conventional Commit messages—ideal for projects using **semantic-release** or similar tools.

> **What changed**
>
> - The action now accepts **two tokens**: one for the **source** repo (read) and one for the **target** repo (write).
> - PR creation now happens via **GitHub CLI (`gh`)** inside the action.

## How it works

1. **Fetch `core/<source_branch>`** and create a temporary branch
   `<pr_branch>-<run_id>` on the target repo
   (default: `sync/core-<run_id>`).

2. **Detect missing commits**

   ```bash
   git cherry -v <target_branch> core/<source_branch>
   ```

   The script scans the list in reverse and collects every "`+`" commit until it
   reaches the first "`-`" (a patch that already exists on the target).

3. **Cherry-pick** those commits (oldest → newest).
   Conflicts, if any, fail the run so you can resolve them manually.

4. **Push the branch** and **open a Pull Request** via the **GitHub CLI (`gh`)**.

The result is a clean, linear history containing **only** the new commits from
the core repository.

## Inputs

| Name            | Required | Default     | Description                                                      |
| --------------- | -------- | ----------- | ---------------------------------------------------------------- |
| `source_repo`   | **Yes**  |             | `owner/repo` of the core repository.                             |
| `source_branch` | No       | `dev`       | Branch to sync _from_ in the core repo.                          |
| `target_branch` | No       | `dev`       | Branch to sync _to_ in the target repo.                          |
| `source_token`  | **Yes**  |             | Token with **read** access to the source repository.             |
| `target_token`  | **Yes**  |             | Token with **write/PR** access to the target repository.         |
| `pr_branch`     | No       | `sync/core` | Prefix for the temporary branch. The action appends `-<run_id>`. |
| `pr_title`      | No       | `Sync Core` | Title of the Pull Request.                                       |
| `pr_labels`     | No       | `sync-core` | Comma-separated list of labels to apply to the PR.               |

## Minimal Usage Example

```yaml
# .github/workflows/syncCore.yml  (in the target repository)
name: Sync from core

on:
  workflow_dispatch: # run manually from the Actions tab

permissions:
  contents: write
  pull-requests: write

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - name: repo-sync-action
        uses: meblabs/repo-sync-action@v1
        with:
          source_repo: Meblabs/Core # core repository
          source_token: ${{ secrets.TEMPLATE_MEBBOT }} # fine-grained PAT: read on source repo
          target_token: ${{ secrets.MEBBOT }} # fine-grained PAT: write/PR on target repo
```

## Token permissions

### Fine-grained PATs (recommended)

- **Source token**: grant access **only** to the source repo
  Permissions: **Contents: Read**.
- **Target token**: grant access **only** to the target repo
  Permissions: **Contents: Read & Write**, **Pull requests: Read & Write**.
  _(Optional)_ **Issues: Write** if the action creates labels.
  _(Optional)_ **Workflows: Read & Write** only if cherry-picked commits modify `.github/workflows`.

### Classic PATs (fallback)

Use **two** tokens:

- **Source classic PAT**: `repo` (cannot be read-only; keep membership limited to the source repo).
- **Target classic PAT**: `repo`, _(optional)_ `workflow`.
  If your org setup requires it, add `read:org` so `gh` can operate across organisations.

Add the tokens as repository secrets, e.g.:

- **Target repo**: `PAT_TARGET_WRITE`
- **Target repo (or org)** where the workflow runs: `PAT_SOURCE_READ`

> Each remote uses **one** token. The action uses `source_token` for fetch from `core`, and `target_token` for push/PR on the target.
