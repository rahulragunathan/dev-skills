#!/usr/bin/env bash
# Install a setup directory link, retaining the previous destination on failure.
set -uo pipefail
SRC="${1:?source required}"
LINK="${2:?link required}"
[ -d "$SRC" ] || { echo "SOURCE DOES NOT EXIST: $SRC"; exit 1; }
SRC="$(cd -- "$SRC" && pwd -P)" || exit 1
mkdir -p "$(dirname -- "$LINK")" || exit 1
if [ -L "$LINK" ] && [ -d "$LINK/" ] &&
  [ "$(cd -- "$LINK/" && pwd -P)" = "$SRC" ]; then
  echo "already linked $LINK"
  exit 0
fi
BACKUP="$LINK.local.bak"
HAD_OLD=0
if [ -e "$LINK" ] || [ -L "$LINK" ]; then
  [ ! -e "$BACKUP" ] && [ ! -L "$BACKUP" ] || { echo "BACKUP EXISTS: $BACKUP"; exit 1; }
  mv -- "$LINK" "$BACKUP" || exit 1
  HAD_OLD=1
fi
rollback() {
  local rc=$?
  trap - EXIT
  rm -f -- "$LINK" || { echo "ROLLBACK FAILED: inspect $LINK and $BACKUP"; exit 1; }
  if [ "$HAD_OLD" = 1 ]; then
    mv -- "$BACKUP" "$LINK" || { echo "ROLLBACK FAILED: original remains at $BACKUP"; exit 1; }
  fi
  exit "$rc"
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ln -s -- "$SRC" "$LINK" || { echo "LINK FAILED"; exit 1; }
[ -L "$LINK" ] && [ -d "$LINK/" ] &&
  [ "$(cd -- "$LINK/" && pwd -P)" = "$SRC" ] || { echo "LINK VERIFICATION FAILED"; exit 1; }
trap - EXIT INT TERM
echo "linked $LINK"
