# Widening a serialized shape under a scoped brief

Class: adding a field to a dataclass/model that round-trips through JSON — `from_dict` /
`to_dict`, CSV export, printed JSON, `--json` CLI output. The change itself is small; the
risk is entirely in the assertions and consumers you did not grep for.

## Blast radius first

Run these before editing, from the repo root:

```bash
git log --oneline -3 && git status --short          # baseline: branch, clean tree
grep -rn "to_dict()\|from_dict(" --include=*.py .    # every consumer
grep -rn "sorted(\(.*keys()\|sorted(data\[0\]\)" --include=*.py .   # key-set assertions
grep -rn "'created_at'\|\"created_at\"" --include=*.py tests/       # hand-written full-dict literals
```

The third and fourth patterns are the ones that bite: a test that asserts a whole dict
literal, or a sorted key list, or a printed JSON schema, encodes the OLD shape and goes red
the moment `to_dict` emits a new key — usually in a test module another peer owns.

Then run the brief's mandated command to record a green (or not) baseline.

## Printed text output is a second shape to grep

The same field addition usually changes the human-readable line too, and those lines are
pinned by exact-string assertions scattered across modules — invisible to the key-set greps
above:

```bash
grep -rn 'stdout, "' --include=*.py tests/              # exact-output assertions
grep -rn "def _format\|def format_" --include=*.py .   # the formatter and every caller
```

- One formatter helper is typically shared by several subcommands, so a single edit ripples to
  every exact-string assertion of every command that prints a task, and to `search`/`list`
  aliases you never opened.
- The pre-change code plus one existing assertion are the spacing authority; the brief's
  example is illustrative and collapses adjacent spaces. Append new segments to the existing
  line rather than reassembling the line from pieces.
- Assertions carry the terminator the command's `print()` adds — match the whole string,
  newline included, when you check the old goldens still hold.

## Implementation rules that make migration safe

- New fields go **last**, with defaults. Positional construction elsewhere keeps working.
- `from_dict`: absent **or** null → the default. Missing new fields must never raise; only an
  explicitly present invalid value raises.
- `to_dict`: always emit every key, `None` for a null optional, so consumers can index
  without `.get()`.
- Validate enum-ish strings as `isinstance(v, str) and v in VALID` — plain `v in {"a","b"}`
  raises `TypeError` (not the contracted `ValueError`) when JSON handed you a list or dict,
  because unhashable values are not even lookupable in a set.
- Leave one old-format test behind: a dict with none of the new keys must still load.

## When the Outcome is unreachable

The brief can require both "always emit the new key" and "existing tests unchanged" while an
existing test asserts the old shape exactly. That is a spec contradiction, not a puzzle to
solve cleverly. Resolve in this order:

| Situation | Action |
|---|---|
| Stale assertion lives in a file you MAY edit, and the brief says ADD tests only | Report it; the minimal edit is the owner's call unless the brief explicitly allows amending that assertion |
| Stale assertion lives in a forbidden file | Report `file:line` + the one-line fix; do not edit |
| Contract doc and brief disagree | The contract doc (Lead-owned, versioned in-repo) governs the code shape; the brief's Outcome governs the report |
| Nothing resolves it | Ship the contract-correct candidate commit, report the contradiction in RISK, ask which side yields |

Never satisfy the gate with a type whose `__eq__` ignores the extra keys, or by weakening
the assertion in a forbidden file. Report the failure verbatim instead — a visible red with
a named minimal fix is what unblocks the peer who owns the stale assertion.
