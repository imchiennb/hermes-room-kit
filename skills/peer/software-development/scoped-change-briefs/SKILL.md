---
name: scoped-change-briefs
description: Use when a brief scopes files, tests, and the commit.
version: 1.0.0
author: hermes-curator
license: MIT
metadata:
  hermes:
    tags: [git, worktree, cli, testing, handoff]
    related_skills: [test-driven-development, requesting-code-review]
---

# Scoped change briefs

A brief hands you: an Outcome (a command that must be green), a file allow-list and
forbid-list, contract invariants, test requirements, commit rules, and a required
response format. The deliverable is the committed change plus the brief's own test
command output, verbatim.

## When to Use

- A task arrives as a written brief with an Outcome, a files-allowed list, a
  files-forbidden list, and a mandated test command and/or response format.
- Work happens in a linked git worktree on a dedicated branch, and the commit is the
  handoff to another agent or to the user.
- You must add commands/endpoints to an existing dispatch surface without touching the
  modules around it.

## Procedure

1. **Read the real code before writing.** Load the entry point and every module the
   brief names (signatures, return shapes, mutation side effects). Load the existing
   test module for the same surface — its helper class is the pattern to copy.
2. **Run the brief's own test command before editing anything** and keep the output
   verbatim. A green baseline proves the Outcome was achievable at the base commit and
   tells the reviewer which failures you introduced versus which were already there;
   without it, a red report is unarguable either way. If you skipped the baseline,
   establish attribution by dependency trace instead of by stashing — see the pitfalls.
3. **Grep the whole tree for every consumer and assertion of the shape you are about to
   change** — not just the module the brief names. Widening a return shape goes red in
   exact-shape assertions living in files you are forbidden to touch. Recipe, patterns,
   and the decision table for an unreachable Outcome: `references/serialization-shape-changes.md`.
4. **Honor the boundary literally.** Only the allowed files change. Do not touch docs,
   README, or the forbidden tests even when the change "should" be documented, and do
   not modify modules the brief says are already correct. If an allowed file reveals a
   bug in a forbidden one, report it instead of fixing it.
5. **Extend the existing dispatch, don't restructure it.** Add new clauses in the same
   shape as the neighboring ones and reuse existing helpers rather than introducing a
   parallel path.
6. **Read-only commands stay out of the mutating set.** Anything that only reads must
   not be added to the save-trigger set; a read command that writes back is a silent
   data-loss bug.
7. **Write the e2e tests next.** Subclass the existing e2e base class and shell out to the CLI
   as a subprocess with every path pointed at a temp file — a new module when the suite has
   none, otherwise a new class appended to the existing e2e module, leaving its base class
   untouched. Put extra accessors (a `json_list()` wrapper, a raw-write fixture) inside your
   new class; when the shared base has no write helper, write the fixture directly with
   `pathlib.Path(self.path).write_text(raw, encoding="utf-8")` instead of adding a method to
   a base other agents' tests also use. See `templates/cli_e2e_test_skeleton.py`. Before writing the assertion literals, hand-run every new flag combination in the real environment and capture the bytes with `cat -v` — the brief's sample fragments assume one renderer, and the environment may resolve the optional-dependency branch instead. Flag placement, mode resolution, and renderer dispatch: `references/cli-output-mode-flags.md`.
8. **Run both commands the brief names, with no pipe**, then capture the full output for
   the report. Also run the whole suite once
   (`python3 -m unittest discover -s tests`) when the brief adds a new module — an
   import-visible name collision or a leaked helper shows up only there, and it is cheap
   evidence for RISK. Piping through a truncating shell utility hides the real exit code and
   cuts the exact text the brief wants reproduced — the tool already returns full output
   plus a saved-file path when it is long.
9. **Stage by explicit pathspec — name only the files on the allow-list.** A pathspec-less
   `git commit -am` cuts both ways: it silently omits untracked files the brief copied in,
   and it sweeps in whatever else is already dirty in the shared worktree — in a parallel
   wave that is another agent's in-flight edit to a file your brief forbids you to touch.
   Stage one path per allowed file (`git add a.py tests/test_a.py`) and leave the rest of
   the dirt alone. Confirm the file list with `git show --stat HEAD` after committing, and
   check the branch is right.
10. **Do not push** when the brief says the commit is the handoff. Report the hash.
11. **Answer in exactly the required format, including when blocked.** No preamble, no
    process narration, no summary of what you just did — the fixed fields, the verbatim
    test output (red included), and the contradiction or residual risk in RISK. Commit the
    contract-correct candidate even when the Outcome is unreachable: the branch is the
    handoff surface, the failure is visible in the output, and an unpushed commit is
    reversible — a stalled worktree with the work uncommitted blocks every peer who needs
    the new signature.

## Pitfalls

- **A touch-created empty file is not a "missing file" fixture.** Loaders commonly
  distinguish absent-file (→ empty list) from unparseable-file (→ error). Creating the
  fixture with an empty write makes every command exit 1 with a corrupt-file error.
  Reserve the path with `mkstemp` then `unlink` (or open and delete it immediately) and
  clean up with `addCleanup`; never leave an empty or truncated fixture behind.
- **Extend a text formatter by appending; never rebuild its line from the brief's example.**
  A brief's illustrative output (`[x] 1  buy milk  !high  due:2026-12-31  #tags`) does not
  disambiguate single from double spaces, and the existing exact-string assertions are the
  only authority on the real spacing. Reassembling the line from parts (e.g. `"  ".join(...)`)
  silently changes the leading separator and turns every exact-stdout assertion of that
  formatter red — including assertions in files you may not touch, and in other subcommands
  that share the same helper. Append (`line += "  " + segment`), copy the pre-change line's
  spacing verbatim, and rerun the FULL suite to confirm the old golden strings, not just the
  tests you added. When the brief also demands a NEW decorated mode (color/ANSI)
  beside the existing plain one, keep the plain branch as a literal copy of the old
  body and put all decoration in the other branch — a shared decorated builder that
  "looks the same" is what turns the pinned plain assertions red. Recipe for a
  plain-plus-ANSI render module, plus the optional-third-party-library variant:
  `references/ansi-render-modules.md`.
- **A brief that fixes both the dispatch rule and the exact table glyphs is only satisfiable
  if you know which branch the environment takes.** Routing a table format through a
  library-backed renderer degrades to plain lines whenever color is off — both the
  optional-library module and the stdlib search/stats helpers open with
  `if not color: return <plain>` — so the `┌ ┬ └` the brief asserts never appear for
  `--format=table` in a pipe, and `…` truncation lives only on the stdlib path. Settle this
  before writing assertions: check `importlib.util.find_spec("<lib>")` and read the
  `color=False` branch of EVERY candidate module. To keep table-shaped output in both color
  modes, call the table function with `color=True` and `strip_ansi()` the result when color
  is off (visible output is unchanged, because padding is measured after stripping), or
  route the colorless case to the stdlib box renderer. Then report the deviation from the
  brief's dispatch wording in RISK rather than weakening the assertion.
- **Measure decorated output with `strip_ansi`, never `len()` or a raw prefix.**
  The escape bytes count as characters, so colored cells padded by `len()` desync the
  frame, and an assertion written as `out.startswith("\u2714")` fails against a spec
  that emits `GREEN + "\u2714 " + msg` — the raw string starts with `\x1b[32m`. Assert
  `strip_ansi(out).startswith(glyph)` plus `assertIn(CODE, out)`, and run the width
  and prefix checks in both color modes.
- **`print()` appends the newline your test forgot.** If the command strips the payload
  before printing, the subprocess stdout still ends in `\n`. Assert the exact string
  including the terminator, or the expectation fails on the easiest test in the file.
- **Assert that `--file` was actually honored**, not just that the command works: point
  it at a second temp file holding different tasks and check the result matches that
  file. A path-resolution regression looks identical to a working command otherwise.
- **Be explicit about which reading path a filter takes.** Bare filters are
  single-value; `append` semantics differ (last wins vs. accumulate). Match the brief.
- **Check the exit-code contract per command**: 0 on success *including no matches*,
  1 on corrupt input, 2 on bad args. "No results" is a success, never an error.
- **Read-only means byte-identical.** Test it: read the input file before and after and
  compare. A save-on-read bug passes every output assertion.
- **A brief that mandates a wider output shape while forbidding edits to existing tests
  is self-contradictory** whenever some existing test asserts the old shape exactly
  (a full dict literal, a `sorted(d.keys())` list, a printed JSON schema). "Keep old tests
  green" and "always emit the new key" cannot both hold. Quantify it with `file:line` for
  every stale assertion, then decide whether the shape change or the assertion yields —
  and report which side is whose to fix. Do not "fix" assertions in files you are not
  allowed to touch, even to reach the Outcome.
- **Check who owns the stale assertion before assuming an oversight.** `git log --stat`
  and `git log -- <test path>` show whether the commit that changed the contract also
  updated its tests. If the contract's owner touched docs only, the stale assertion is
  theirs to amend; your report names the minimal edit and the owning file.
- **Never manufacture green with a type whose `__eq__` lies.** Returning a dict subclass
  that compares equal to a dict missing the new keys passes the gate and silently corrupts
  every future comparison for every consumer. Refusing the trick and reporting the
  contradiction is the cheaper engineering result.
- **Appending fields to a dataclass keeps positional construction working** only if the
  new fields carry defaults and go last; a default-less field in the middle breaks every
  existing `Cls(a, b, ...)` call site you did not grep for.
- **Widen the module's existing test factory helper; do not add a second one.** When new
  fields need fixtures, extend the existing `mk()`-style builder with defaulted kwargs
  (`def mk(id, title="t", ..., priority="medium", due=None)`) and give it a `created_at`
  parameter if the sort logic needs distinct values. Write it with explicit defaulted
  keyword parameters, not `**kwargs` over an internal dict — the dict widens every value
  to `int | str` and the language server then flags every construction site.
  A parallel helper reimplements the
  fixture shape and drifts from it, and defaulted kwargs keep every existing call site
  green with zero edits.
- **Attribute a failing shard before reporting it, and never by stashing.** In a shared
  worktree the tree is already dirty with parallel waves, so a failure inside a forbidden
  test file is usually not yours. `git status --short` names whose uncommitted edits are
  present; then `search_files` for the module's importers proves whether your change is on
  that code path at all (`from todo.service import` across `tests/`). Do not `git stash` to
  reconstruct a baseline — the stash is shared across linked worktrees and takes the peer's
  uncommitted work with it. Cross-checking the failure against the forbidden file's own
  `git log --stat` pins the owner.
- **Report the pre-existing failures by test ID, not as a count.** Enumerate them with the
  discover run and a `grep -E '^(FAIL|ERROR):'` filter, then name each in RISK with its
  file so the next wave knows what is theirs. Diagnostic pipes like this are fine; never
  pipe the gate command itself, since the exit code you receive is the pipeline's last
  command, not the test run's.
- **Stub a not-yet-merged sibling module as an UNTRACKED file, never stage it.** When
  the brief says your module imports a peer's module that lands in a later wave, write the
  minimal stub (public signatures returning an empty string) at the real path so imports
  resolve, and wrap the fallback import in its own `try/except ImportError` so the module
  still imports if the stub is ever absent. Keep it out of the commit: stage only the
  allow-listed paths, then confirm with `git show --stat HEAD` (exactly the allowed files)
  and `git status --short` (the stub still shows `??`). A `git add -A` sweeps the stub in
  and the peer's real module collides with it at merge.
- **Report residual risk honestly.** Non-atomic side writes, single-value filters, and
  similar deliberate simplifications belong in the RISK field; `none` is only truthful
  when nothing was skipped.

## Style

Deliver code through file edits, not code blocks in the reply. Keep the reply to the
brief's required fields. When the brief names a simplification ceiling, mark it in code
with a short comment naming the upgrade path.
