#!/usr/bin/env bash

set -euo pipefail
set -x
echo "::group:: preparation"

# Maschera i token nei log
echo "::add-mask::${SOURCE_TOKEN}"
echo "::add-mask::${TARGET_TOKEN}"

echo "::group:: preparation"
git config --global user.name 'MeblabsBot'
git config --global user.email 'github@meblabs.com'

if git remote | grep -q '^core$'; then
  git remote set-url core "https://x-access-token:${SOURCE_TOKEN}@github.com/${SOURCE_REPO}.git"
else
  git remote add core "https://x-access-token:${SOURCE_TOKEN}@github.com/${SOURCE_REPO}.git"
fi
git fetch core "${SOURCE_BRANCH}"

# Create working branch
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
  echo "PR_BRANCH_PUSHED=false" >> "$GITHUB_ENV"
  exit 0
fi

# Reverse to apply cherry‑picks from oldest → newest
echo "Commits to cherry-pick:"
echo "${MISSING}"
echo "::endgroup::"

echo "::group:: cherry-pick"
trap 'echo "::error::Sync script failed at line $LINENO"; exit 1' ERR
for sha in ${MISSING}; do
  echo "Cherry-pick ${sha}"
  git cherry-pick -x "${sha}"
done
echo "::endgroup::"

echo "::group:: push & flag PR"
git remote set-url origin "https://x-access-token:${TARGET_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git push --force-with-lease -u origin "${PR_BRANCH}"

{
  echo "PR_BRANCH_PUSHED=true"
  echo "PR_BRANCH=${PR_BRANCH}"
} >> "$GITHUB_ENV"

echo "::endgroup::"
