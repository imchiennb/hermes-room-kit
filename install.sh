#!/usr/bin/env bash
# install.sh — put this Hermes room onto a machine (fresh box or an existing
# Hermes install). Idempotent: run it twice and nothing is duplicated.
#
#   bash install.sh                 # real install into ~/.hermes/profiles + ~/.paseo
#   bash install.sh --dry-run       # show what would change, write nothing
#   bash install.sh --root DIR --paseo-home DIR   # test/alternative roots
#
# It installs: 3 profile configs + role contracts (AGENTS.md), the shared room
# contract, the 3 room skills, an .env template, and the Paseo provider/agent
# profiles (merged, never wholesale). It never copies secrets or runtime state.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_PROFILES_DIR="${HERMES_PROFILES_DIR:-$HOME/.hermes/profiles}"
PASEO_HOME="${PASEO_HOME:-$HOME/.paseo}"
DEFAULT_ROOT="$HOME/.hermes/profiles"
FORCE=0
DRY=0
SKIP_PASEO=0
NO_RELOAD=0
STAMP="$(date +%Y%m%d-%H%M%S)"

while [ $# -gt 0 ]; do
  case "$1" in
    --root)        HERMES_PROFILES_DIR="$2"; shift 2 ;;
    --paseo-home)  PASEO_HOME="$2"; shift 2 ;;
    --force)       FORCE=1; shift ;;
    --dry-run)     DRY=1; shift ;;
    --skip-paseo)  SKIP_PASEO=1; shift ;;
    --no-reload)   NO_RELOAD=1; shift ;;
    -h|--help)     sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }
step() { printf '\n== %s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '   [dry-run] %s\n' "$*"; else "$@"; fi; }
# copy_with_backup <src> <dst>; always backs up an existing, differing dst
copy_with_backup() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    run cp -p "$dst" "$dst.bak-$STAMP"
    say "   backup: ${dst#$HOME/}.bak-$STAMP"
  fi
  run mkdir -p "$(dirname "$dst")"
  run cp -p "$src" "$dst"
  say "   ${dst#$HOME/}"
}

step "preflight"
python3 --version >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }
say "   python3: $(python3 --version 2>&1)"
if command -v hermes >/dev/null 2>&1; then
  say "   hermes:  $(command -v hermes) ($(hermes --version 2>/dev/null | head -1))"
else
  warn "no 'hermes' on PATH — the room's ACP seats cannot start until Hermes is installed"
fi
if [ -f "$PASEO_HOME/config.json" ]; then
  say "   paseo:   $PASEO_HOME/config.json (existing, will be merged)"
else
  warn "no Paseo config at $PASEO_HOME/config.json — install Paseo Desktop first if you want the UI"
fi

step "Hermes profiles"
for seat in supervisor lead peer; do
  dir="$HERMES_PROFILES_DIR/$seat"
  if [ ! -d "$dir" ]; then
    if [ "$HERMES_PROFILES_DIR" = "$DEFAULT_ROOT" ] && command -v hermes >/dev/null 2>&1; then
      run hermes profile create "$seat" --no-alias
    else
      run mkdir -p "$dir"
    fi
    say "   created profile '$seat'"
  fi
  copy_with_backup "$KIT_DIR/profiles/$seat/config.yaml" "$dir/config.yaml"
  copy_with_backup "$KIT_DIR/profiles/$seat/AGENTS.md"  "$dir/AGENTS.md"
done

step "Shared room contract"
for f in WORKFLOW.md PROMPT_TEMPLATES.md; do
  copy_with_backup "$KIT_DIR/profiles/shared/$f" "$HERMES_PROFILES_DIR/$f"
done

step "Room skills"
for seat in supervisor lead peer; do
  src_root="$KIT_DIR/skills/$seat"
  [ -d "$src_root" ] || continue
  for skill_dir in "$src_root"/*/*/; do
    [ -f "${skill_dir}SKILL.md" ] || continue
    category="$(basename "$(dirname "${skill_dir%/}")")"
    name="$(basename "${skill_dir%/}")"
    dst="$HERMES_PROFILES_DIR/$seat/skills/$category/$name"
    if [ -d "$dst" ]; then
      if diff -rq "$skill_dir" "$dst" >/dev/null 2>&1; then
        say "   $seat/$name — already current"
        continue
      fi
      run mv "$dst" "$dst.bak-$STAMP"
      say "   backup: ${dst#$HOME/}.bak-$STAMP"
    fi
    run mkdir -p "$(dirname "$dst")"
    run cp -r "$skill_dir" "$dst"
    say "   ${dst#$HOME/}"
  done
done

step "Credentials template"
for seat in supervisor lead peer; do
  env_file="$HERMES_PROFILES_DIR/$seat/.env"
  if [ -f "$env_file" ]; then
    if grep -qE '^SWICLOUD_API_KEY=.+' "$env_file"; then
      say "   $seat/.env — key present, left untouched"
    else
      warn "$seat/.env exists but SWICLOUD_API_KEY looks empty — fill it in (never commit it)"
    fi
  else
    run mkdir -p "$HERMES_PROFILES_DIR/$seat"
    if [ "$DRY" = 1 ]; then
      say "   [dry-run] would write $seat/.env template"
    else
      cat > "$env_file" <<'EOF'
# Credential for the provider configured in this profile's config.yaml.
# Each profile has its own secret scope: keys in ~/.hermes/.env are NOT inherited.
SWICLOUD_API_KEY=
EOF
      chmod 600 "$env_file"
      say "   ${env_file#$HOME/} template written (fill in the key)"
    fi
  fi
done

if [ "$SKIP_PASEO" = 0 ]; then
  step "Paseo config (merged, not replaced)"
  if [ -d "$PASEO_HOME" ] || [ -f "$PASEO_HOME/config.json" ]; then
    merge_args=(--fragment "$KIT_DIR/paseo/room.fragment.json" --config "$PASEO_HOME/config.json")
    [ "$FORCE" = 1 ] && merge_args+=(--force)
    [ "$DRY" = 1 ] && merge_args+=(--dry-run)
    python3 "$KIT_DIR/scripts/merge_paseo_config.py" "${merge_args[@]}"
  else
    warn "skipped — Paseo home not found at $PASEO_HOME"
  fi
fi

if [ "$NO_RELOAD" = 0 ] && [ "$DRY" = 0 ]; then
  step "Apply config to the running daemon"
  if curl -sf -m 3 http://127.0.0.1:6767/api/health >/dev/null 2>&1; then
    if command -v paseo >/dev/null 2>&1; then
      paseo daemon reload --host 127.0.0.1:6767 || warn "paseo daemon reload failed — restart Paseo Desktop instead"
    else
      warn "Paseo daemon is running but no 'paseo' CLI: quit and reopen Paseo Desktop (do it while no agent is running — a restart kills running agents)"
    fi
  else
    say "   daemon not running — config applies on next start"
  fi
fi

step "Next"
say "   1. fill SWICLOUD_API_KEY in each ~/.hermes/profiles/<seat>/.env"
say "   2. bash verify.sh"
say "   3. open Paseo Desktop → profiles Supervisor / Lead / Peer should be listed"
