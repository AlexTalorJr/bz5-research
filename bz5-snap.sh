#!/usr/bin/env bash
# bz5-snap — snapshot tool for the bz5-research repo.
#
# Generates tar.gz of the parts of the repo Claude needs for a session,
# without dragging unrelated history or old raw data through the chat.
#
# Usage (run from anywhere inside the bz5-research clone, or set
# BZ5_RESEARCH_DIR to its path):
#   bz5-snap warm           # default — reference/ + last 3 cycles
#   bz5-snap full           # everything except .git
#   bz5-snap cycle NNN      # one specific cycle directory
#   bz5-snap cycles N M     # range of cycles inclusive (e.g. 5 12)
#   bz5-snap reference      # just reference/ docs
#
# Output: /tmp/bz5-snap-{warm,full,cycle-NNN,...}.tar.gz
# Drag-drop that file into the Claude chat.

set -euo pipefail

REPO="${BZ5_RESEARCH_DIR:-$PWD}"
if [ ! -d "$REPO/.git" ] || [ ! -d "$REPO/cycles" ]; then
  # Try parent dirs in case we're inside a subdir
  while [ "$REPO" != "/" ] && [ ! -d "$REPO/.git" ]; do
    REPO="$(dirname "$REPO")"
  done
fi
if [ ! -d "$REPO/.git" ]; then
  echo "error: not inside a bz5-research clone, and BZ5_RESEARCH_DIR not set" >&2
  exit 1
fi
cd "$REPO"

# Sync with remote so the snapshot reflects what Friend 2 has pushed.
echo "→ git pull --ff-only"
git pull --ff-only >&2 || {
  echo "warning: pull failed; using local state" >&2
}

cmd="${1:-warm}"
shift || true

case "$cmd" in
  warm)
    # Reference docs + the 3 most recent cycles. Anything older is
    # assumed to be summarised in reference/ already.
    OUT="/tmp/bz5-snap-warm.tar.gz"
    paths=(reference cycles/_template)
    # Pick 3 newest cycle dirs by name (zero-padded ⇒ lexical = numeric).
    while IFS= read -r d; do
      paths+=("cycles/$d")
    done < <(ls -1 cycles/ 2>/dev/null | grep -E '^[0-9]{3}-' | sort -r | head -3)
    ;;
  full)
    OUT="/tmp/bz5-snap-full.tar.gz"
    paths=(reference cycles README.md)
    ;;
  cycle)
    n="${1:?cycle number required}"
    nnn=$(printf "%03d" "$n")
    OUT="/tmp/bz5-snap-cycle-$nnn.tar.gz"
    match=$(ls -1d "cycles/$nnn-"* 2>/dev/null | head -1)
    if [ -z "$match" ]; then
      echo "error: no cycle matching cycles/$nnn-*" >&2
      exit 1
    fi
    paths=("$match")
    ;;
  cycles)
    from="${1:?from cycle number required}"
    to="${2:?to cycle number required}"
    OUT="/tmp/bz5-snap-cycles-$(printf %03d $from)-$(printf %03d $to).tar.gz"
    paths=()
    for n in $(seq "$from" "$to"); do
      nnn=$(printf "%03d" "$n")
      match=$(ls -1d "cycles/$nnn-"* 2>/dev/null | head -1)
      [ -n "$match" ] && paths+=("$match")
    done
    if [ ${#paths[@]} -eq 0 ]; then
      echo "error: no cycles in range $from-$to" >&2
      exit 1
    fi
    ;;
  reference)
    OUT="/tmp/bz5-snap-reference.tar.gz"
    paths=(reference)
    ;;
  *)
    echo "usage: bz5-snap [warm|full|reference|cycle N|cycles N M]" >&2
    exit 2
    ;;
esac

echo "→ packing: ${paths[*]}" >&2
tar czf "$OUT" "${paths[@]}"
size=$(du -h "$OUT" | cut -f1)
echo "✓ $OUT ($size)"
echo "  drag this file into the Claude chat"
