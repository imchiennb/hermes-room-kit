#!/usr/bin/env bash
# room-cleanup.sh — inventory (and optionally reclaim) the git worktrees a room leaves behind.
#
# Every peer gets its own worktree under ~/.paseo/worktrees/<id>/<slug>, and every run
# leaves those worktrees + their branches behind. This lists them with the facts that
# decide whether they can go, and removes only the ones that are provably safe.
#
#   bash scripts/room-cleanup.sh --repo /path/to/repo              # list only (default)
#   bash scripts/room-cleanup.sh --repo /path/to/repo --apply       # remove the SAFE ones
#
# SAFE-TO-REMOVE = lives under $PASEO_HOME/worktrees, has a CLEAN working tree, and its
# branch is already merged into the repo's base branch. Everything else is listed and left
# alone — this script never guesses.
#
# Never run --apply while a room run is active: an agent whose cwd is that worktree breaks
# when it disappears. Check that the Paseo agents are idle first.
set -uo pipefail

PASEO_HOME="${PASEO_HOME:-$HOME/.paseo}"
REPO=""
BASE=""
APPLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)        REPO="$2"; shift 2 ;;
    --base)        BASE="$2"; shift 2 ;;
    --paseo-home)  PASEO_HOME="$2"; shift 2 ;;
    --apply)       APPLY=1; shift ;;
    -h|--help)     sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$REPO" ] || { echo "error: --repo is required" >&2; exit 2; }
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "error: no such repo" >&2; exit 1; }
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "error: $REPO is not a git repo" >&2; exit 1; }

if [ -z "$BASE" ]; then
  for cand in develop main master; do
    if git -C "$REPO" show-ref --verify --quiet "refs/heads/$cand"; then BASE="$cand"; break; fi
  done
fi
[ -n "$BASE" ] || { echo "error: cannot detect a base branch — pass --base <branch>" >&2; exit 1; }

printf 'repo: %s\nbase: %s\npaseo worktrees under: %s\n\n' "$REPO" "$BASE" "$PASEO_HOME/worktrees"
printf '%-50s %-20s %6s %6s %7s  %s\n' "WORKTREE" "BRANCH" "DIRTY" "AHEAD" "MERGED" "VERDICT"

safe_paths=(); safe_branches=(); n_safe=0; n_keep=0
while IFS= read -r line; do
  case "$line" in
    "worktree "*) wt="${line#worktree }" ;;
    "branch refs/heads/"*)
      branch="${line#branch refs/heads/}"
      case "$wt" in
        "$PASEO_HOME"/worktrees/*) ;;
        *)
          printf '%-50s %-20s %6s %6s %7s  %s\n' "${wt/#$HOME/~}" "$branch" "-" "-" "-" "SKIP (not a Paseo worktree)"
          continue ;;
      esac
      dirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l)
      ahead=$(git -C "$REPO" rev-list --count "$BASE..$branch" 2>/dev/null || echo "?")
      if git -C "$REPO" branch --merged "$BASE" --format='%(refname:short)' 2>/dev/null | grep -Fxq "$branch"; then
        merged=yes
      else
        merged=no
      fi
      if [ "$dirty" = 0 ] && [ "$merged" = yes ]; then
        verdict="SAFE-TO-REMOVE"; n_safe=$((n_safe+1)); safe_paths+=("$wt"); safe_branches+=("$branch")
      else
        verdict="KEEP (dirty=$dirty merged=$merged)"; n_keep=$((n_keep+1))
      fi
      printf '%-50s %-20s %6s %6s %7s  %s\n' "${wt/#$HOME/~}" "$branch" "$dirty" "$ahead" "$merged" "$verdict"
      ;;
  esac
done < <(git -C "$REPO" worktree list --porcelain)

printf '\nsafe-to-remove: %d | keep: %d\n' "$n_safe" "$n_keep"

if [ "$APPLY" = 0 ]; then
  [ "$n_safe" -gt 0 ] && printf 'dry-run: nothing removed (re-run with --apply while the room is idle)\n'
  exit 0
fi

printf '\n[apply] removing %d worktree(s) + branch(es) — the room must be idle\n' "$n_safe"
i=0
while [ "$i" -lt "${#safe_paths[@]}" ]; do
  wt="${safe_paths[$i]}"; br="${safe_branches[$i]}"; i=$((i+1))
  if git -C "$REPO" worktree remove --force "$wt" 2>&1; then
    printf '  removed worktree %s\n' "${wt/#$HOME/~}"
  else
    printf '  FAILED to remove %s\n' "$wt"; continue
  fi
  if [ -n "$br" ] && [ "$br" != "$BASE" ]; then
    git -C "$REPO" branch -d "$br" 2>&1 | sed 's/^/  /'
  fi
done
git -C "$REPO" worktree prune
printf '  pruned stale worktree metadata\n'
