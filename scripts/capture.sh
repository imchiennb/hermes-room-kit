#!/usr/bin/env bash
# capture.sh — snapshot the LIVE room into this kit.
#
# Run this on a machine where the room already works (the box you copy FROM).
# It copies the portable parts and extracts the Paseo fragment:
#   * per-seat profile config.yaml + AGENTS.md (role contract)
#   * the shared room contract (WORKFLOW.md, PROMPT_TEMPLATES.md)
#   * the three room skills (supervisor / lead / peer)
#   * the Paseo provider + agent-profile fragment
#
# NEVER copied: .env (secrets), state.db, sessions, memories, caches, logs, worktrees.
#
# Usage:  scripts/capture.sh [--profiles-dir DIR] [--paseo-home DIR]
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES_PROFILES_DIR="${HERMES_PROFILES_DIR:-$HOME/.hermes/profiles}"
PASEO_HOME="${PASEO_HOME:-$HOME/.paseo}"

while [ $# -gt 0 ]; do
  case "$1" in
    --profiles-dir) HERMES_PROFILES_DIR="$2"; shift 2 ;;
    --paseo-home)   PASEO_HOME="$2"; shift 2 ;;
    -h|--help)      sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

SEATS=(supervisor lead peer)
# seat:skill-name:category
SKILLS=(
  "supervisor:paseo-room-supervisor:autonomous-ai-agents"
  "lead:paseo-lead-orchestration:autonomous-ai-agents"
  "peer:scoped-change-briefs:software-development"
)

[ -d "$HERMES_PROFILES_DIR" ] || { echo "error: no Hermes profiles dir at $HERMES_PROFILES_DIR" >&2; exit 1; }

copied=0
for seat in "${SEATS[@]}"; do
  src="$HERMES_PROFILES_DIR/$seat"
  if [ ! -d "$src" ]; then
    echo "warn: profile '$seat' not found at $src — skipped"
    continue
  fi
  mkdir -p "$KIT_DIR/profiles/$seat"
  for f in config.yaml AGENTS.md; do
    if [ -f "$src/$f" ]; then
      cp -p "$src/$f" "$KIT_DIR/profiles/$seat/$f"
      copied=$((copied + 1))
      echo "  profile  profiles/$seat/$f"
    else
      echo "warn: $src/$f missing"
    fi
  done
done

mkdir -p "$KIT_DIR/profiles/shared"
for f in WORKFLOW.md PROMPT_TEMPLATES.md; do
  if [ -f "$HERMES_PROFILES_DIR/$f" ]; then
    cp -p "$HERMES_PROFILES_DIR/$f" "$KIT_DIR/profiles/shared/$f"
    copied=$((copied + 1))
    echo "  shared   profiles/shared/$f"
  else
    echo "warn: $HERMES_PROFILES_DIR/$f missing"
  fi
done

for entry in "${SKILLS[@]}"; do
  IFS=: read -r seat name category <<<"$entry"
  src="$HERMES_PROFILES_DIR/$seat/skills/$category/$name"
  if [ ! -d "$src" ]; then
    echo "warn: skill '$name' not found at $src — skipped"
    continue
  fi
  rm -rf "$KIT_DIR/skills/$seat/$category/$name"
  mkdir -p "$KIT_DIR/skills/$seat/$category"
  dst="$KIT_DIR/skills/$seat/$category/$name"
  cp -r "$src" "$dst"
  files=$(find "$dst" -type f | wc -l)
  copied=$((copied + 1))
  echo "  skill    skills/$seat/$category/$name ($files files)"
done

mkdir -p "$KIT_DIR/paseo"
python3 - "$PASEO_HOME/config.json" "$KIT_DIR/paseo/room.fragment.json" <<'PY'
import json, sys, os

src, dst = sys.argv[1], sys.argv[2]
if not os.path.isfile(src):
    print(f"warn: no Paseo config at {src} — fragment not refreshed")
    sys.exit(0)

cfg = json.load(open(src, encoding="utf-8"))
providers = (cfg.get("agents") or {}).get("providers") or {}
profiles = ((cfg.get("daemon") or {}).get("agentProfiles")) or []

room_providers = {k: v for k, v in providers.items() if k.startswith("hermes-")}
room_profiles = [p for p in profiles if str(p.get("provider", "")).startswith("hermes-")]

if not room_providers:
    print("warn: live config has no hermes-* providers — fragment not refreshed")
    sys.exit(0)

fragment = {
    "_comment": "Portable room fragment. install.sh merges ONLY these keys into the target "
                "~/.paseo/config.json; every other provider and daemon setting is preserved.",
    "agents": {"providers": room_providers},
    "daemon": {"agentProfiles": room_profiles},
}
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(fragment, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(f"  paseo    paseo/room.fragment.json ({len(room_providers)} providers, {len(room_profiles)} agent profiles)")
PY

echo
echo "captured $copied item(s) into $KIT_DIR"
