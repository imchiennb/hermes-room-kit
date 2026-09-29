# hermes-room-kit

[![selftest](https://github.com/imchiennb/slp-hermes-setup/actions/workflows/selftest.yml/badge.svg)](https://github.com/imchiennb/slp-hermes-setup/actions/workflows/selftest.yml)

A portable **seat-based agent room** for coding work: one human, one **Supervisor**, N **Lead** seats split by domain, and **Peer** seats that each own exactly one bounded write scope.

It runs on [Paseo](https://paseo.sh) (UI + daemon + agent orchestration) and [Hermes Agent](https://hermes-agent.nousresearch.com) (the agent runtime behind each seat). This kit installs the room onto a machine, and turns any project — brand new or five years old — into a room-shaped workstream.

> **Tóm tắt (tiếng Việt):** máy mới → `bash install.sh` → điền API key vào 3 file `.env` → `bash verify.sh`. Dự án mới hay cũ → `bash scripts/onboard-project.sh /path/to/project --run-tests` → mở `brief-*.md`, dán khối text vào ghế **Supervisor**. Chi tiết: [`docs/ONBOARDING.md`](docs/ONBOARDING.md) (tiếng Việt).

---

## Why this shape

Multi-agent setups usually fail for boring reasons: two agents editing one file, a "done" claim with no artifact behind it, a wave everyone calls parallel that actually ran serially, or an agent starting the app on the host while the project only runs in Docker.

The kit encodes the fixes as *seat contracts* and *gate rules*, not vibes:

- **One owner per moving scope.** Every Peer works in its own git worktree + branch; shared files (`cli.py`, `README.md`, the contract) are single-writer and land in a later wave.
- **A wave is dispatched in one turn.** All worktrees + all agents of a wave are created in the same assistant turn, then the dispatcher waits for events. Parallelism is *proved* with the `[createdAt, updatedAt]` intervals from the agent daemon — never inferred from commit times.
- **Review is a gate, not a formality.** The Lead reads the artifact itself (`git show`, the harness, the raw output) and sends corrections back to the **same** Peer on the **same** branch until nothing needs changing. A verdict without captured raw output is a review failure.
- **The Supervisor never implements.** It verifies claims against live state (git log, worktree list, the acceptance command it runs itself) and reports numbers to the human.
- **The human owns the irreversible.** Push, merge to the real branch, production data, scope changes, new dependencies.

## Architecture

```
Human  ──asks/decides──▶  Supervisor        (routes, monitors, verifies, reports; never codes)
                             │
                             ├── Lead Backend ──────┬── Peer ──▶ one worktree + branch + one scope
                             ├── Lead Frontend ─────┴── Peer ──▶ one worktree + branch + one scope
                             └── Lead Architecture  └── Peer ──▶ one worktree + branch + one scope
                                        │
                                        └── reviews every artifact, integrates, ACCEPTs/REJECTs
```

One Lead per domain, not one Lead total. A single-domain project uses one Lead.

## What the kit installs

| Item | Where it lands | What it is |
|---|---|---|
| 3 Hermes profiles | `~/.hermes/profiles/{supervisor,lead,peer}/` | seat config (`config.yaml`) + role contract (`AGENTS.md`) + a `.env` template |
| Shared room contract | `~/.hermes/profiles/{WORKFLOW.md,PROMPT_TEMPLATES.md}` | the rules every seat reads at session start |
| 3 room skills | `~/.hermes/profiles/*/skills/…` | `paseo-room-supervisor` (supervisor), `paseo-lead-orchestration` (lead), `scoped-change-briefs` (peer) — the accumulated operating knowledge |
| Paseo provider + agent profiles | merged into `~/.paseo/config.json` | `hermes-supervisor` / `hermes-lead` / `hermes-peer` entries that launch `hermes acp --profile <seat>` |

`install.sh` **merges** into `~/.paseo/config.json` — foreign providers and daemon settings are preserved, and a timestamped backup is always written first. Wholesale replacement of that file is a known way to silently delete someone's seats (the `codex-room-setup` installer does exactly that, plus it links `~/.local/bin/paseo`); this kit never does.

## Requirements

- **Hermes Agent** installed and on `PATH` (`hermes --version`). Developed against v0.21.x.
- **Paseo Desktop** (AppImage/dmg) — it spawns the daemon at `127.0.0.1:6767`. Optional for `install.sh`, but this is where agents actually run. The optional `paseo` CLI (`@getpaseo/cli`) makes config reloads and agent listings easier.
- `bash`, `git`, `python3`.
- **An LLM provider key.** The shipped profiles are configured for a SwiCloud-compatible endpoint (`SWICLOUD_API_KEY`); point them at any OpenAI-compatible provider — hosted or local — as described in [`docs/PROVIDERS.md`](docs/PROVIDERS.md). Give the three seats different models on purpose: the strongest coding model on the **Lead** seat, a cheap fast one on **Peer**.

## Quickstart — install on a machine

```bash
# 1. Hermes + Paseo Desktop installed, Paseo opened once so the daemon exists

# 2. get the kit (clone, scp, zip — it is ~300 KB)
git clone <this repo> hermes-room-kit && cd hermes-room-kit

# 3. install (idempotent; --dry-run prints without writing)
bash install.sh

# 4. put your API key in each seat's .env
#    ~/.hermes/profiles/{supervisor,lead,peer}/.env  →  SWICLOUD_API_KEY=...
#    (secrets are per-profile; ~/.hermes/.env is NOT inherited by a profile)

# 5. verify
bash verify.sh          # expect: "20 passed, 0 failed"
```

Then open Paseo Desktop: the **Supervisor / Lead / Peer** agent profiles are listed.

To prove the kit itself works without a second machine:

```bash
bash scripts/selftest.sh     # installs into a throwaway root, checks idempotency + the revert path
```

## Use it on a project

```bash
bash scripts/onboard-project.sh /path/to/project --run-tests
```

It auto-detects whether the project is **new** (no git / no remote / young history) or **long-running** (remote, history, CI) — printing its evidence, so you can override with `--mode`. It writes `baselines/baseline-*.md` (git state, the project's *real* test command, the baseline result, repo shape, CI, existing rules) and `baselines/brief-*.md` — a paste-ready brief for the Supervisor seat plus the four things you must decide first.

The two modes differ in exactly the ways that matter:

| | **New project** | **Long-running project** |
|---|---|---|
| Product contract | Supervisor writes `README` (scope, acceptance, constraints) and commits the base | Supervisor reconciles acceptance against the existing repo — it does not rewrite history |
| Acceptance | suite green **including a real end-to-end test** + a real smoke run | **no regression**: the same pre-existing failures stay failing; new behaviour gets new tests, old tests are never edited |
| Integration | merge to the repo's default branch (nobody depends on it yet) | merge to an integration branch `room/<task-slug>`; the human merges/pushes for real |
| Parallelism | many peers (independent modules) | fewer peers — only genuinely independent files; never fake-split |
| Main risk | scope creep | breaking something that already runs (schema, style, dependencies, the dev environment) |

Full guide: [`docs/ONBOARDING.md`](docs/ONBOARDING.md).

### Agree the execution environment first

Before any peer runs anything, settle this with the human — it is the most common way a wave goes wrong:

- Are host commands allowed at all? Many projects run **only in Docker**: the app may already be running in dev mode in a container, so a peer must never start a server or run `npm`/`node` on the host. Valid tools are `docker exec` / `docker cp` against the existing containers; `docker compose up/down/restart` is off-limits.
- Which container serves the app, on which internal port, and what does it mount? If it mounts `src/` from the main checkout, then a peer's worktree **is not what runs**, and writing to that mounted `src/` hot-reloads the human's live environment.
- Where may test data be written? Peers tag it, clean up, and prove residuals are zero.

## Update the kit from the machine that runs it

```bash
bash scripts/capture.sh     # re-snapshot profiles, skills and the Paseo fragment from the live machine
git diff && git commit
```

Improve a skill where you actually use it, then capture. Do not let the kit copy and the live copy drift apart.

## Scripts

| Script | Purpose |
|---|---|
| `install.sh` | install/refresh the room on this machine (`--dry-run`, `--force`, custom `--root`/`--paseo-home` for testing) |
| `verify.sh` | assert the install is real: files, contracts, keys present, Hermes lists the profiles, Paseo providers/profiles, daemon liveness |
| `scripts/selftest.sh` | prove the kit itself: installs into a throwaway root, checks idempotency, runs `verify.sh`, checks the revert path |
| `scripts/onboard-project.sh` | one entrypoint for any project: detect new/existing, write baseline + paste-ready Supervisor brief |
| `scripts/onboard-repo.sh` | the raw baseline report (git state, real test command, suite result, repo shape, CI, lint traps) |
| `scripts/room-cleanup.sh` | inventory the worktrees a room leaves behind; `--apply` removes only clean+merged ones |
| `scripts/capture.sh` | snapshot the live room back into the kit (profiles, skills, Paseo fragment) |
| `scripts/carry-state.sh` | move seat state (memories, cron, hooks, optionally `state.db` + `.env`) to another machine |
| `scripts/merge_paseo_config.py` | merge — or with `--remove`, revert — the room's Paseo entries; never touches foreign providers |

## Repo layout

```
install.sh · verify.sh · README.md · LICENSE · CONTRIBUTING.md
profiles/{supervisor,lead,peer}/{config.yaml,AGENTS.md}
profiles/shared/{WORKFLOW.md,PROMPT_TEMPLATES.md}
skills/{supervisor,lead,peer}/<category>/<skill>/{SKILL.md,references,templates}
paseo/room.fragment.json          # the provider + agent-profile entries to merge
scripts/…                         # see the table above
docs/{ONBOARDING.md,OPERATIONS.md,PROVIDERS.md}
.github/workflows/selftest.yml    # the kit's own CI (must stay green)
baselines/                        # generated per project (gitignored)
```

## Security and secrets

- The kit never copies secrets or runtime state. `.env` files are written as **empty templates**; keys are per-profile and stay on the machine.
- `scripts/carry-state.sh` includes `.env` only with the explicit `--with-secrets` flag; its output lands in `state/`, which is gitignored. Move it over `scp`/USB, then delete it.
- The room never pushes to a remote. Push, merges to protected branches, production data operations and dependency changes are human decisions, always.
- Evidence rule for reviews: raw output on disk at an absolute path, a negative control, and an explicit "not proven" list — a green test suite alone is not proof of a working feature.

## What this kit does not do

- It does not install Hermes or Paseo, and it cannot create a "second machine" proof for you — `selftest.sh` covers the kit's own logic, not a fresh OS.
- It does not carry session history or memories by default (that is the opt-in `carry-state.sh`).
- It does not create CI. Verification is a gate the seats run, plus `selftest.sh` for the kit.
- `hermes profile export/import` is currently unusable with these profiles (the archives contain symlinks → `Unsupported archive member type`); `carry-state.sh` is the working path.

## Troubleshooting

`docs/OPERATIONS.md` has the full list (mode-inheritance errors, `tool_call` batching limits, the serial-wave trap, missing `node_modules` in worktrees, the `lint --fix` rewrite trap, exact agent timestamps). The short version:

```bash
bash verify.sh                                # is the install real?
bash scripts/selftest.sh                      # is the kit itself sound?
curl -s http://127.0.0.1:6767/api/health      # is the daemon alive?
```

## Language

`README.md` is in English for portability; `docs/ONBOARDING.md` and `docs/OPERATIONS.md` are in Vietnamese (the language this room was operated in). Skill files are in English because the seats read them.

## License

MIT — see [`LICENSE`](LICENSE).
