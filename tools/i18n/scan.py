"""Scan in-scope files for player-facing strings.

A finding is one place the game hands text to a player, with the exact character span needed
to rewrite it. There are two shapes and they cover every UI sink:

- **a literal** becomes `L.t(slug, "the literal")`;
- **an expression** (a variable, a call) becomes `L.t(<expression>)`, which resolves a content
  slug and is a no-op for anything else, so wrapping an expression is always safe.

A display `const`/`var` holding text becomes `var NAME := L.t(...)`: a `const` may not call a
function, so the keyword changes and each prose literal in the initializer is wrapped. The
English stays at the call site in every case, so nothing needs a catalog to read correctly.

A `.tscn` literal or an authored `.tres` field cannot call a helper, so those are inventoried
and left for a later wave — see the ADR.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from . import policy
from .catalog import unescape

## A GDScript string literal, escapes included. The alternation handles `\"`.
STRING_LIT = re.compile(r'"(?:[^"\\]|\\.)*"')

## The resolver call, for finding literals already wrapped (idempotence).
_LT_CALL = re.compile(r"L\.t\(")

_GD_ASSIGN = re.compile(
    r"\.(?P<prop>" + "|".join(policy.TEXT_PROPERTIES) + r")\s*(?<![=!<>])=(?!=)\s*(?P<rhs>.+?)\s*$"
)
_GD_DECL = re.compile(
    r"^(?P<indent>\s*)(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?P<kw>const|var)\s+(?P<name>[A-Za-z_]\w*)\s*(?::[^=]*?)?\s*=\s*(?P<rhs>.+)$"
)
_GD_FUNC = re.compile(r"^\s*(?:static\s+)?func\s+(?P<name>[A-Za-z_]\w*)")
_GD_RETURN = re.compile(r"^\s*return\s+(?P<rhs>.+?)\s*$")
_USE2 = re.compile(r'L\.t\(\s*"(LOC_[^"]+)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)')
_USE1 = re.compile(r'L\.t\(\s*"(LOC_[^"]+)"\s*\)')
_TRES_ROW = re.compile(
    r'^\s*"?(?P<field>'
    + "|".join(policy.CONTENT_FIELDS)
    + r')"?\s*[:=]\s*"(?P<lit>(?:[^"\\]|\\.)*)"'
)
_TSCN_ROW = re.compile(
    r"^\s*(?P<prop>" + "|".join(policy.TEXT_PROPERTIES) + r')\s*=\s*"(?P<lit>(?:[^"\\]|\\.)*)"'
)

## Kinds carrying a literal (they get a slug and a catalog row).
LIT_KINDS = frozenset({"gd_prop_lit", "gd_return_lit", "gd_const_lit"})
## Kinds the tool rewrites. `gd_const_kw` is the `const` -> `var` keyword change.
REWRITABLE = LIT_KINDS | {"gd_prop_expr", "gd_const_kw"}


@dataclass
class Finding:
    """A player-facing sink and how to rewrite it."""

    rel: str
    line: int
    start: int
    end: int
    english: str
    prefix: str
    catalog: str
    kind: str


@dataclass
class Use:
    """An `L.t` call already in the source, for the catalog consistency check."""

    rel: str
    line: int
    key: str
    english: str


@dataclass
class Unsupported:
    """A display sink the tool will not rewrite (a continued or unbalanced expression)."""

    rel: str
    line: int
    reason: str


@dataclass
class Scan:
    findings: list[Finding]
    uses: list[Use]
    unsupported: list[Unsupported]
    migrated: bool  # the file already contains at least one `L.t(` call


def decode(raw: str) -> str:
    """Decode GDScript escapes in a literal body to the text a player sees."""
    return unescape(raw)


def _comment_index(line: str) -> int:
    """Index of the first `#` outside a string, or `len(line)` when there is none."""
    in_string = False
    escaped = False
    for index, char in enumerate(line):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "#":
            return index
    return len(line)


def _balanced(expr: str) -> bool:
    """Whether every bracket in `expr` closes, ignoring brackets inside strings."""
    depth = 0
    in_string = False
    escaped = False
    for char in expr:
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0 and not in_string


def _wrappable(expr: str) -> bool:
    """Whether an expression RHS can be wrapped in `L.t(...)` without breaking syntax."""
    stripped = expr.strip()
    if not stripped or STRING_LIT.fullmatch(stripped):
        return False
    if re.fullmatch(r"-?\d+(?:\.\d+)?", stripped) or stripped in ("true", "false", "null"):
        return False
    if stripped.startswith(("L.t(", "tr(", "tr_n(")):
        return False
    if not _balanced(stripped):
        return False
    # A trailing operator means the expression continues on the next line, which a
    # line-based wrap cannot see; leave it for a human.
    return stripped[-1] not in "+-*/%&|,:("


def _initializer_span(text: str, index: int) -> int:
    """The exclusive end of the initializer that starts at `index` (brackets balanced)."""
    depth = 0
    in_string = False
    escaped = False
    cursor = index
    while cursor < len(text):
        char = text[cursor]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
            if depth == 0:
                return cursor + 1
        elif char == "\n" and depth == 0:
            return cursor
        cursor += 1
    return len(text)


def scan_gd(rel: str, text: str, prefix: str, catalog: str) -> Scan:
    findings: list[Finding] = []
    uses: list[Use] = []
    unsupported: list[Unsupported] = []
    regions: list[tuple[int, int]] = []
    current_func = ""
    offset = 0
    line_no = 0
    for raw_line in text.splitlines(keepends=True):
        line_no += 1
        line_start = offset
        offset += len(raw_line)
        if policy.IGNORE_MARKER in raw_line:
            continue
        code = raw_line[: _comment_index(raw_line)]

        # Uses are collected before the region skip: a `const` dictionary's wrapped values
        # are uses too, and missing them would let `extract` prune live catalog rows.
        matched_func = _GD_FUNC.match(code)
        if matched_func:
            current_func = matched_func.group("name")
        for use in _USE2.finditer(code):
            uses.append(Use(rel, line_no, use.group(1), decode(use.group(2))))
        for use in _USE1.finditer(code):
            uses.append(Use(rel, line_no, use.group(1), ""))

        if any(start <= line_start < end for start, end in regions):
            continue
        _scan_assign(rel, line_no, line_start, code, prefix, catalog, findings, unsupported)
        _scan_decl(
            rel, line_no, line_start, code, text, prefix, catalog, findings, regions, unsupported
        )
        if policy.has_display_token(current_func):
            _scan_return(rel, line_no, line_start, code, prefix, catalog, findings)
    return Scan(findings, uses, unsupported, "L.t(" in text)


def _wrapped_spans(text: str, start: int, end: int) -> list[tuple[int, int]]:
    """Spans of every existing `L.t(...)` call in `[start, end)`, brackets balanced.

    A literal inside one is already translated; wrapping it again would nest the call. This
    is what makes `extract` idempotent.
    """
    spans: list[tuple[int, int]] = []
    for match in _LT_CALL.finditer(text, start, end):
        depth = 1
        cursor = match.end()
        while cursor < end:
            char = text[cursor]
            if char == '"':
                cursor += 1
                while cursor < end and text[cursor] != '"':
                    if text[cursor] == "\\":
                        cursor += 1
                    cursor += 1
            elif char in "([{":
                depth += 1
            elif char in ")]}":
                depth -= 1
                if depth == 0:
                    cursor += 1
                    break
            cursor += 1
        spans.append((match.start(), cursor))
    return spans


def _scan_assign(rel, line_no, line_start, code, prefix, catalog, findings, unsupported) -> None:
    match = _GD_ASSIGN.search(code)
    if match is None:
        return
    rhs = match.group("rhs")
    start = line_start + match.start("rhs")
    end = line_start + match.end("rhs")
    literal = STRING_LIT.fullmatch(rhs)
    if literal is not None:
        english = decode(literal.group(0)[1:-1])
        if policy.is_player_text(english):
            findings.append(
                Finding(rel, line_no, start, end, english, prefix, catalog, "gd_prop_lit")
            )
        return
    if rhs.strip().startswith(("L.t(", "tr(", "tr_n(")):
        return
    if _wrappable(rhs):
        findings.append(Finding(rel, line_no, start, end, "", prefix, catalog, "gd_prop_expr"))
    elif rhs.strip():
        unsupported.append(Unsupported(rel, line_no, rhs.strip()))


def _is_dict_key(text: str, end: int, limit: int) -> bool:
    """Whether the literal ending at `end` is a dictionary KEY (followed by `:`).

    A key is a lookup, not text: wrapping `"display_name"` in a `recipe.get(...)` call is the
    bug this exists to stop.
    """
    cursor = end
    while cursor < limit and text[cursor] in " \t":
        cursor += 1
    return cursor < limit and text[cursor] == ":"


def _scan_decl(
    rel, line_no, line_start, code, text, prefix, catalog, findings, regions, unsupported
) -> None:
    match = _GD_DECL.match(code)
    if match is None:
        return
    is_const = match.group("kw") == "const"
    # A `const` holding a prose literal is configuration wording (`UNWIRED_CLOCK`), whatever
    # its name — gate on the value, not the name. A local `var` is noisier (log strings,
    # scratch text), so it still needs a display token in its name.
    if not is_const and not policy.has_display_token(match.group("name")):
        return
    equals = code.find("=", match.end("name"))
    if equals < 0:
        return
    span_start = line_start + equals + 1
    span_end = _initializer_span(text, span_start)
    regions.append((line_start + match.start("kw"), span_end))
    wrapped = _wrapped_spans(text, span_start, span_end)
    literals: list[Finding] = []
    for literal in STRING_LIT.finditer(text, span_start, span_end):
        if _is_dict_key(text, literal.end(), span_end):
            continue
        if any(begin <= literal.start() and literal.end() <= stop for begin, stop in wrapped):
            continue  # already inside an L.t(...) call
        english = decode(literal.group(0)[1:-1])
        if policy.is_player_text(english):
            literals.append(
                Finding(
                    rel,
                    line_no,
                    literal.start(),
                    literal.end(),
                    english,
                    prefix,
                    catalog,
                    "gd_const_lit",
                )
            )
    if not literals:
        return
    if is_const and "static func" in text:
        # A `var` is not reachable from a `static func`, so `DomainOutcome.outcome_text`
        # reading its own `OUTCOME_TEXT` would stop compiling. Leave the const's wording
        # alone and report it; a human migrates the file (see the ADR's reader-side note).
        unsupported.append(
            Unsupported(rel, line_no, f"{match.group('name')} (const, file has a static func)")
        )
        return
    findings.extend(literals)
    if is_const:
        findings.append(
            Finding(
                rel,
                line_no,
                line_start + match.start("kw"),
                line_start + match.end("kw"),
                "",
                prefix,
                catalog,
                "gd_const_kw",
            )
        )


def _scan_return(rel, line_no, line_start, code, prefix, catalog, findings) -> None:
    match = _GD_RETURN.match(code)
    if match is None:
        return
    rhs = match.group("rhs")
    literal = STRING_LIT.fullmatch(rhs)
    if literal is None:
        return
    english = decode(literal.group(0)[1:-1])
    if not policy.is_player_text(english):
        return
    findings.append(
        Finding(
            rel,
            line_no,
            line_start + match.start("rhs"),
            line_start + match.end("rhs"),
            english,
            prefix,
            catalog,
            "gd_return_lit",
        )
    )


def _scan_rows(rel, text, prefix, catalog, kind, pattern) -> list[Finding]:
    findings: list[Finding] = []
    offset = 0
    line_no = 0
    for raw_line in text.splitlines(keepends=True):
        line_no += 1
        line_start = offset
        offset += len(raw_line)
        match = pattern.match(raw_line)
        if match is None:
            continue
        english = decode(match.group("lit"))
        if not policy.is_player_text(english):
            continue
        start = line_start + match.start("lit") - 1  # include the opening quote
        findings.append(
            Finding(
                rel,
                line_no,
                start,
                start + len(match.group("lit")) + 2,
                english,
                prefix,
                catalog,
                kind,
            )
        )
    return findings


def scan_tres(rel: str, text: str, prefix: str, catalog: str) -> Scan:
    return Scan(_scan_rows(rel, text, prefix, catalog, "tres_lit", _TRES_ROW), [], [], False)


def scan_tscn(rel: str, text: str, prefix: str, catalog: str) -> Scan:
    return Scan(_scan_rows(rel, text, prefix, catalog, "tscn_lit", _TSCN_ROW), [], [], False)


def scan_file(rel: str, text: str) -> Scan | None:
    kind = policy.scope_kind(rel)
    domain = policy.domain_of(rel)
    if kind is None or domain is None:
        return None
    if kind == "gd":
        return scan_gd(rel, text, domain.prefix, domain.catalog)
    if kind == "tres":
        return scan_tres(rel, text, domain.prefix, domain.catalog)
    return scan_tscn(rel, text, domain.prefix, domain.catalog)
