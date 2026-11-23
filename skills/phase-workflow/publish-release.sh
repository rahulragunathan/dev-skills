#!/usr/bin/env bash
# publish-release.sh — tag an approved merge and delete its branch, or refuse.
#
# Usage:
#   publish-release.sh --check-origin <origin-fetch-url> <origin-push-url>
#   publish-release.sh <approved-sha> <tag> <branch> <origin-fetch-url> <origin-push-url> [--confirmed-on-remote]
#
# Every destination recorded at the gate is passed in. Nothing is re-derived
# here, because a guard that reads the value it is checking guards nothing.
#
# --check-origin exits before any ref changes.
# The full form is a local-only utility; the phase SOP uses --check-origin.
# A manual caller uses --confirmed-on-remote to assert the tip's approval and
# presence on the remote, permitting -D only at the approved tip.
# Actual remote publication and cleanup are in SKILL.md, whose fences are
# executed directly by phase-git.bats. The local utility does not push a tag.
# Exit 0 on completion; exit 1 on refusal or failure.

set -uo pipefail

CHECK_ONLY=0
CONFIRMED_ON_REMOTE=0
if [ "${1:-}" = --check-origin ]; then
  CHECK_ONLY=1
  WANT_FETCH="${2:?missing recorded fetch url}"
  WANT_PUSH="${3:?missing recorded push url}"
else
  APPROVED="${1:?usage: publish-release.sh <approved-sha> <tag> <branch> <fetch-url> <push-url> [--confirmed-on-remote]}"
  TAG="${2:?missing tag}"
  BRANCH="${3:?missing branch}"
  WANT_FETCH="${4:?missing recorded fetch url}"
  WANT_PUSH="${5:?missing recorded push url}"
  shift 5
  case "$#:${1:-}" in
    0:) ;;
    1:--confirmed-on-remote) CONFIRMED_ON_REMOTE=1 ;;
    *) echo "UNKNOWN ARGUMENTS — expected only optional --confirmed-on-remote"; exit 1 ;;
  esac
fi

git rev-parse --git-dir >/dev/null 2>&1 || { echo "NOT A GIT REPOSITORY"; exit 1; }

# The origin URLs are copied into the committed phase record and the review
# bundle, so only the forms a phase needs are accepted, and a credential in one
# is refused without being printed. Shell patterns decide, not an external
# command, so a tool that cannot run cannot make a URL pass.

# kind <url>: url, scp, path or refused.
kind() {
  case "$1" in
    ''|-*|//*|*[[:space:]]*|*::*) echo refused ;;
    # Lower case only: git picks its built-in transports by exact prefix, and hands
    # any other spelling to a remote helper.
    ssh://?*|git+ssh://?*|ssh+git://?*|https://?*) echo url ;;
    *://*) echo refused ;;
    /*) echo path ;;
    *:*)
      # scp form: [user@]host:path, with no slash before the first colon.
      case "${1%%:*}" in ''|*/*|*@|@*) echo refused ;; *) echo scp ;; esac ;;
    *) echo refused ;;
  esac
}

# has_credentials <url> <kind>: a password, token or query in an accepted form.
# A bare user is allowed over ssh (ssh://git@host) and in the scp form.
has_credentials() {
  case "$2:$1" in url:*'?'*|url:*'#'*|scp:*'?'*|scp:*'#'*) return 0 ;; esac
  case "$2" in
    url)
      local rest="${1#*://}"
      local authority="${rest%%/*}"
      # git decodes %-escapes in an ssh authority before parsing it, so none may hide a part.
      case "$authority" in *%*) return 0 ;; esac
      case "$authority" in
        *@*)
          local user="${authority%@*}"
          # git decodes %-escapes before it splits the user part, so refuse them outright.
          case "$user" in *:*|*%*) return 0 ;; esac
          case "$1" in https://*) return 0 ;; esac ;;
      esac ;;
    scp)
      local user_host="${1%%:*}" path="${1#*:}"
      case "$user_host" in *@*@*) return 0 ;; esac
      case "${path%%/*}" in *@*) return 0 ;; esac ;;
  esac
  return 1
}

for url in "$WANT_FETCH" "$WANT_PUSH"; do
  url_kind="$(kind "$url")"
  if [ "$url_kind" = refused ]; then
    echo "UNSUPPORTED ORIGIN URL — refusing; use an ssh, https or scp-style remote or a local path, and do not record the URL"
    exit 1
  fi
  if has_credentials "$url" "$url_kind"; then
    echo "CREDENTIALS IN ORIGIN URL — refusing; use SSH or a credential helper, and do not record the URL"
    exit 1
  fi
done

# The remote must still be the one that was approved — both URLs. Git keeps them
# separately, so a remote can fetch from the approved repository and push to a
# fork, which would satisfy every SHA check and then receive the tag.
have_fetch="$(git remote get-url origin 2>/dev/null || true)"
have_push="$(git remote get-url --push origin 2>/dev/null || true)"
[ "$have_fetch" = "$WANT_FETCH" ] \
  || { echo "ORIGIN FETCH URL CHANGED SINCE THE GATE — refusing"; exit 1; }
[ "$have_push" = "$WANT_PUSH" ] \
  || { echo "ORIGIN PUSH URL CHANGED SINCE THE GATE — refusing"; exit 1; }

# More than one push destination means the check above covers only the first,
# and a listing that fails proves nothing. The whole listing must be the one URL.
# The trailing x keeps the listing's final newlines, which command substitution would strip.
all_push="$(git remote get-url --push --all origin 2>/dev/null && printf x)" \
  || { echo "CANNOT LIST THE ORIGIN PUSH URLS — refusing"; exit 1; }
if [ "$all_push" != "$WANT_PUSH
x" ]; then
  echo "ORIGIN HAS MULTIPLE PUSH URLS — refusing; a tag would go to all of them"
  exit 1
fi
# A configured helper replaces the transport the URL names.
# Present at all, even empty, it selects a helper; only git's "absent" status (1) passes.
vcs_rc=0; git config --get remote.origin.vcs >/dev/null 2>&1 || vcs_rc=$?
if [ "$vcs_rc" -ne 1 ]; then
  echo "remote.origin.vcs IS SET — refusing; it hands origin to a remote helper"
  exit 1
fi

[ "$CHECK_ONLY" = 1 ] && exit 0

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
  # The caller explicitly confirms this approved tip was present on the remote.
  # It contains no unpushed commits; the positional APPROVED alone is not proof.
  if [ "$CONFIRMED_ON_REMOTE" = 1 ]; then
    git branch -D "$BRANCH" >/dev/null 2>&1 \
      || { echo "RETAINED — branch deletion failed; inspect it by hand"; exit 1; }
  elif git branch -d "$BRANCH" >/dev/null 2>&1; then
    :
  else
    # A -d refusal can also mean a squash merge; it does not prove missing work.
    echo "RETAINED — approval was not confirmed for $BRANCH at tip $head_now; -d refused, so -D was not attempted."
    echo "Missing --confirmed-on-remote; pass it only after confirming this tip's approval and presence on the remote."
    exit 1
  fi
fi

echo "published $TAG at $APPROVED; branch $BRANCH removed"
exit 0
