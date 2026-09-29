# Operations — running and maintaining the room

Machine-level operations. The *workflow* (who does what) lives in the skills the kit installs; this file is about keeping the installation healthy.

## Where everything lives

| Path | What | Safe to delete? |
|---|---|---|
| `~/.hermes/profiles/{supervisor,lead,peer}/{config.yaml,AGENTS.md}` | seat definition + role contract | no (the kit restores them) |
| `~/.hermes/profiles/*/.env` | per-profile API keys (secret scope is per profile — `~/.hermes/.env` is NOT inherited) | no |
| `~/.hermes/profiles/*/skills/<cat>/<name>/` | room skills | no |
| `~/.hermes/profiles/{WORKFLOW.md,PROMPT_TEMPLATES.md}` | shared room contract | no |
| `~/.hermes/profiles/*/{state.db,sessions,memories,cron}` | runtime state | only when resetting a seat (carry it with `carry-state.sh` first) |
| `~/.paseo/config.json` | daemon config: provider entries + agent profiles | no — back it up before touching |
| `~/.paseo/worktrees/<id>/<slug>` | one git worktree per peer | yes, via `scripts/room-cleanup.sh` |
| `~/.paseo/agents/`, `~/.paseo/daemon.log` | agent bookkeeping + daemon log | the log rotates itself |

## Applying config changes

- Provider entries / agent profiles changed in `~/.paseo/config.json` → **`paseo daemon reload`** (live, does not kill agents). `install.sh` tries this when a `paseo` CLI is present.
- Anything under `features.*`, or when no `paseo` CLI exists → **restart Paseo Desktop**. That **kills every running agent** — never mid-run.
- Hermes profile changes (`config.yaml`, `AGENTS.md`, skills) take effect on the seat's **next** session; a running agent keeps the instructions it loaded.

## Cleaning up after runs

```bash
bash scripts/room-cleanup.sh --repo /path/to/repo            # inventory only
bash scripts/room-cleanup.sh --repo /path/to/repo --apply    # remove provably-safe ones
```
It only touches worktrees under `~/.paseo/worktrees/`, only those with a clean tree whose branch is already merged into the repo's base branch, and prints everything else as `KEEP` with the reason. Run it while the room is idle — an agent whose cwd is a removed worktree breaks.

Agents are separate: archive them from the Paseo UI or via `mcp__paseo__archive_agent` (soft delete, history kept) rather than `kill_agent` (ends the session). `hermes worktree` audits Hermes' own worktrees — a different set.

## Keeping the kit in sync with the machine

```bash
bash scripts/capture.sh      # re-snapshot profiles, skills, Paseo fragment from the live machine
git diff && git commit
```
Improve a skill on the machine → capture → commit. Never edit only the kit copy (or only the live copy) and forget the other.

## Reverting / uninstalling

```bash
# 1. remove the room from the Paseo config (foreign providers preserved, backup written)
python3 scripts/merge_paseo_config.py --fragment paseo/room.fragment.json --config ~/.paseo/config.json --remove
# 2. optionally delete the seats themselves
hermes profile delete supervisor -y    # repeat for lead, peer
# 3. or restore an earlier config
ls ~/.paseo/config.json.bak-*
```
`install.sh` never overwrites a differing `~/.paseo/config.json` entry without `--force`, and always writes a timestamped backup first.

## Moving state to another machine

`hermes profile export/import` currently fails on these profiles (`Unsupported archive member type` — the archives contain symlinks). Use:

```bash
bash scripts/carry-state.sh capture --with-history --with-secrets   # old machine
bash scripts/carry-state.sh restore --with-history --with-secrets   # new machine, after install.sh
```
Carries `memories/`, `cron/`, `hooks/`, `plugins/`, `SOUL.md`, and optionally a consistent `state.db` snapshot + `.env`. Keep the resulting `state/` out of git.

## Troubleshooting (every one of these happened for real)

| Symptom | Cause | Fix |
|---|---|---|
| `cannot inherit mode … Pass an explicit mode` on `create_agent` | parent provider differs from the child's | always pass `settings: {"modeId": "dont_ask"}` |
| `tool_call` rejected with a schema error | more than one local MCP call in one `tool_call`, or `title` > 60 chars | one MCP call per invocation; shorten titles |
| A "parallel" wave that actually ran serially | agents created one per turn instead of all in one turn | dispatch every worktree+agent of the wave in the same turn; prove overlap with `[createdAt, updatedAt]` from `get_agent_status` |
| Peer worktree has no `node_modules` | fresh worktree; installing dependencies is heavy | symlink the main checkout's `node_modules` (and `.env`) into the worktree, or install inside it |
| A peer starts the app on the host while the project runs in Docker | execution environment never agreed up front | agree it before dispatch; run everything through `docker exec` / `docker cp` |
| `npm run lint` rewrites hundreds of files | the script contains `--fix` | read the script before briefing; run the linter read-only for a baseline |
| Agent reports "done" without evidence | claim with no artifact | review gate: raw output on disk at an absolute path + a negative control + a "not proven" list |
| `paseo agent ls` shows relative times (`just now`) | the CLI summary truncates timestamps | use `get_agent_status` for exact `createdAt`/`updatedAt` |
| `hermes profile export/import` fails | symlinks inside the archive | use `scripts/carry-state.sh` |

## Health check

```bash
bash verify.sh                              # install assertions on this machine
bash scripts/selftest.sh                    # proves the kit itself (temp root, nothing real touched)
curl -s http://127.0.0.1:6767/api/health    # daemon liveness
```
