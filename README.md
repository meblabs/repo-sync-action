# repo-sync-action

Composit GitHub Action to sync repos commits

Automated **commit‑level sync** between a “core” repository and one or more
installation/target repositories.

`repo‑sync‑action` cherry‑picks _only_ the new commits that are missing in the target branch **after** the most recent commit already present. Commits from the core repository that were previously skipped or not included will **not** be synchronized retroactively. 

This approach preserves the original Conventional Commit messages—ideal for projects using **semantic‑release** or similar tools.

## How it works

1. **Fetch `core/<source_branch>`** and create a temporary branch
   `<pr_branch>-<short‑sha>` on the target repo  
   (default: `sync/core‑<7‑digit workflow sha>`).

2. **Detect missing commits**

   ```bash
   git cherry -v <target_branch> core/<source_branch>
   ```

   The script scans the list in reverse and collects every "`+`" commit until it
   reaches the first "`-`" (a patch that already exists on the target).

3. **Cherry‑pick** those commits (oldest → newest).  
   Conflicts, if any, fail the run so you can resolve them manually.

4. **Push the branch** and **open a Pull Request** via
   [`peter‑evans/create‑pull‑request`](https://github.com/peter-evans/create-pull-request).

The result is a clean, linear history containing **only** the new commits from
the core repository.

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `source_repo` | **Yes** | | `owner/repo` of the core repository. |
| `source_branch` | No | `dev` | Branch to sync _from_ in the core repo. |
| `target_branch` | No | `dev` | Branch to sync _to_ in the target repo. |
| `token` | **Yes** | | Personal Access Token with `repo`, `read:org` (and `workflow` if you sync workflow files). |
| `pr_branch` | No | `sync/core` | Prefix for the temporary branch. The action appends `‑<short‑sha>`. |
| `pr_title` | No | `Sync from Core` | Title of the Pull Request (the short SHA is appended automatically). |
| `pr_labels` | No | `sync-core` | Comma‑separated list of labels to apply to the PR. |

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
          token: ${{ secrets.MEBBOT }} # PAT saved in repo secrets
```

## PAT scopes

| Scope | Why |
|-------|-----|
| `repo` | Push branch & create PR in **private** repos. |
| `read:org` | Required by GitHub CLI to authenticate across organisations. |
| `workflow` | _(optional)_ needed **only** if the cherry‑picked commits modify files in `.github/workflows`. |

Add the token to every target repository as `MEBBOT` (or another name) under
**Settings → Secrets and variables → Actions**.
