#!/usr/bin/env bash
# Build and verify the replacement before moving any existing destination.
set -uo pipefail
SRC="${1:?source required}"
LINK="${2:?link required}"
[ -d "$SRC" ] || { echo "SOURCE DOES NOT EXIST: $SRC" >&2; exit 1; }
SRC="$(cd -- "$SRC" && pwd -P)" || exit 1
mkdir -p "$(dirname -- "$LINK")" || exit 1
if [ -L "$LINK" ] && [ -d "$LINK/" ] &&
  [ "$(cd -- "$LINK/" && pwd -P)" = "$SRC" ]; then
  echo "already linked $LINK"
  exit 0
fi
BACKUP="$LINK.local.bak"
if [ ! -L "$LINK" ] && [ -e "$LINK" ]; then
  [ ! -e "$BACKUP" ] && [ ! -L "$BACKUP" ] || { echo "BACKUP EXISTS: $BACKUP" >&2; exit 1; }
fi
STAGE="$(mktemp -d "${LINK}.stage.XXXXXX")" || exit 1
HAD_OLD=0
INSTALLED=0
rollback() {
  local rc=$?
  trap - EXIT
  if [ "$HAD_OLD" = 1 ] && [ "$INSTALLED" = 0 ] &&
    [ ! -e "$LINK" ] && [ ! -L "$LINK" ] && [ -e "$BACKUP" ]; then
    mv -- "$BACKUP" "$LINK" || { echo "ROLLBACK FAILED: original remains at $BACKUP" >&2; exit 1; }
  fi
  rm -rf -- "$STAGE"
  exit "$rc"
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ln -s -- "$SRC" "$STAGE/link" || { echo "LINK FAILED" >&2; exit 1; }
[ -L "$STAGE/link" ] && [ -d "$STAGE/link/" ] &&
  [ "$(cd -- "$STAGE/link/" && pwd -P)" = "$SRC" ] || { echo "LINK VERIFICATION FAILED" >&2; exit 1; }
if [ ! -L "$LINK" ] && [ -e "$LINK" ]; then
  # The trap is active before the move; detect even a signal just after mv.
  HAD_OLD=1
  mv -- "$LINK" "$BACKUP" || { HAD_OLD=0; exit 1; }
fi
python3 - "$STAGE/link" "$LINK" <<'PY' || exit 1
import os, sys
os.replace(sys.argv[1], sys.argv[2])
PY
INSTALLED=1
echo "linked $LINK"
