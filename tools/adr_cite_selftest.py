"""Red-path self-tests for `tools adr-cite`.

A guard shipped in Python is unreachable from the GDScript suite, so nothing asserts
it still goes RED unless its cases are loaded here (INC-0016). This is the case module
`tools/__main__.py` imports for that reason, beside `data_selftest` and
`new_adr_selftest`.

## What each case proves

Not "the checker passes on today's tree" — `tools check` already does that, and it
proves nothing. Each case builds a throwaway tree with one deliberately wrong citation
in it and asserts a non-zero verdict:

- a citation whose LINE exists but whose named symbol does not (the exact shape the
  existence-only audit scored 0/86 on)
- a citation past the end of a shorter file
- a citation naming a file that is not in the tree
- a citation that is fine, asserted to stay green so the cases above cannot pass
  against a checker that fails everything
- a WAIVED citation, which must stop failing — and a waiver that names the wrong
  symbol must NOT cover a second claim citing the same line, or the baseline table is
  blanket suppression wearing a ledger's clothes.

No case edits the repository: every fixture is a temp directory, and the real
`docs/adr/` is never the subject.
"""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
from collections.abc import Iterator
from pathlib import Path

from . import adr_cite
from .selftest import case, expect, write

# A fixture module, long enough that a citation past its end is a real finding rather
# than an off-by-one in the test.
_FIXTURE_MODULE = "\n".join(
    [
        "extends RefCounted",
        "",
        "",
        "## A docstring that mentions `earn_fate` in prose.",
        "##",
        "## Real decision point.",
        "static func earn_oath(actor: Actor) -> bool:",
        "\treturn true",
        "",
    ]
)

_FIXTURE_ADR = """# 0001 Fixture

- Status: Accepted
- Date: 2026-01-01

## Decision

- The earn happens at `fixture.gd:6 earn_oath`. Verified by reading the line.
"""


@contextlib.contextmanager
def _quiet() -> Iterator[None]:
    """Swallow the checker's output so the harness reads only verdicts."""
    sink = io.StringIO()
    with contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink):
        yield


@contextlib.contextmanager
def _tree(adr_body: str, waivers: dict | None = None) -> Iterator[Path]:
    """A temp repo holding one fixture module and one ADR citing it."""
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        write(root / "game/src/modules/fixture.gd", _FIXTURE_MODULE)
        write(root / "docs/adr/0001-fixture.md", adr_body)
        original_waivers = dict(adr_cite.WAIVERS)
        if waivers is not None:
            adr_cite.WAIVERS.clear()
            adr_cite.WAIVERS.update(waivers)
        try:
            yield root
        finally:
            adr_cite.WAIVERS.clear()
            adr_cite.WAIVERS.update(original_waivers)


def _verdict(root: Path, adr: Path) -> int:
    """The gate's own exit code, through the STRICT path.

    `report` is report-only by default (DEF-0285: a permanently red gate is a gate
    nobody reads), so the cases assert the exit code CI actually gates on.
    """
    return adr_cite.report(adr_cite.audit(adr.parent, root), as_json=False, strict=True)


@case("adr-cite: a citation whose line exists but names nothing there STILL fails")
def _right_line_wrong_symbol_fails() -> None:
    """The shape the existence-only audit scored 0 of 86 on.

    The cited line is real and in range, and `earn_oath` is nowhere within the checker's
    ±3 tolerance window of it — the tolerance is the design (a decision that moved a line
    or two is not drift), so the case points far enough away that only a content check
    can tell this apart from a correct citation. An existence-only checker passes it.
    """
    body = _FIXTURE_ADR.replace("fixture.gd:6 earn_oath", "fixture.gd:1 earn_oath")
    with _tree(body) as root, _quiet():
        code = _verdict(root, root / "docs/adr/0001-fixture.md")
    expect(
        code != 0,
        "a citation pointing at a line whose whole ±3 window holds nothing passed; line "
        "EXISTENCE is the check that cannot fail, and this is the drift it misses",
    )


@case(
    "adr-cite: a correct citation stays GREEN, so the red cases are not a checker "
    "that fails everything"
)
def _correct_citation_passes() -> None:
    with _tree(_FIXTURE_ADR) as root, _quiet():
        code = _verdict(root, root / "docs/adr/0001-fixture.md")
    expect(
        code == 0,
        "the ADR's own correct citation (`fixture.gd:6 earn_oath`) was reported as drift, "
        "so every red case above would have passed against a checker that rejects all "
        "citations rather than the wrong ones",
    )


@case("adr-cite: a citation past the end of a shorter file fails")
def _line_past_eof_fails() -> None:
    body = _FIXTURE_ADR.replace("fixture.gd:6", "fixture.gd:9000")
    with _tree(body) as root, _quiet():
        code = _verdict(root, root / "docs/adr/0001-fixture.md")
    expect(
        code != 0,
        "a citation 9000 lines into an 8-line file was accepted; a line that does not "
        "exist cannot hold the claim an ADR makes for it",
    )


@case("adr-cite: a citation naming a file that is not in the tree fails")
def _missing_file_fails() -> None:
    body = _FIXTURE_ADR.replace("fixture.gd:6 earn_oath", "no_such_file.gd:6 earn_oath")
    with _tree(body) as root, _quiet():
        code = _verdict(root, root / "docs/adr/0001-fixture.md")
    expect(
        code != 0,
        "an ADR citing a file that does not exist passed the checker; DEF-0231/0232 "
        "recorded two ADRs citing a test file that was never created, which is the "
        "cheapest citation to make wrong and the one nothing else catches",
    )


@case("adr-cite: a waiver stops a finding, but only for the symbol it names")
def _waiver_is_scoped_to_its_symbol() -> None:
    """A baseline table that covers anything is blanket suppression.

    Two claims cite the SAME drifted line with DIFFERENT symbols. Only one is waived,
    so a waiver that ignored the symbol would silence both — and the table would have
    become the quiet lie this tool exists to replace.
    """
    body = _FIXTURE_ADR.replace("fixture.gd:6 earn_oath", "fixture.gd:4 earn_fate")
    waivers = {"0001": (("fixture.gd:4", "earn_fate", "immutable"),)}
    with _tree(body, waivers) as root, _quiet():
        waived_code = _verdict(root, root / "docs/adr/0001-fixture.md")

    body_other = _FIXTURE_ADR.replace("fixture.gd:6 earn_oath", "fixture.gd:4 unrelated_name")
    with _tree(body_other, waivers) as root, _quiet():
        other_code = _verdict(root, root / "docs/adr/0001-fixture.md")

    expect(
        waived_code == 0,
        "an explicitly waived citation still failed, so the tool cannot record a moving "
        "line and every future one has to be re-edited into an immutable ADR",
    )
    expect(
        other_code != 0,
        "a waiver for `earn_fate` silenced a DIFFERENT symbol citing the same line; the "
        "waiver table has become blanket suppression and every finding is now optional",
    )


@case("adr-cite: a citation with no symbol beside it is COUNTED as unchecked, never as ok")
def _unchecked_is_not_ok() -> None:
    body = _FIXTURE_ADR.replace("`fixture.gd:6 earn_oath`", "`fixture.gd:6`")
    with _tree(body) as root:
        findings = adr_cite.audit(root / "docs/adr", root)
        verdicts = {f.verdict for f in findings}
        with _quiet():
            code = adr_cite.report(findings, as_json=True)
    expect(
        "unchecked" in verdicts and "ok" not in verdicts,
        "a citation naming no code identifier was graded `ok`; existence is not "
        "verification, and counting it as verified is how 86 drifted citations reported "
        "as clean",
    )
    expect(
        code == 0,
        "an `unchecked` citation failed the gate; it must be counted and reported, not "
        "fatal, because a bare `file:line` with no symbol is legitimate prose",
    )


@case("adr-cite: the shipped waiver table is well formed and inside its budget")
def _waiver_table_is_sound() -> None:
    """The table is hand-maintained, so it is the one part with no guard on it.

    An unknown reason code would raise at the first matching citation and take the
    whole gate down; a table past its budget is the ADR one-page cap arriving through
    the side door. Both are checked here rather than trusted.
    """
    entries = [
        (adr, citation, symbol, reason)
        for adr, rows in adr_cite.WAIVERS.items()
        for citation, symbol, reason in rows
    ]
    unknown = sorted({reason for *_, reason in entries if reason not in adr_cite.REASONS})
    expect(not unknown, f"waiver reasons not in REASONS: {', '.join(unknown)}")
    expect(
        len(entries) <= adr_cite.MAX_WAIVER_LINES,
        f"the waiver table holds {len(entries)} entries against a budget of "
        f"{adr_cite.MAX_WAIVER_LINES}; a baseline nobody can read stops being a "
        "reviewed record and becomes a list of known wrongs",
    )
    counted = sum(len(rows) for rows in adr_cite.WAIVERS.values())
    expect(
        counted == len(entries),
        "the waiver table has entries this checker cannot parse, so part of it is "
        "never reached and silently suppresses nothing",
    )


@case("adr-cite: --json reports the failing citations machine-readably")
def _json_report_names_the_findings() -> None:
    """`check` consumes this. A summary string a caller has to re-parse is not one."""
    body = _FIXTURE_ADR.replace("fixture.gd:6 earn_oath", "fixture.gd:9000")
    with _tree(body) as root:
        findings = adr_cite.audit(root / "docs/adr", root)
        sink = io.StringIO()
        with contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink):
            code = adr_cite.report(findings, as_json=True, strict=True)
    text = sink.getvalue()
    # The JSON is one indented block; the fail/warn lines follow it, so the payload is
    # extracted by braces rather than by parsing the whole sink (the tool's contract is
    # "the JSON block is in the output", not "the output is only JSON").
    payload = json.loads(text[text.index("{") : text.rindex("}") + 1])
    expect(code != 0, "a past-EOF citation passed the JSON report path")
    expect(
        any(f["verdict"] == "line_past_eof" for f in payload["findings"]),
        "the JSON report printed no finding for a citation 9000 lines past the end of "
        "an 8-line file, so a caller reading it would conclude the tree is clean",
    )
