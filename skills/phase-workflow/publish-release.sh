#!/usr/bin/env bash
# publish-release.sh — tag an approved merge and delete its branch, or refuse.
#
# Implements the guarded parts of phase-workflow §4. These are the destructive
# operations in this workflow and they were specified only in prose, which is
# how review pass 8 found two defects in the guards themselves: the remote was
# re-read at the moment of comparison, and only git's fetch URL was checked
# while pushes can go to a different one.
#
# Usage:
#   publish-release.sh <approved-sha> <tag> <branch> <origin-fetch-url> <origin-push-url>
#
# Every destination recorded at the gate is passed in. Nothing is re-derived
# here, because a guard that reads the value it is checking guards nothing.
#
# Exit 0  tag published and branch deleted
# Exit 1  refused; nothing was published or deleted

set -uo pipefail

APPROVED="${1:?usage: publish-release.sh <approved-sha> <tag> <branch> <fetch-url> <push-url>}"
TAG="${2:?missing tag}"
BRANCH="${3:?missing branch}"
WANT_FETCH="${4:?missing recorded fetch url}"
WANT_PUSH="${5:?missing recorded push url}"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "NOT A GIT REPOSITORY"; exit 1; }

# The remote must still be the one that was approved — both URLs. Git keeps them
# separately, so a remote can fetch from the approved repository and push to a
# fork, which would satisfy every SHA check and then receive the tag.
have_fetch="$(git remote get-url origin 2>/dev/null || true)"
have_push="$(git remote get-url --push origin 2>/dev/null || true)"
[ "$have_fetch" = "$WANT_FETCH" ] \
  || { echo "ORIGIN FETCH URL CHANGED SINCE THE GATE — refusing"; exit 1; }
[ "$have_push" = "$WANT_PUSH" ] \
  || { echo "ORIGIN PUSH URL CHANGED SINCE THE GATE — refusing"; exit 1; }

# More than one push destination means the check above covers only the first.
if [ "$(git remote get-url --push --all origin 2>/dev/null | wc -l | tr -d ' ')" -gt 1 ]; then
  echo "ORIGIN HAS MULTIPLE PUSH URLS — refusing; a tag would go to all of them"
  exit 1
fi

git rev-parse --verify "$APPROVED^{commit}" >/dev/null 2>&1 \
  || { echo "APPROVED SHA IS NOT A COMMIT: $APPROVED"; exit 1; }

[ "$BRANCH" != "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo)" ] \
  || { echo "REFUSING TO DELETE THE CHECKED-OUT BRANCH"; exit 1; }

for protected in main master; do
  [ "$BRANCH" = "$protected" ] && { echo "REFUSE DEFAULT BRANCH DELETION"; exit 1; }
done

# An existing tag is accepted only when it already points at the approved commit.
if existing="$(git rev-parse --verify --quiet "refs/tags/$TAG^{commit}")"; then
  [ "$existing" = "$(git rev-parse "$APPROVED^{commit}")" ] \
    || { echo "TAG $TAG EXISTS AND POINTS ELSEWHERE — refusing to move it"; exit 1; }
else
  git tag "$TAG" "$APPROVED" || { echo "TAG CREATE FAILED"; exit 1; }
fi

# The branch is deleted only if it still points at what was approved.
head_now="$(git rev-parse --verify --quiet "refs/heads/$BRANCH" || true)"
if [ -n "$head_now" ]; then
  [ "$head_now" = "$(git rev-parse "$APPROVED^{commit}")" ] \
    || { echo "BRANCH ADVANCED SINCE APPROVAL — retaining it"; exit 1; }
  git branch -d "$BRANCH" >/dev/null 2>&1 \
    || { echo "BRANCH HOLDS UNMERGED WORK — retaining it"; exit 1; }
fi

echo "published $TAG at $APPROVED; branch $BRANCH removed"
exit 0
