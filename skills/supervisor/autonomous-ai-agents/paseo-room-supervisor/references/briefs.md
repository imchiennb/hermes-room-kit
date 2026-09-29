# Brief skeletons

Copy, fill, and keep every section — incomplete briefs are the main cause of scope drift.

## Supervisor -> Lead

```
Role: Lead <Domain>. You coordinate, review, and integrate. You do NOT write product code.

## Goal
<Human intent restated as an outcome, one paragraph, no private conversation>

## Repo
<path> — branch main, base commit <hash>. State: <tests x/y, what exists>.

## Steps
1. Read README + all existing code/tests. Freeze the internal contract in docs/CONTRACT.md
   (function signatures, data schema, error/exit-code rules, per-peer file boundaries).
2. Split into bounded outcomes with independent write scopes; order by dependency.
3. Dispatch one WAVE per dependency level: ALL workspaces + agents of a wave in ONE turn,
   then await events. Peer provider hermes-peer/<model>, settings {"modeId":"dont_ask"},
   create_workspace isolation="worktree" mode="branch-off" branchName="peer/<scope>",
   notifyOnFinish=true. Brief each peer with: observable outcome, exact files, contract
   references, invariants (keep signatures, stdlib only, no other files), the test command
   that must really run, commit on the peer branch, NO push, and the exact response format
   (CANDIDATE_COMMIT / BRANCH / BASE / FILES_CHANGED / TEST_OUTPUT / RISK).
4. REVIEW LOOP: for each finished peer read `git show <candidate>` yourself and check hash,
   scope, contract, stdlib-only, README untouched, and test coverage of every acceptance
   criterion. Send corrections to the SAME peer on the SAME branch until nothing needs changing.
5. Integrate accepted branches into main in dependency order (--no-ff), run the full suite
   on main, run a real end-to-end smoke test. ACCEPT/REJECT each candidate with a reason.

## Invariants
No push. Each write scope has one owner. Shared files are single-writer and sequenced.
Escalate to Supervisor only when blocked or when a decision exceeds your authority
(push/merge remote, delete data, change product scope or the contract).

## Final report
Table: scope | peer agent id | candidate commit | review rounds (with what was sent back) |
main test result | verdict. Plus per-peer start/end timestamps proving overlap, the smoke-test
command + real output, residual risk, and "Human decisions needed" (or "none").
```

## Lead -> Peer

```
## PEER BRIEF — <scope>

### Outcome
<exact command> from <worktree root> must be fully green, and <observable behaviour>.

### Files allowed to change (exactly these)
- <src file>
- <test file>

### Forbidden
README.md, docs/CONTRACT.md, every other src/ or tests/ file, anything outside the worktree.

### Contract to preserve
<signatures + invariants from docs/CONTRACT.md> — no new dependency outside stdlib.

### Suggested approach
<one clear direction (a hint, not a mandate)>

### Test command (must really run before commit)
<command + expected result>

### Commit
Commit on branch peer/<scope> of this worktree. NO push to remote.

### Required response format
CANDIDATE_COMMIT: <40-char hash>
BRANCH: peer/<scope>
BASE: <base commit>
FILES_CHANGED: <list>
TEST_OUTPUT:
<verbatim output>
RISK: <residual risk or "none">
```
