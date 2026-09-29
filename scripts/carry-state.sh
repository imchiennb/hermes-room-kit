#!/usr/bin/env bash
# carry-state.sh — move the room's *state* (not the room itself) between machines.
#
# The room itself (profiles, role contracts, skills, Paseo providers) comes from
# install.sh. This script adds what only exists on the running box: agent memories,
# cron jobs, hooks, plugins — and optionally session history and .env secrets.
#
#   bash scripts/carry-state.sh capture [--out DIR] [--with-history] [--with-secrets]
#   bash scripts/carry-state.sh restore [--from DIR] [--with-history] [--with-secrets]
#
# Excluded by design: caches, logs, sandboxes, LSP installs, worktrees, models cache.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES_PROFILES_DIR="${HERMES_PROFILES_DIR:-$HOME/.hermes/profiles}"
SEATS=(supervisor lead peer)
STAMP="$(date +%Y%m%d-%H%M%S)"

MODE="${1:-}"; shift || true
OUT="$KIT_DIR/state"
WITH_HISTORY=0
WITH_SECRETS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out|--from)  OUT="$2"; shift 2 ;;
    --with-history) WITH_HISTORY=1; shift ;;
    --with-secrets) WITH_SECRETS=1; shift ;;
    -h|--help)     sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# state dirs carried by default; SOUL.md keeps a customised persona
DEFAULT_PATHS=(memories cron hooks plugins SOUL.md)

snapshot_db() { # seat -> writes a consistent sqlite snapshot to $OUT/<seat>.state.db
  local seat="$1" src="$HERMES_PROFILES_DIR/$seat/state.db" dst="$OUT/$seat.state.db"
  [ -f "$src" ] || return 0
  python3 - "$src" "$dst" <<'PY'
import sqlite3, sys, os
src, dst = sys.argv[1], sys.argv[2]
if os.path.exists(dst):
    os.remove(dst)
con = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
try:
    con.execute("VACUUM INTO ?", (dst,))
finally:
    con.close()
print(f"   snapshot: {dst}")
PY
}

case "$MODE" in
  capture)
    mkdir -p "$OUT"
    for seat in "${SEATS[@]}"; do
      seat_dir="$HERMES_PROFILES_DIR/$seat"
      [ -d "$seat_dir" ] || { echo "warn: profile '$seat' not found — skipped"; continue; }
      members=()
      for p in "${DEFAULT_PATHS[@]}"; do
        [ -e "$seat_dir/$p" ] && members+=("$seat/$p")
      done
      if [ "$WITH_SECRETS" = 1 ] && [ -f "$seat_dir/.env" ]; then
        members+=("$seat/.env")
      fi
      if [ "$WITH_HISTORY" = 1 ]; then
        snapshot_db "$seat"
        if [ -f "$OUT/$seat.state.db" ]; then
          cp -p "$OUT/$seat.state.db" "$seat_dir/.room-state.db"
          members+=("$seat/.room-state.db")
        fi
      fi
      if [ ${#members[@]} -eq 0 ]; then
        echo "warn: nothing to carry for '$seat'"
        continue
      fi
      archive="$OUT/room-state-$seat.tar.gz"
      tar -czf "$archive" -C "$HERMES_PROFILES_DIR" "${members[@]}"
      echo "   $archive ($(du -h "$archive" | cut -f1)) — $(printf '%s ' "${members[@]}")"
    done
    if [ "$WITH_SECRETS" = 0 ]; then
      echo "   note: .env not included (pass --with-secrets, and never commit the result)"
    fi
    ;;

  restore)
    [ -d "$OUT" ] || { echo "error: no state dir at $OUT" >&2; exit 1; }
    for seat in "${SEATS[@]}"; do
      archive="$OUT/room-state-$seat.tar.gz"
      [ -f "$archive" ] || { echo "warn: no archive for '$seat' — skipped"; continue; }
      seat_dir="$HERMES_PROFILES_DIR/$seat"
      mkdir -p "$seat_dir"
      keep=""
      for p in memories cron hooks plugins SOUL.md .env; do
        [ -e "$seat_dir/$p" ] && keep="$keep $p"
      done
      if [ -n "$keep" ]; then
        backup="$seat_dir/.room-state-backup-$STAMP.tar.gz"
        tar -czf "$backup" -C "$HERMES_PROFILES_DIR" $(for p in $keep; do printf '%s ' "$seat/$p"; done)
        echo "   backup: $backup"
      fi
      tmp="$(mktemp -d)"
      tar -xzf "$archive" -C "$tmp"
      if [ -f "$tmp/$seat/.room-state.db" ]; then
        mv "$tmp/$seat/.room-state.db" "$seat_dir/state.db"
        echo "   restored $seat/state.db (session history)"
      fi
      for p in memories cron hooks plugins SOUL.md .env; do
        [ -e "$tmp/$seat/$p" ] || continue
        rm -rf "$seat_dir/$p"
        mv "$tmp/$seat/$p" "$seat_dir/$p"
        [ "$p" = ".env" ] && chmod 600 "$seat_dir/.env"
        echo "   restored $seat/$p"
      done
      rm -rf "$tmp"
    done
    echo "   done — run 'bash verify.sh' next"
    ;;

  *)
    sed -n '2,12p' "$0"; exit 2 ;;
esac
