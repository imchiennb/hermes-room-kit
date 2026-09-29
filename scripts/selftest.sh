#!/usr/bin/env bash
# selftest.sh — prove THIS KIT works, without a second machine.
#
# It installs the room into a throwaway root (profiles dir + Paseo home), checks
# idempotency, and runs verify.sh against that root. Nothing touches the real
# ~/.hermes/profiles or ~/.paseo.
#
#   bash scripts/selftest.sh            # run the full self-test
#   bash scripts/selftest.sh --keep     # keep the temp root for inspection
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

TMP="$(mktemp -d "${TMPDIR:-/tmp}/room-kit-selftest.XXXXXX")"
ROOT="$TMP/profiles"
PASEO="$TMP/paseo"
pass=0; fail=0
ok()   { printf '  PASS  %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$*"; fail=$((fail+1)); }
head_() { printf '\n%s\n' "$*"; }

cleanup() {
  if [ "$KEEP" = 1 ]; then printf '\ntemp root kept: %s\n' "$TMP"; else rm -rf "$TMP"; fi
}
trap cleanup EXIT

head_ "setup a fake target machine inside $TMP"
mkdir -p "$ROOT" "$PASEO"
python3 - "$PASEO/config.json" <<'PY'
import json, sys
json.dump({
    "version": 1,
    "daemon": {"listen": "127.0.0.1:6767", "mcp": {"injectIntoAgents": True}, "relay": {"enabled": True}},
    "app": {"baseUrl": "https://app.paseo.sh"},
    "pluginsEnabled": True,
    "agents": {"providers": {"claude": {"enabled": False}, "codex": {"enabled": False}}},
}, open(sys.argv[1], "w"), indent=2)
PY
ok "fake paseo config with foreign providers created"

head_ "install #1"
if bash "$KIT_DIR/install.sh" --root "$ROOT" --paseo-home "$PASEO" --no-reload >"$TMP/install1.log" 2>&1; then
  ok "install.sh exited 0"
else
  bad "install.sh failed — see $TMP/install1.log"; tail -20 "$TMP/install1.log"
fi

head_ "files landed where Hermes expects them"
for seat in supervisor lead peer; do
  [ -f "$ROOT/$seat/config.yaml" ] && ok "$seat/config.yaml" || bad "$seat/config.yaml missing"
  [ -f "$ROOT/$seat/AGENTS.md" ]   && ok "$seat/AGENTS.md"   || bad "$seat/AGENTS.md missing"
  [ -f "$ROOT/$seat/.env" ]        && ok "$seat/.env template" || bad "$seat/.env missing"
done
for f in WORKFLOW.md PROMPT_TEMPLATES.md; do
  [ -f "$ROOT/$f" ] && ok "shared $f" || bad "shared $f missing"
done
for spec in "supervisor:autonomous-ai-agents:paseo-room-supervisor" \
            "lead:autonomous-ai-agents:paseo-lead-orchestration" \
            "peer:software-development:scoped-change-briefs"; do
  IFS=: read -r seat cat name <<<"$spec"
  [ -f "$ROOT/$seat/skills/$cat/$name/SKILL.md" ] && ok "$seat skill $name" || bad "$seat skill $name missing"
done

head_ "paseo merge preserved foreign providers + added the room"
python3 - "$PASEO/config.json" <<'PY' && ok "paseo config merged correctly" || bad "paseo config wrong"
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
p = cfg["agents"]["providers"]
names = {a.get("name") for a in cfg["daemon"]["agentProfiles"]}
assert "claude" in p and "codex" in p, "foreign providers were dropped"
for seat in ("supervisor", "lead", "peer"):
    assert f"hermes-{seat}" in p, f"provider hermes-{seat} missing"
    assert p[f"hermes-{seat}"].get("enabled") is not False, f"hermes-{seat} disabled"
for want in ("Supervisor", "Lead", "Peer"):
    assert want in names, f"agent profile {want} missing"
PY

head_ "install #2 is idempotent (no duplicate providers / agent profiles)"
if bash "$KIT_DIR/install.sh" --root "$ROOT" --paseo-home "$PASEO" --no-reload >"$TMP/install2.log" 2>&1; then
  ok "second install exited 0"
else
  bad "second install failed"; tail -20 "$TMP/install2.log"
fi
python3 - "$PASEO/config.json" <<'PY' && ok "no duplication after the second run" || bad "duplication after the second run"
import json, sys, collections
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
profiles = [a.get("name") for a in cfg["daemon"]["agentProfiles"]]
dupes = [n for n, c in collections.Counter(profiles).items() if c > 1]
assert not dupes, f"duplicate agent profiles: {dupes}"
assert len(cfg["agents"]["providers"]) == 5, f"provider count changed: {len(cfg['agents']['providers'])}"
PY
grep -q "already current" "$TMP/install2.log" && ok "skills recognised as already current" || bad "skills reinstalled on the second run"

head_ "verify.sh against the installed room"
for seat in supervisor lead peer; do printf 'SWICLOUD_API_KEY=dummy-self-test\n' > "$ROOT/$seat/.env"; done
bash "$KIT_DIR/verify.sh" --root "$ROOT" --paseo-home "$PASEO" >"$TMP/verify.log" 2>&1
vrc=$?
tail -3 "$TMP/verify.log" | sed 's/^/    /'
[ "$vrc" -eq 0 ] && ok "verify.sh exited 0" || bad "verify.sh exited $vrc"

head_ "revert path: merge script can remove only the room entries"
cp -p "$PASEO/config.json" "$TMP/before-revert.json"
python3 "$KIT_DIR/scripts/merge_paseo_config.py" --fragment "$KIT_DIR/paseo/room.fragment.json" --config "$PASEO/config.json" --remove >/dev/null 2>&1
python3 - "$PASEO/config.json" <<'PY' && ok "--remove dropped the room and kept foreign providers" || bad "--remove behaved incorrectly"
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
p = cfg["agents"]["providers"]
assert not [k for k in p if k.startswith("hermes-")], "hermes-* providers left behind"
assert "claude" in p, "foreign provider claude was removed"
assert not [a for a in cfg["daemon"]["agentProfiles"] if str(a.get("provider","")).startswith("hermes-")], "room agent profiles left behind"
PY

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
