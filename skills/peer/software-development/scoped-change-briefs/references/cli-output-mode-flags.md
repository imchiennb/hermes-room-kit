# Output-mode flags (`--format` / `--color`) in a subcommand CLI

Use when a brief adds presentation flags to a CLI that already has subparsers:
where the flag lives, how the mode resolves, and which renderer branch runs.

## Where the flag lives in the parser

An argparse subparser sets its own default for every option it defines, so a value
parsed before the subcommand is clobbered: `cli --format=table list` silently becomes
`auto`. Define the flags once in a parent parser and attach it to every subparser,
with `default=argparse.SUPPRESS` on the parent copies and the real default declared on
the top-level parser. `SUPPRESS` means "do not set this attribute", so a value already
parsed at the top level survives, and an occurrence after the subcommand still wins.

```python
_COMMON = argparse.ArgumentParser(add_help=False)
_COMMON.add_argument("--color", choices=["auto", "always", "never"], default=argparse.SUPPRESS)
_COMMON.add_argument("--format", choices=["auto", "plain", "table", "json"],
                     default=argparse.SUPPRESS, dest="fmt")

p = argparse.ArgumentParser(prog="todo")
p.add_argument("--color", choices=["auto", "always", "never"], default="auto")
p.add_argument("--format", choices=["auto", "plain", "table", "json"], default="auto", dest="fmt")
sub = p.add_subparsers(dest="cmd", required=True)
sub.add_parser("list", parents=[_COMMON], help="list tasks")
```

Test all three placements: flag before the subcommand, flag after it, and the same
option given twice (the later occurrence wins).

## Resolving the mode

- Resolve once in `main` — a `bool` for color and a concrete mode string for format —
  and pass both into the dispatch function. Do not scatter `sys.stdout.isatty()`
  through the command branches.
- `auto` → decorated/table when stdout is a TTY, plain otherwise. Non-TTY is the normal
  case under a subprocess test harness, which is exactly why `--format=auto` must equal
  today's plain output: that is what keeps the pre-existing golden assertions green.
- An alias flag (`--json`) wins over `--format`; read it with
  `getattr(args, "json", False)` because only some subparsers define it.
- `never` is absolute: if a mode promises "no ANSI", no branch may emit an escape.
  Assert `"\033" not in out` on every such path — a decorated path that merely looks
  plain still fails it, and this is the check that catches a renderer picked for table
  shape rather than for color.
- A fixed-format command (CSV export) must ignore the flag; test that the flag does not
  change its output.

## Dispatching to the renderer

- Pick the renderer in ONE helper and give it the color decision, not just library
  availability: a library module whose `color=False` branch returns plain lines cannot
  produce a table, so colorless table/stat/search output has to come from the stdlib
  renderer. Check `importlib.util.find_spec("<lib>")` and read both branches.
- When a module only box-draws in color mode, call its table function with `color=True`
  and `strip_ansi()` the string when color is off. Cell padding is computed on stripped
  text, so the visible layout is identical to a colorless render, and `never` still
  holds. Keep the ANSI strip in the same helper as the call so every table path inherits
  it.
- Plain modes never need the library: `line(t, False)` is byte-identical across the
  modules by contract.
- Rendering a message for a mutating command is a one-line change per call site; keep
  the command's exit-code path (errors to stderr, `if msg:` guard for empty output)
  untouched.

## Probe before asserting

Hand-run each new flag combination and read the bytes before writing assertions:
`run --format=table | cat -v` shows escapes, and a box-drawing glyph differs per
renderer and per color mode. Assert the glyph set of the branch the environment
actually takes (`┌ ┬ └` stdlib vs the library's own box), plus one shared invariant
that holds in both (`STATUS` header present, `"\033[" in out` when color is forced).
Omitted truncation fixtures are the other trap: `…` only appears when a title exceeds
`max_width`, so seed a title longer than the limit instead of assuming.
