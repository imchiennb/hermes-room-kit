#!/usr/bin/env bash
# verify.sh — check that the room is actually installed on THIS machine.
# Reads the live files; never prints secrets. Exit code 1 if anything FAILs.
#
#   bash verify.sh [--root DIR] [--paseo-home DIR]
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_PROFILES_DIR="${HERMES_PROFILES_DIR:-$HOME/.hermes/profiles}"
PASEO_HOME="${PASEO_HOME:-$HOME/.paseo}"
DAEMON_URL="${DAEMON_URL:-http://127.0.0.1:6767}"

while [ $# -gt 0 ]; do
  case "$1" in
    --root)        HERMES_PROFILES_DIR="$2"; shift 2 ;;
    --paseo-home)  PASEO_HOME="$2"; shift 2 ;;
    -h|--help)     sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

pass=0; fail=0; warn_n=0
ok()   { printf '  PASS  %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$*"; fail=$((fail+1)); }
warn() { printf '  warn  %s\n' "$*"; warn_n=$((warn_n+1)); }
head_() { printf '\n%s\n' "$*"; }

head_ "Runtime"
if command -v hermes >/dev/null 2>&1; then
  ok "hermes on PATH ($(hermes --version 2>/dev/null | head -1))"
  if [ "$HERMES_PROFILES_DIR" = "$HOME/.hermes/profiles" ]; then
    listed="$(hermes profile list 2>/dev/null)"
    for seat in supervisor lead peer; do
      if printf '%s' "$listed" | grep -qw "$seat"; then
        ok "hermes itself lists profile '$seat'"
      else
        bad "hermes does not list profile '$seat' (files on disk are not enough)"
      fi
    done
  else
    warn "custom --root given: skipped 'hermes profile list' (it only reads the default root)"
  fi
else
  bad "hermes not on PATH — ACP seats cannot start"
fi

head_ "Profiles"
for seat in supervisor lead peer; do
  cfg="$HERMES_PROFILES_DIR/$seat/config.yaml"
  agents="$HERMES_PROFILES_DIR/$seat/AGENTS.md"
  [ -f "$cfg" ]    && ok "$seat/config.yaml present"    || bad "$seat/config.yaml missing"
  [ -f "$agents" ] && ok "$seat/AGENTS.md present"      || bad "$seat/AGENTS.md missing"
  [ -f "$agents" ] && grep -q "Room role:" "$agents" \
      && ok "$seat role contract declares 'Room role:'" \
      || bad "$seat AGENTS.md has no 'Room role:' line"
done

for f in WORKFLOW.md PROMPT_TEMPLATES.md; do
  [ -f "$HERMES_PROFILES_DIR/$f" ] && ok "shared contract $f present" || bad "shared contract $f missing"
done

head_ "Skills"
check_skill() { # seat name
  local skill_file
  skill_file="$(find "$HERMES_PROFILES_DIR/$1/skills" -path "*/$2/SKILL.md" -print -quit 2>/dev/null)"
  [ -n "$skill_file" ] && ok "$1 has skill '$2'" || bad "$1 is missing skill '$2'"
}
check_skill supervisor paseo-room-supervisor
check_skill lead       paseo-lead-orchestration
check_skill peer       scoped-change-briefs

head_ "Credentials"
for seat in supervisor lead peer; do
  env_file="$HERMES_PROFILES_DIR/$seat/.env"
  if [ -f "$env_file" ] && grep -qE '^SWICLOUD_API_KEY=.+' "$env_file"; then
    ok "$seat/.env has a non-empty SWICLOUD_API_KEY"
  else
    bad "$seat/.env SWICLOUD_API_KEY missing or empty (blocker for that seat)"
  fi
done

head_ "Paseo config"
cfg="$PASEO_HOME/config.json"
if [ -f "$cfg" ]; then
  python3 - "$cfg" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
providers = (cfg.get("agents") or {}).get("providers") or {}
profiles = ((cfg.get("daemon") or {}).get("agentProfiles")) or []
ok_n = fail_n = 0
def ok(m):
    global ok_n; ok_n += 1; print(f"  PASS  {m}")
def bad(m):
    global fail_n; fail_n += 1; print(f"  FAIL  {m}")
for seat in ("supervisor", "lead", "peer"):
    key = f"hermes-{seat}"
    p = providers.get(key)
    if not p:
        bad(f"{key} provider missing")
    elif p.get("enabled") is False:
        bad(f"{key} provider is disabled")
    else:
        cmd = " ".join(p.get("command") or [])
        if f"--profile {seat}" in cmd:
            ok(f"{key} → {cmd}")
        else:
            bad(f"{key} command does not select profile {seat}: {cmd!r}")
names = {p.get("name") for p in profiles if isinstance(p, dict)}
for want in ("Supervisor", "Lead", "Peer"):
    ok(f"agent profile {want!r} present") if want in names else bad(f"agent profile {want!r} missing")
others = sorted(k for k in providers if not k.startswith("hermes-"))
print(f"  note  other providers left alone: {', '.join(others) if others else '(none)'}")
sys.exit(1 if fail_n else 0)
PY
  [ $? -eq 0 ] && pass=$((pass+1)) || fail=$((fail+1))
else
  warn "no Paseo config at $cfg (skip if this machine has no Paseo)"
fi

head_ "Live daemon (optional)"
if curl -sf -m 3 "$DAEMON_URL/api/health" >/dev/null 2>&1; then
  ok "daemon answering at $DAEMON_URL"
  if command -v paseo >/dev/null 2>&1; then
    n=$(paseo agent ls --host 127.0.0.1:6767 --json 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo "?")
    warn "agents currently known to the daemon: $n"
  else
    warn "no 'paseo' CLI — list agents from the Paseo Desktop UI"
  fi
else
  warn "daemon not reachable at $DAEMON_URL (Paseo Desktop not running)"
fi

printf '\n%d passed, %d failed, %d warnings\n' "$pass" "$fail" "$warn_n"
[ "$fail" -eq 0 ] || exit 1
