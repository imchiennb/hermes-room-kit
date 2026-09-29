# Contributing

Thanks for looking. This kit is small on purpose: shell + one Python script, no build step, no runtime dependencies beyond `bash`, `git`, `python3`.

## The one rule that matters most

**The machine running the room is the source of truth for the skills and profiles.** Seat skills get improved *while agents work* (they patch their own skill files when they hit a new pitfall). So:

```bash
bash scripts/capture.sh        # pull profiles/, skills/, paseo/room.fragment.json from the live machine
git diff                       # read it
git add -A && git commit
```

If you hand-edit a skill in the kit, run the room, and later `capture.sh`, your edit is gone. Either edit the live copy (recommended) and capture, or edit the kit copy and remember to re-install to the machine.

`README.md`, `docs/`, `install.sh`, `verify.sh` and `scripts/` are the opposite: they are authored here, and `capture.sh` never touches them.

## Before you push

```bash
bash scripts/selftest.sh                     # must end with "0 failed"
for f in install.sh verify.sh scripts/*.sh; do bash -n "$f" || echo "FAIL $f"; done
python3 -m py_compile scripts/merge_paseo_config.py
```

CI runs `scripts/selftest.sh` on Linux. On a runner without Hermes installed, `verify.sh` is invoked with `--allow-missing-hermes` (the kit's logic is still fully exercised; only "is Hermes on PATH" is downgraded to a warning).

## Conventions

- **Languages:** `README.md` and skills are in English (the seats read the skills; README is for strangers). `docs/ONBOARDING.md` and `docs/OPERATIONS.md` are in Vietnamese. Keep new docs in one of those, not a third.
- **Commits:** conventional prefixes (`feat:`, `fix:`, `docs:`, `chore:`), imperative subject, no trailing period. Say *why* in the body when the change is not obvious.
- **Shell:** `set -euo pipefail` (or `-uo` where you must tolerate failures), `bash -n` clean, no GNU-only flags you cannot justify, quote expansions.
- **Anything destructive defaults to read-only.** `room-cleanup.sh` lists; `--apply` removes. `merge_paseo_config.py` prints; `--dry-run` is supported and install.sh prefers it. A script that removes something must print exactly what it removed and write a backup of anything it overwrites.
- **Absolute paths for artifacts.** Peer/lead harnesses and generated reports use absolute paths; relative paths break the moment a script `cd`s into a repo.
- **Never commit:** `baselines/`, `state/`, `.env`, `*.tar.gz`, `*.bak-*` (all gitignored).
- **Never print secrets.** Scripts may read a key to pass it along; they must not echo it.

## Adding a script

Required: a `-h/--help` that shows the usage header, a read-only default for anything that mutates, and a mention in the `Scripts` table in `README.md`. If it needs a second machine to be useful, say so in the doc instead of pretending.

## Reporting a bug or a room failure

The useful report contains: the command you ran, its **raw output**, `bash verify.sh` output, and — for room failures — the exact agent ids plus their `[createdAt, updatedAt]` from `get_agent_status`. Claims without an artifact are the thing this kit exists to prevent, so please do not file them here either.

## Scope

In scope: install/verify/onboarding/ops ergonomics, the seat contracts, the skills that encode dispatch + review discipline, and honest documentation of limits.

Out of scope: changes that only make sense for one private project (put them in that project's `docs/`), and anything that turns a human decision (push, production data, dependency changes) into an automated one.
