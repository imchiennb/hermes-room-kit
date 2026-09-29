# Peer Brief Template

Copy-paste this structure into `initialPrompt` when creating a peer agent. Fill every section — incomplete briefs cause scope drift.

```
## PEER BRIEF — <Module Name>

### Outcome
<test command> run from <worktree_root> must be fully green.
Example: `python3 -m unittest tests.test_<module> -v` run from `<worktree root>` (`~/.paseo/worktrees/<id>/peer-<scope>`)

### Files allowed to change (exactly 2)
- src/<module>.py
- tests/test_<module>.py

### Files forbidden to touch
- README.md
- all other src/ and tests/ files
- any file outside the two above

### Contract to preserve
- Class <Name>(<args>) — public API: <list methods>
- <key invariant 1>
- <key invariant 2>
- No new dependencies outside stdlib

### Bug analysis
<exact bug, mechanism, which tests currently fail and why>

### Suggested approach
<one clear direction with key implementation detail>

### Test command (must run for real before commit)
```bash
cd <worktree_root>
<test command>
```
Must be green before committing.

### Commit
Commit to branch `peer/<module>` of this worktree. NO push to remote.

### Required response format
```
CANDIDATE_COMMIT: <40-char hash>
BRANCH: peer/<module>
BASE: <base commit hash>
FILES_CHANGED: <list>
TEST_OUTPUT:
<full verbatim output of test command>
RISK: <residual risk or "none">
```
```

## Invariants for All Briefs

- Outcome must be **observable** (test command + expected result), not vague ("fix the bug").
- The 2-file limit is not optional; state it explicitly and repeat under forbidden files.
- Contract section must include all public method signatures; peer must not add new public API.
- Suggested approach is a hint, not a mandate — peer may diverge if they can pass all tests within scope.
- Base commit hash must match the actual `git log` hash in the worktree; verify before briefing.
- The response format must be verbatim so Lead can parse it programmatically.

## Test-file mutation rules (critical — brief must state these explicitly)

Two categories of existing tests respond differently to schema/API changes:

**Logic/behavior tests** — e.g. `test_done_defaults_false`, `test_mark_done_missing_raises`. Test invariants that do not change with new fields. Brief instruction: "MUST NOT be deleted or weakened."

**Schema/shape tests** — e.g. `test_to_dict_keys_and_values` (asserts exact key set), `test_valid_json_returns_tasks` (asserts exact dict equality). When the schema gains new fields, these MUST be updated to reflect the new shape. Brief instruction: "UPDATE to match new schema — add the new keys to expected dicts; do not delete the test."

When writing the brief for a schema-changing peer (model field addition, etc.):
1. Identify which existing tests assert exact dict shapes or exact key lists.
2. Tell the peer explicitly: "Fix `<TestClass>.<test_name>` at `tests/<file>.py:L<N>` — add `\"<field>\": <default>` to the expected dict."
3. If you miss these tests upfront, the peer will correctly refuse to update them (since brief said "MUST NOT") and return a FAIL. Issue a `send_agent_prompt` correction (field `prompt`, not `message`) identifying the specific lines and authorizing the update.

**Never write "existing tests MUST NOT be changed"** without qualification. The correct framing:
- "Existing *logic* tests MUST NOT be deleted or weakened."
- "Existing *schema-shape* tests at [list lines] MUST be updated to include the new fields."

## Schema-change fallout across file boundaries

When a shared model (`model.py`) gains new fields, tests in OTHER modules assert old shapes too:
- `tests/test_storage.py`: any test that calls `to_dict()` and compares to a literal dict.
- `tests/test_cli.py`: `test_json_schema` asserts sorted key list.

The owning peers of those files (peer/storage-vN, peer/cli-vN) must handle their own fallout. Lead's job: identify the stale lines before briefing each Wave B/C peer, and include the specific line numbers and fix in each brief.
