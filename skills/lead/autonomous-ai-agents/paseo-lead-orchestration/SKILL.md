---
name: paseo-lead-orchestration
description: "Use when Lead orchestrates peers via Paseo MCP worktrees."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [multi-agent, lead, peer, paseo, orchestration, worktree, review, merge]
    related_skills: [hermes-multi-agent, test-driven-development]
---

# Lead Orchestration via Paseo MCP

Procedure for a Lead role that spawns peers via Paseo MCP (`create_workspace` + `create_agent`), reviews artifacts, and integrates into `main`. Each peer owns one write scope; Lead coordinates, reviews, and integrates.

## When to Use

- Lead must parallelize independent fixes/features across N modules with strict write-scope isolation
- Each module has its own test suite; peers must run tests before committing
- Lead is explicitly forbidden from writing module code (role separation enforced by brief)

## Step-by-Step Procedure

### 1. Context Gathering (before briefing anyone)

Read all relevant artifacts first: contract/README + every target module + every test file. Run the test suite to confirm the current baseline.

```bash
cd <repo_root>
python3 -m unittest discover -s tests -v 2>&1
```

For each module/feature, identify:
- Exact scope (new module vs. bug fix)
- Approach (one clear direction)
- Which tests will catch regression if approach is wrong

### 1b. Design commit (for new-feature rounds)

When the round adds new modules rather than fixing existing ones, write and commit the design artifacts **before** dispatching any peer:

1. Write `docs/FEATURES.md` (or equivalent): feature table with user value, risk, files touched, acceptance criteria, and explicit CHOSEN / REJECTED reasoning.
2. Update `README.md`: add new commands and acceptance criteria.
3. Update `docs/CONTRACT.md`: add public API signatures, invariants, and file-ownership map for every new module.
4. Commit: `git commit -m "design: <scope> — FEATURES.md + CONTRACT.md + README updated"`
5. Record the resulting base commit hash — every peer brief's `BASE:` field must reference it.

Peers write code against a stable, committed design contract. Never dispatch a peer before the design commit exists.

### 2. Create Worktrees (one per peer)

```python
# tool_call — one at a time
mcp__paseo__create_workspace(
    isolation="worktree",
    path="<repo_root>",          # source checkout
    mode="branch-off",
    branchName="peer/<module>",  # e.g. peer/lru-cache
    title="peer/<module> — <one-line purpose>"
)
# Returns: workspaceId, cwd (worktree path)
```

One worktree = one write scope = one owner. Never assign two peers to the same worktree.

**Naming (user-mandated)**: user-visible titles must be `<scope> — <purpose>` for workspaces and `<Role> <Domain> — <scope>` for agents (e.g. `Peer Backend — render`, `Lead Backend — api`). Do not leave ad-hoc ids like `peer-render-v2` as the agent title.

### 3. Create Agents (one per `tool_call` invocation, ALL in the same Lead turn)

**Critical**: `tool_call` rejects batches of >1 local MCP tool — issue each `create_agent` as a separate `tool_call`. But ALL `create_workspace` + `create_agent` calls for a round must be issued **within the same Lead response turn**, before awaiting any result. The pattern is:

```
Turn N:  create_workspace(A) → create_agent(A)       # tool_call 1
         create_workspace(B) → create_agent(B)       # tool_call 2
         create_workspace(C) → create_agent(C)       # tool_call 3
         [end turn — all 3 peers now running]
Turn N+1: first notify arrives → review that peer; others still running
```

Never do:
```
Turn N:   create_workspace(A) → create_agent(A)
Turn N+1: [await A finish] → create_workspace(B) → create_agent(B)   ← WRONG
```
That makes peers run sequentially, not in parallel, even though each `tool_call` is correctly serialized.

```python
mcp__paseo__create_agent(
    title="peer-<module>: <one-line purpose>",
    provider="hermes-peer/custom:swicloud:cmc/deepseek/deepseek-v4-flash",
    settings={"modeId": "dont_ask"},
    workspaceId="<id from step 2>",
    notifyOnFinish=True,
    initialPrompt="<brief — see references/peer-brief-template.md>"
)
```

If a `create_workspace` or `create_agent` call errors, retry it immediately **in the same turn** before ending the turn. Do not silently skip and retry in a later turn — that serializes the entire round.

### 3b. Sequential waves when scopes are interdependent

Some rounds have a mandatory serial dependency: Wave A owns a shared file (e.g. `model.py`) that Wave B peers import. Wave B CANNOT run in parallel with Wave A — it must run after Wave A is accepted and merged.

Rule: if peer B imports a symbol from peer A's scope, Wave A must be accepted AND merged into `main` before Wave B is dispatched. Do not attempt to paper over this with stubs when the real file is about to exist. The correct sequencing is:

```
Wave A: peer/model-v3 (serial — owns shared model)
  → ACCEPT + merge to main
Wave B: peer/service-v3 + peer/storage-v3 (parallel — both import model, independent of each other)
  → branch off main after Wave A merge so the updated model is in the base
```

When a round has this structure, state the dependency explicitly in the design commit and in the report.

### 4. Wait for Notify Events

Do NOT poll agent status. `notifyOnFinish=true` fires on finish/error/attention. Act only when the event arrives. Multiple peers run concurrently; each notify is handled independently — review the arriving peer immediately; do not wait for the others before reviewing.

### 5. Lead Review Gate (MANDATORY before acceptance)

For each finished peer, before any merge:

```bash
# In the peer's worktree:
git log --oneline -3
git show <candidate_commit>       # read the full diff
```

Verify:
- [ ] Commit hash from `git log` matches hash peer reported (mismatch → reject)
- [ ] Diff touches only the 2 allowed files
- [ ] Logic satisfies the contract (trace through each public method change)
- [ ] No new imports outside stdlib
- [ ] README untouched
- [ ] Test file assertions unchanged (if test file was modified)

If review fails: send a specific correction to the peer via `send_agent_prompt` (file:line, wrong behavior, expected behavior). Peer commits a new fix on the same branch and reports back. Repeat until review PASS.

Do not accept on peer's word alone. Do not accept because test output looks green.

### 6. Worktree preparation for peers that depend on not-yet-merged artifacts

Two patterns depending on whether the downstream peer owns those files:

**Pattern A — downstream peer OWNS the dependency** (e.g. a single "wiring" peer that integrates Wave 1 modules as part of its own commit):

```bash
# Copy Wave 1 output files into the Wave 2 worktree as untracked files
cp <wt-peer-A>/todo/module_a.py <wt-wave2>/todo/module_a.py
cp <wt-peer-B>/todo/module_b.py <wt-wave2>/todo/module_b.py
# Brief the peer to git add those files as part of its commit
```

**Pattern B — downstream peer does NOT own the dependency** (e.g. Wave C wires cli.py and imports render.py, but render.py is owned by a separate Wave B peer):

```bash
# Copy dependency files as UNTRACKED only — for import resolution
cp <wt-render>/todo/render.py <wt-cli>/todo/render.py
cp <wt-render-rich>/todo/render_rich.py <wt-cli>/todo/render_rich.py
# Brief the peer: "DO NOT git add these files — they are untracked stubs for import
#                  only and will be merged via their own branches"
```

Choose Pattern A when the downstream peer is responsible for delivering those artifacts. Choose Pattern B when those artifacts have their own peer+branch and will be merged separately. State which pattern applies in the brief.


### 7. Integration

Only after ALL peer reviews PASS:

```bash
cd <repo_root>   # main repo, not a worktree
git merge --no-ff peer/<module> -m "integrate(<module>): <reason>"
```

Merge one branch at a time. Resolve conflicts before the next merge. After all merges:

```bash
python3 -m unittest discover -s tests -v 2>&1
```

All tests must pass. ACCEPT or REJECT each candidate with a technical reason based on diff evidence.

## Pitfalls

- **`create_agent` title max 60 chars** — `tool_call` rejects with a schema validation error if the title exceeds 60 characters. Keep titles to `peer-<scope>: <verb> <object>` form; truncate the object before the verb.
- **All peers in one turn, not one peer per turn** — `tool_call` serialization (one MCP call per invocation) does NOT mean one peer per Lead turn. Issue all `create_workspace` + `create_agent` pairs for a round in a single turn; end the turn; then await events. Issuing them across turns makes the round sequential, not parallel.
  - Anti-pattern A: creating ALL worktrees in block 1, then ALL agents in block 2 — if an interrupt or user message arrives between the blocks, agents land in different turns and run serially.
  - Anti-pattern B: creating workspace(A) + agent(A) correctly in turn N, then any external message causes the Lead to end turn N early — B and C are dispatched in turns N+1 and N+2, fully serial.
  - **The correct interleaving** (must survive any interrupt): `create_workspace(A)` → `create_agent(A)` → `create_workspace(B)` → `create_agent(B)` → ... ALL in turn N. Only ONE workspace+agent pair per `tool_call` invocation, but all pairs in the SAME response turn before ending the turn.
  - **Self-check before ending the turn**: after issuing all create_agent calls for the wave, call `mcp__paseo__get_agent_status` on each agentId and confirm `status == "running"` before ending the turn. If any agent is missing, create it immediately in the same turn.
- **Retry dispatch errors in the same turn** — if a `create_workspace` or `create_agent` call fails, retry it immediately before ending the turn. A silent skip followed by a later retry serializes the whole round.
- **Greenfield Wave 1 peers: stubs for cross-peer imports** — when a Wave 1 peer imports a module owned by a *different* Wave 1 peer that hasn't been merged yet, brief the peer to create a LOCAL UNTRACKED minimal stub and `git add` only their scope files. State: "create stub, do NOT git add it".
- **Wave 2 worktree: copy real implementations, not stubs** — Wave 2 branches off `main` before Wave 1 is merged. Physically copy the accepted Wave 1 output files into the Wave 2 worktree (`cp`), then brief the peer to `git add` them. The Wave 2 peer gets real implementations to import, test, and wire — not stubs.
- **Commit timestamps are NOT valid parallelism proof** — a peer can be created at T1, idle for 30s, then commit at T2, making commit times appear overlapping even when agents ran serially. The only valid proof is that the `[createdAt, updatedAt]` intervals from `mcp__paseo__get_agent_status` INTERSECT for two peers. If intervals do not intersect, report the round as sequential regardless of how the commit times look. Never infer overlap from `git log` timestamps.
- **One MCP command per `tool_call`, whole wave per turn** — each `create_agent` needs its own `tool_call` invocation, but all of them belong to the same turn. Never treat the batching limit as "wait for peer 1 before creating peer 2".
- **Handle each notify independently** — when one peer finishes, review that peer immediately; peers still running must not be blocked, and the next wave only depends on the *previous wave's* accepted artifacts, not on the review of an unrelated peer.
- **Read artifacts before briefing** — without reading actual source + tests, bug analysis will be wrong and peer fixes the wrong thing.
- **Review gate is not optional** — test output passing on peer's machine is not proof; diff may fix tests via assertion deletion or scope drift. Always `git show <hash>` and read the diff.
- **Hash verification is the first review step** — a peer that misreports a commit hash cannot be trusted; reject immediately.
- **`--no-ff` merge** — avoids fast-forward that loses peer commit provenance in the log.
- **Worktree path ≠ repo root** — worktree lives under `~/.paseo/worktrees/<id>/peer-<module>`; run full-suite integration from repo root, not a worktree.
- **Stale worktree base after a design commit** — if an interrupt causes a design commit to land on `main` AFTER a worktree was already created, that worktree's base is one commit behind. Do NOT reuse it — create a new worktree branching off the current `main`. The peer brief's `BASE:` must match `git log --oneline -1` on the worktree; verify before briefing.
- **Wave B with N>2 parallel peers** — the same one-turn rule applies regardless of N. Pattern for 3 peers: `create_workspace(B1)→create_agent(B1)→create_workspace(B2)→create_agent(B2)→create_workspace(B3)→create_agent(B3)` — all in one turn. Confirm all N agents `status=="running"` via `get_agent_status` before ending the turn. If any is missing, create it in the same turn.
- **`send_agent_prompt` field is `prompt`, not `message`** — the MCP tool schema requires the field named `prompt`; passing `message` causes a validation error and the call is NOT invoked. Always use `prompt=` in the arguments object.
- **`send_agent_prompt` for corrections, not a new agent** — reopen on the same agent/branch so fix commits chain on the same branch.
- **Do not merge a partially-reviewed batch** — wait for all review rounds to complete before any merge.
- **`respond_to_permission` requires `response` object, not a flat `optionId`** — the schema is `{agentId, requestId, response: {behavior: "allow"|"deny", selectedActionId: "<optionId>"}}`. Passing `optionId` at the top level causes a schema validation error and the tool is NOT invoked, leaving the peer blocked on the permission prompt. Always nest `behavior` + `selectedActionId` inside `response`.
- **`get_agent_activity` output can exceed the inline limit** — when it does, the full result is auto-saved to a spillover file (path shown in the result). Use `read_file(path=<spillover_path>)` to page through it; do NOT re-call `get_agent_activity` to retry — the file already holds the complete data.
- **Verify runtime prerequisites BEFORE briefing a peer to run a service** — check the interpreter version the project actually runs on, the real build entry path, and whether the host can resolve the container hostnames; put all three in the peer brief. Real example: a NestJS repo needed Node 22 (Node 24+ crashes a legacy dep through the removed `SlowBuffer`), the entry was `dist/src/main.js` (not `dist/main.js`), and running from the host required `MONGO_HOST=127.0.0.1 REDIS_HOST=127.0.0.1` because docker-compose hostnames have no DNS outside the compose network. Discovering these cost a peer half its run.
- **Ask which execution environment is permitted BEFORE any peer runs anything — never assume the host is allowed.** On a real project the app ran only inside Docker (`nest start --watch` inside a container, code mounted from the main checkout, `node_modules` in a named volume) while a peer had started the same service on the host with a host `npm build`. Peers then proved real things by an unsanctioned method and the whole wave had to be re-briefed. Rules to establish up front: is host execution allowed at all; which container serves the app and on which internal port; does the container mount the main checkout (so a peer's worktree is NOT what runs, and writing to the mounted `src/` hot-reloads the human's live dev server); and that `docker compose up/down/restart` is off-limits. Harness then runs as `docker cp <script> <container>:/tmp/x.js` + `docker exec <container> node /tmp/x.js`.
- **Never brief a peer to run a repo's `lint` script without reading the script first** — one containing `--fix` rewrites the tree (a real repo had 18k prettier errors from an `endOfLine: crlf` mismatch and `--fix` would have rewritten 315 files). If lint must be a gate, run the linter read-only and record the pre-existing error count as the baseline.
- **`--out` / relative artifact paths**: in a peer brief, always give ABSOLUTE artifact paths. A script that `cd`s into the repo resolves a relative output path inside the repo, which either dirties the tree or silently fails.

## Final Report Format

```
| Module | Peer Agent ID | Candidate Commit | Review Rounds | Test on main | Verdict |
|--------|--------------|-----------------|---------------|-------------|--------|
| <mod>  | <id>          | <hash>           | 1             | N/N OK      | ACCEPT |

Round parallelism evidence:
- Round 1 (N peers): <peer-A> started <HH:MM:SS>, finished <HH:MM:SS>; <peer-B> started ...; overlap: yes/no
  (If only 1 scope in the round: state "1 scope, no parallelism possible" — do NOT invent extra scopes)

Progress: N/N modules integrated into main.
Residual risk: <list or "none">
Human decisions needed: <list or "none">
```

Timestamps: use `mcp__paseo__get_agent_status` `createdAt` and `updatedAt` fields for every peer in the round. Do NOT use commit timestamps — a peer can be created at T1, do nothing for 30s, then commit at T2, making commit times appear overlapping when the agents were actually sequential. The only valid parallelism proof is that the `[createdAt, updatedAt]` intervals of two peers INTERSECT. If the intervals do not intersect, report the round as sequential regardless of commit timestamps.

See `references/peer-brief-template.md` for the full brief structure.
See `references/verification-harness.md` for proof-only peer patterns: discriminating test design, WebSocket wire-frame capture, HMAC signing, fixture strategy, and evidence artifact format.
