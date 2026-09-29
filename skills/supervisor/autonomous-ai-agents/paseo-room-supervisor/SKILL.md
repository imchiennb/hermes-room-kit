---
name: paseo-room-supervisor
description: "Use when supervising a Paseo/Hermes agent room."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [multi-agent, supervisor, lead, peer, paseo, orchestration, worktree, review]
    related_skills: [hermes-multi-agent, paseo-lead-orchestration]
---

# Supervising a Paseo/Hermes agent room

How to act as the **Supervisor** seat of a room driven from Paseo Desktop, with N domain Leads under it, each owning Peers. Load this before spawning or steering room agents.

## When to Use

- Human hands you an intent (build / fix / research something) that must be routed into the room
- You are about to spawn or steer Lead/Peer agents through Paseo MCP
- Human asks for room progress, or a Lead reports completion, a block, or a needed decision
- You are about to name or rename a room agent or workspace

## Topology (this user's room)

```
Human
  └── Supervisor        entry point, monitor, router - never implements
        ├── Lead Backend
        ├── Lead Frontend        one Lead PER DOMAIN, not one Lead total
        └── Lead Architecture     -> each Lead owns its own Peers
```

- **Supervisor**: frames the requirement + acceptance criteria (the product contract), dispatches to Lead(s), monitors, verifies claims against real state, relays progress/decisions to Human. Escalate to Human only when work is genuinely blocked or a decision exceeds authority (push/merge to remote, delete data, change product scope or the contract).
- **Lead**: analyzes, decides the approach, freezes the internal contract (`docs/CONTRACT.md`), splits bounded outcomes, dispatches Peers, reviews every artifact, integrates, ACCEPTs/REJECTs. Lead owns contract/docs files, not product code.
- **Peer**: exactly one bounded write scope (typically 1 module + its own test file) in its own worktree/branch. Commits locally, never pushes, never edits another peer's files or the README.

## Naming (user-mandated)

`<Role> <Domain> — <project/scope>`:

| Item | Example |
|---|---|
| Supervisor | `Supervisor — webapp + api` |
| Lead | `Lead Backend — webapp`, `Lead Frontend — webapp` |
| Peer | `Peer Backend — storage`, `Peer Backend — cli` |
| Workspace (repo checkout) | `webapp — REST API (Python)` |
| Worktree workspace | `peer/storage — JSON read/write + path resolution` |

Never invent suffixes like `(room demo 2)`. Rename with `mcp__paseo__rename_workspace` / `mcp__paseo__update_agent` when names drift.

## Dispatch rules

- A **wave** is the set of independent scopes dispatched together. Create **all** worktrees + agents of the wave in one assistant turn, then end the turn and await events.
- One MCP command per `tool_call`, but **all of them in the same turn**. Creating one agent, waiting for its finish, then creating the next serializes the wave — the #1 failure seen in practice.
- One owner per moving scope. Shared files (`cli.py`, `README.md`, the contract) are single-writer and belong to a later wave, sequenced after the modules they depend on.
- Greenfield scope whose imports do not exist yet: brief the peer to add a **local untracked stub** for imports/tests and `git add` only its own files.
- Pass an explicit `settings.modeId` when the caller mode cannot be inherited (`cannot inherit mode ... pass an explicit mode`).
- Retry a failed `create_workspace`/`create_agent` **inside the same turn**; a silent skip retried later turns parallelism into serialism.

## Review loop (Lead's duty — Supervisor verifies it happened)

For every finished peer, before integration, the Lead must read the artifact itself (`git log`, `git show <candidate>` in that worktree) and check: reported hash matches `git log`; diff touches only the allowed files; logic matches the contract; stdlib only; README untouched; a README acceptance criterion without a test is a **review failure**.
Corrections go to the **same** peer on the **same** branch via `send_agent_prompt` (file:line, wrong behaviour, pass condition), and the loop repeats until nothing needs changing. Only then: merge `--no-ff` per accepted branch in dependency order, run the full suite on `main` from the repo root, and run a **real** end-to-end smoke test with real output. Nothing is accepted on the peer's word or on "tests green".

## Supervisor duties (this seat)

- Verify every claim against live state: `git log --format='%h %cI %s'` on the branches (timestamps prove or disprove parallelism), `git worktree list`, `paseo agent ls --json` for full agent ids/status, and run the acceptance command yourself before reporting success.
- When Human asks for progress, read live state first and answer with numbers: integrated x/y, tests n/n on main, review rounds per scope, what is in flight, blockers. Never guess or repeat the Lead's prose.
- Intervene **through the Lead** with specific corrections; never do the product work yourself (the anti-pattern is "Supervisor implements instead of Lead").
- Report format: `scope | peer id | candidate commit | review rounds | test on main | verdict`, plus per-peer start/end timestamps proving overlap, the smoke-test command + output, residual risk, and an explicit "Human decisions needed" line.

## Paseo MCP gotchas

- A `tool_call` with local MCP tools rejects batches of >1 — one command per invocation.
- Agent-scoped calls create **subagents**; pass `workspaceId` explicitly to place a Lead in a repo workspace. `list_agents` shows only top-level agents — use `paseo agent ls --json` (CLI) for the full inventory with full ids.
- Worktrees live under `~/.paseo/worktrees/<id>/peer-<scope>`; run main-suite commands from the repo root, never from a worktree.
- `paseo daemon reload` applies `~/.paseo/config.json` changes (provider entries) without a restart; `features.*` needs a restart, and a restart kills running agents — never restart while a room run is active.
- ⚠️ Installing the **codex-room-setup** repo (Codex seats) *replaces* `~/.paseo/config.json` wholesale and links `~/.local/bin/paseo`: snapshot the config first, because it drops the operator's `hermes-supervisor/lead/peer` providers and agent profiles. Only do it when the user actually wants Codex seats — this user wants Hermes seats.

## References

- `references/briefs.md` — brief skeletons for Supervisor -> Lead and Lead -> Peer.
