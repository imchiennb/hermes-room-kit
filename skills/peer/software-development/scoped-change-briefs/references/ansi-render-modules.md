# Plain/ANSI render modules

Use when a brief asks for a new render module that must keep a plain
(no-escape-byte) output byte-identical to an existing formatter while adding a
`color: bool` mode — lines, box tables, stats bars, messages.

## Structure

- One stdlib-only module. Import the domain types; never import the CLI module
  you are mirroring (that is what the plain-branch equality is for).
- Each public function branches `if not color: <plain> return ...` FIRST, with the
  colored path after it. The plain branch is the existing formatter's body copied
  segment by segment (`line += "  " + seg`), never re-derived from the brief's
  prose — the pinned golden string is the authority on spacing and markers.
- One cell builder per table column returning text that may carry ANSI, so plain
  and colored rows share a single layout path.

## Measuring widths

- Length of a colored cell is `len(strip_ansi(cell))`, where
  `strip_ansi = re.sub(r'\x1b\[[0-9;]*m', '', s)`. Escape bytes count as
  characters in `len()` and silently desync the frame.
- Derive each column width from the FINAL cell strings
  (`max(len(header[i]), *(len(strip_ansi(r[i])) for r in rows))`), not from the raw
  task fields, so replacing a cell (highlight, em dash) cannot desync it.
- Frame width with `│ cell │` cells and `│` separators is
  `sum(widths) + 3 * ncols + 1`; build the top/mid/bottom border rows from the same
  widths so header, data, and borders match exactly.
- Uniformity test that actually bites: assert
  `len({len(strip_ansi(line)) for line in out.splitlines()}) == 1`, run in BOTH
  color modes.

## Truncation

Compute `fixed = sum(widths) - title_w + 3 * ncols + 1`, `room = max_width - fixed`;
if `room < title_w`, cut every title to `room - 1` characters plus `…` and set the
column width to `room`. Clamp the limit to `>= 2` so the ellipsis always fits, and
assert the longest line is `<= max_width` after stripping escapes.

## Colors

- Empty cell (no due, no tags) → em dash in both modes, so the frame never has a
  blank-looking hole.
- Highlight a query BEFORE widths are computed, splicing
  `BOLD + YELLOW + match + RESET` from `re.finditer(re.escape(q), text, re.IGNORECASE)`;
  measure afterwards via `strip_ansi`.
- Guard the date math: `date.fromisoformat(due)` can raise on a malformed string,
  and the urgency comparison is against `date.today()` — a `None`/parse-failure
  path falls back to the uncolored cell rather than crashing the whole table.

## Assertions against a decorated spec

A spec written as `CODE + "\u2714 " + msg + RESET` means the raw string STARTS with
the escape, not the glyph. Assert `strip_ansi(out).startswith("\u2714")` and
separately `assertIn(CODE, out)`. The same trap applies to any "starts with …"
check once a mode adds decoration. Test both modes for every function that takes
`color`; the plain path is what the rest of the suite pins.

## Optional-dependency variants (rich)

Use when the module renders through a third-party library when importable and falls
back to the stdlib renderer otherwise, while the plain branch stays byte-identical.

- Guard every library import in ONE module-top `try/except ImportError` that sets the
  `*_AVAILABLE` flag, and put the fallback import in its own `try/except ImportError`
  (`_fallback = None`) so the module still imports before the peer's module merges.
  Delegate through one helper — `getattr(_fallback, name, None)` with the native plain
  string as the default — so a missing fallback returns a string instead of raising.
- Branch on `if not color` BEFORE touching the library. A contract pinning
  `render_table(tasks, False) == "\n".join(plain_line(t) for t in tasks)` fails when the
  plain call runs through a library table; the plain branch is the stdlib path.
- Return `""` for an empty list before building any renderable.
- Capture with `Console(file=io.StringIO(), force_terminal=color, width=W).print(obj)`,
  then `rstrip("\n")` for single-line returns. Pass `width` explicitly (from
  `max_width` for tables): with `force_terminal=True` and no TTY the console falls back
  to 80 columns and wraps cells you did not expect. Library tables that ellipsize column
  overflow by default need no hand-written truncation.
- `rich.box.SIMPLE_HEAVY` draws heavy horizontals with NO vertical rule, so a test
  asserting `"│" in out or "─" in out` fails on it. `HEAVY_HEAD` has both characters.
- Gating: `@unittest.skipUnless(RICH_AVAILABLE, ...)` on every test that calls the
  library path, but leave the `import module` test and the flag-is-bool test UNGATED —
  they are the only proof the module imports on a machine without the dependency.
- Probe the degraded branch instead of uninstalling: install an import hook raising
  `ImportError` for the package name and its prefix, purge it from `sys.modules`, then
  import the module and assert the flag plus one return type is `str`. Run that as a
  scratch script; a script outside the repo does not get the repo root on `sys.path`, so
  insert it explicitly.
- Highlighting splits a token: building the cell with a library text object by splitting
  the title on the query emits `Buy ` then a styled `milk`, so `assertIn("Buy milk", out)`
  fails against correct code. Assert the fragments (`"Buy"`, `"milk"`) plus the style
  escape code.
