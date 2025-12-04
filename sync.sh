#!/usr/bin/env bash

set -euo pipefail
set -x
echo "::group:: preparation"

# Mask tokens in logs
echo "::add-mask::${SOURCE_TOKEN}"
echo "::add-mask::${TARGET_TOKEN}"

# Default: assume we WON'T push a PR branch
# so later steps will not try to create a PR unless we explicitly set this to true
{
  echo "PR_BRANCH_PUSHED=false"
  echo "PR_BRANCH="
} >> "$GITHUB_ENV"

git config --global user.name 'MeblabsBot'
git config --global user.email 'github@meblabs.com'

git config --local --unset-all http.https://github.com/.extraheader || true

if git remote | grep -q '^core$'; then
  git remote set-url core "https://x-access-token:${SOURCE_TOKEN}@github.com/${SOURCE_REPO}.git"
else
  git remote add core "https://x-access-token:${SOURCE_TOKEN}@github.com/${SOURCE_REPO}.git"
fi
git remote -v

git fetch core "${SOURCE_BRANCH}"

# Create working branch from target
git checkout -B "${PR_BRANCH}" "origin/${TARGET_BRANCH}"

echo "::endgroup::"
echo "::group:: calculating missing commits"

# git cherry shows from oldest → newest.
# We read in reverse (tac) to start from the newest and
# collect the "+" until we encounter the first "-" (already present in the target).
MISSING=$(git cherry -v "${TARGET_BRANCH}" "core/${SOURCE_BRANCH}" \
          | tac \
          | awk '$1=="-" {exit} $1=="+" {print $2}' \
          | tac || true)

if [[ -z "${MISSING}" ]]; then
  echo "No commits to synchronize."
  # PR_BRANCH_PUSHED is already false
  echo "::endgroup::"
  exit 0
fi

echo "Commits to cherry-pick:"
echo "${MISSING}"
echo "::endgroup::"

echo "::group:: cherry-pick"
trap 'echo "::error::Sync script failed at line $LINENO"; exit 1' ERR

APPLIED_NONEMPTY=false

for sha in ${MISSING}; do
  echo "Cherry-pick ${sha}"

  # Try cherry-pick and handle empty / conflict cases
  if ! git cherry-pick -x "${sha}"; then
    # If both working tree and index are clean, this is most likely an empty cherry-pick
    if git diff --quiet && git diff --cached --quiet; then
      echo "Commit ${sha} is already effectively applied on target branch, skipping it"
      # Skip this cherry-pick and continue with the next one
      git cherry-pick --skip || true
      continue
    fi

    # Otherwise we have real conflicts or partial changes: abort and fail
    echo "::error::Cherry-pick ${sha} failed with conflicts, aborting sync"
    git cherry-pick --abort || true
    exit 1
  fi

  # If cherry-pick succeeded, a new non-empty commit was created
  APPLIED_NONEMPTY=true
done
echo "::endgroup::"

# If all cherry-picks were empty, do NOT push a branch and do NOT create a PR
if [[ "${APPLIED_NONEMPTY}" != "true" ]]; then
  echo "::group:: no effective changes"
  echo "All missing commits were empty on the target branch. Nothing to push."
  echo "::endgroup::"
  exit 0
fi

echo "::group:: push & flag PR"
git config --local --unset-all http.https://github.com/.extraheader || true
git remote set-url origin "https://x-access-token:${TARGET_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git push --force-with-lease -u origin "${PR_BRANCH}"

{
  echo "PR_BRANCH_PUSHED=true"
  echo "PR_BRANCH=${PR_BRANCH}"
} >> "$GITHUB_ENV"

echo "::endgroup::"
