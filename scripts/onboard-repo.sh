#!/usr/bin/env bash
# onboard-repo.sh — baseline report for an EXISTING repo before the room touches it.
#
# Run this from the Supervisor seat for any repo that has history (not greenfield),
# and paste the output into the Lead brief. It records the facts a brief must carry:
# branch/HEAD, dirty state, existing agent rules, the real test command, repo shape,
# and whether the room already has worktrees here.
#
#   bash scripts/onboard-repo.sh /path/to/repo [--run-tests] [--test-cmd "CMD"] [--out FILE]
#
# --run-tests executes the detected suite (default: only report it — a mature repo's
# suite can be slow or side-effecting, that decision belongs to the Supervisor).
set -uo pipefail

REPO="${1:-}"
[ -n "$REPO" ] || { sed -n '2,13p' "$0"; exit 2; }
shift || true
RUN_TESTS=0
TEST_CMD=""
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run-tests) RUN_TESTS=1; shift ;;
    --test-cmd)  TEST_CMD="$2"; shift 2 ;;
    --out)       OUT="$2"; shift 2 ;;
    -h|--help)   sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "error: no such directory" >&2; exit 1; }
cd "$REPO" || exit 1

emit() { printf '%s\n' "$*"; [ -n "$OUT" ] && printf '%s\n' "$*" >> "$OUT"; }
[ -n "$OUT" ] && : > "$OUT"

emit "# Baseline report — $(basename "$REPO")"
emit "_generated $(date -Iseconds) on $(hostname)_"
emit ""

emit "## Repository"
if git rev-parse --git-dir >/dev/null 2>&1; then
  emit "- path: \`$REPO\`"
  emit "- branch: \`$(git rev-parse --abbrev-ref HEAD)\`"
  emit "- HEAD: \`$(git rev-parse --short HEAD)\` ($(git log -1 --format=%cI))"
  emit "- last commit: $(git log -1 --format=%s)"
  emit "- commits: $(git rev-list --count HEAD 2>/dev/null || echo '?') | first: $(git log --reverse --format=%cI | head -1)"
  remotes="$(git remote -v | awk '{print $2}' | sort -u | tr '\n' ' ')"
  emit "- remotes: ${remotes:-（none — nothing can be pushed anyway）}"
  extra_wt="$(git worktree list | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
  emit "- git worktrees: $(git worktree list | wc -l) total (extra: ${extra_wt:-none}) — peers will add more"
else
  emit "- NOT a git repo — create one and commit a base before dispatch"
fi
emit ""

emit "## Working tree state (must be clean before dispatch)"
dirty="$(git status --porcelain 2>/dev/null | wc -l)"
emit "- changed/untracked entries: $dirty"
if [ "$dirty" -gt 0 ]; then
  git status --porcelain 2>/dev/null | head -20 | while read -r line; do emit "  - \`$line\`"; done
  [ "$dirty" -gt 20 ] && emit "  - … $((dirty - 20)) more"
  emit "- ACTION: commit or stash these before the room starts (peers branch off HEAD)"
fi
stashes="$(git stash list 2>/dev/null | wc -l)"
[ "$stashes" -gt 0 ] && emit "- stashes: $stashes (decide whether they matter)"
emit ""

emit "## Rules already in the repo (these win over room defaults)"
found_rules=0
for f in AGENTS.md CLAUDE.md .cursorrules .cursor/rules CONTRIBUTING.md CODEOWNERS docs/WORKSPACE_PROTOCOL.md docs/CONTRACT.md; do
  [ -e "$f" ] && { emit "- \`$f\` ($(wc -l < "$f" 2>/dev/null || echo '?') lines)"; found_rules=1; }
done
[ "$found_rules" = 0 ] && emit "- none found"
emit ""

emit "## Test / CI entrypoints (use the project's real command)"
detected=""
test_dir=""
[ -d tests ] && test_dir=tests
[ -z "$test_dir" ] && [ -d test ] && test_dir=test
if [ -n "$test_dir" ]; then
  if [ -f pytest.ini ] || grep -qs "pytest" pyproject.toml 2>/dev/null || grep -rqs "^import pytest\|^from pytest" "$test_dir" 2>/dev/null; then
    detected="python3 -m pytest -q"
  else
    detected="python3 -m unittest discover -s $test_dir -v"
  fi
fi
if [ -z "$detected" ] && grep -qs "pytest" pyproject.toml 2>/dev/null; then
  detected="python3 -m pytest -q"
fi
if [ -z "$detected" ] && [ -f package.json ]; then
  detected="$(python3 - "$PWD/package.json" <<'PY'
import json,sys
scripts=(json.load(open(sys.argv[1],encoding="utf-8")).get("scripts") or {})
print("npm test" if "test" in scripts else "")
PY
)"
fi
[ -z "$detected" ] && [ -f Makefile ] && grep -qE '^test:' Makefile && detected="make test"
for ci in .github/workflows .gitlab-ci.yml .circleci Jenkinsfile azure-pipelines.yml .buildkite; do
  [ -e "$ci" ] && emit "- CI config: \`$ci\`"
done
emit "- detected test command: \`${detected:-unknown — ask the human}\`"
emit "- lint/format config: $(ls -d ruff.toml .ruff.toml .flake8 .eslintrc* .prettierrc* 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
emit ""

emit "## Repo shape (helps the Lead find independent write scopes)"
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  git ls-files | awk -F/ 'NF>1{print $1"/"} NF==1{print "(root files)"}' | sort | uniq -c | sort -rn | head -12 \
    | while read -r n dir; do emit "- \`$dir\` — $n tracked file(s)"; done
  emit "- total tracked files: $(git ls-files | wc -l)"
else
  find . -maxdepth 2 -type d ! -path "*/.git*" | head -12 | while read -r d; do emit "- \`$d\`"; done
fi
emit ""

emit "## Baseline suite"
cmd="$TEST_CMD"
[ -z "$cmd" ] && cmd="$detected"
if [ "$RUN_TESTS" = 1 ] && [ -n "$cmd" ] && [ "$cmd" != "unknown — ask the human" ]; then
  emit "\`$cmd\` (timeout 600s):"
  out="$(timeout 600 bash -c "$cmd" 2>&1)"; rc=$?
  emit '```'
  printf '%s\n' "$out" | tail -25 | while read -r l; do emit "$l"; done
  emit '```'
  emit "- exit code: $rc — **this is the baseline; acceptance = no regression**"
  emit "- if the baseline is RED, record which failures pre-exist and forbid 'fixing' them silently"
else
  emit "- not run (pass --run-tests, or --test-cmd \"…\") — acceptance will be measured against whatever you record here"
fi
emit ""

emit "## Brief material"
emit "- base commit for all peer worktrees: \`$(git rev-parse HEAD 2>/dev/null)\`"
emit "- recommended integration branch: \`room/<task-slug>\` branched from HEAD (NOT directly on the project's main)"
emit "- unresolved inputs to confirm with the human: env vars/secrets, fixtures, DB, external services"

if [ -n "$OUT" ]; then printf '\nwritten: %s\n' "$OUT"; fi
