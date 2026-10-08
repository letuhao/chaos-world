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
## Any `LOC_…` literal is a USE, however it is held: `L.t(key)` at a sink, a bare
## `const X := "LOC_…"` that a reader resolves, or a key in a format's arguments. A key
## nothing references is an orphan, and matching only the wrapped form called every
## const-held key one — which `extract` would then prune while the source still used it.
_USE_ANY = re.compile(r'"(LOC_[A-Z0-9_]+)"')
## A CONSTANT-shaped identifier: the name a keyed `const` is spelled with.
_KEYED_ARG = re.compile(r"(?<![\w.])[A-Z][A-Z0-9_]*")
_TRES_ROW = re.compile(
    r'^\s*"?(?P<field>'
    + "|".join(policy.CONTENT_FIELDS)
    + r')"?\s*[:=]\s*"(?P<lit>(?:[^"\\]|\\.)*)"'
)
_TSCN_ROW = re.compile(
    r"^\s*(?P<prop>" + "|".join(policy.TEXT_PROPERTIES) + r')\s*=\s*"(?P<lit>(?:[^"\\]|\\.)*)"'
)

## Kinds carrying a literal (they get a key and a catalog row).
LIT_KINDS = frozenset({"gd_prop_lit", "gd_return_lit", "gd_const_key"})
## Kinds the tool rewrites. `gd_const_key` leaves a `const` a `const` holding a bare KEY; the
## reader resolves it, because a `var REASON_TEXT` is a `class-variable-name` lint error.
REWRITABLE = LIT_KINDS | {"gd_prop_expr", "gd_format_expr"}


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
    ## Filled in by `extract` when it assigns a stable key. Empty on a read-only scan, and
    ## never re-derived from the text — see `catalog.assign_key`.
    key: str = ""


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


def _in_comment(text: str, position: int) -> bool:
    """Whether `position` falls inside a `#` comment on its own line.

    A declaration's initializer SPAN crosses lines for a dict or array, so the span scan can
    reach a literal written inside a COMMENT below it — a quoted English word in prose. Keying
    that corrupts the comment and mints a row nothing derives, so it is checked here.
    """
    start = text.rfind("\n", 0, position) + 1
    return position >= start + _comment_index(text[start:])


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
    ## The consts THIS file holds a bare KEY in, so a `return CONST` can be seen as the leak it is.
    keyed: set[str] = set()
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
        for use in _USE_ANY.finditer(code):
            uses.append(Use(rel, line_no, use.group(1), ""))

        if any(start <= line_start < end for start, end in regions):
            continue
        _scan_assign(rel, line_no, line_start, code, prefix, catalog, findings, unsupported, keyed)
        _scan_decl(
            rel,
            line_no,
            line_start,
            code,
            text,
            prefix,
            catalog,
            findings,
            regions,
            unsupported,
            keyed,
        )
        if policy.has_display_token(current_func):
            _scan_return(rel, line_no, line_start, code, prefix, catalog, findings, keyed)
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


def _format_operator(rhs: str) -> int:
    """Index of the `%` that makes `rhs` a format expression, or -1.

    The operator is the `%` OUTSIDE any string (a `%` inside the message is a placeholder) and
    not a `%%` escape. That is what separates `"%s x%d" % [a, b]` from a plain literal.
    """
    in_string = False
    escaped = False
    index = 0
    while index < len(rhs):
        char = rhs[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "%" and (index + 1 >= len(rhs) or rhs[index + 1] != "%"):
            return index
        index += 1
    return -1


def _key_format(rel, line_no, base, rhs, prefix, catalog, kind, findings, keyed) -> bool:
    """Key a `%`-format expression: its MESSAGE literal and every prose literal in ARGUMENTS.

    `"%s - %s" % [fact, "heard" if ok else "not yet"]` holds three messages — the template and
    the two argument words — so keying only the leading literal would ship English inside an
    otherwise translated line. Returns True when `rhs` IS a format expression. The message is
    keyed only when it is a bare literal, so an already-migrated `L.t(key) % […]` keys just its
    remaining argument wording.
    """
    operator = _format_operator(rhs)
    if operator < 0:
        return False
    message = STRING_LIT.fullmatch(rhs[:operator].strip())
    if message is not None:
        english = decode(message.group(0)[1:-1])
        if policy.is_player_text(english):
            findings.append(
                Finding(rel, line_no, base, base + message.end(), english, prefix, catalog, kind)
            )
    else:
        # `CONST % args` where CONST holds a KEY: a key is not a template, so the format would
        # run on `LOC_…` and raise. Resolving the head first is the only correct rewrite.
        head = rhs[:operator].strip()
        offset = rhs.index(head) if head else 0
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*", head) and not head.startswith(policy.RESOLVER):
            findings.append(
                Finding(
                    rel,
                    line_no,
                    base + offset,
                    base + offset + len(head),
                    "",
                    prefix,
                    catalog,
                    "gd_format_expr",
                )
            )
    arguments = rhs[operator + 1 :]
    offset = base + operator + 1
    wrapped = _wrapped_spans(arguments, 0, len(arguments))
    for literal in STRING_LIT.finditer(arguments):
        if any(begin <= literal.start() and literal.end() <= stop for begin, stop in wrapped):
            continue
        english = decode(literal.group(0)[1:-1])
        if not policy.is_player_text(english):
            continue
    # A CONST the file holds a KEY in, used as an ARGUMENT, is a message fragment too:
    # `"%s %s" % [LABEL, UNEARNED]` renders both slugs unless each is resolved first.
    for token in _KEYED_ARG.finditer(arguments):
        if token.group(0) not in keyed:
            continue
        if any(begin <= token.start() and token.end() <= stop for begin, stop in wrapped):
            continue
        findings.append(
            Finding(
                rel,
                line_no,
                offset + token.start(),
                offset + token.end(),
                "",
                prefix,
                catalog,
                "gd_format_expr",
            )
        )
    return True


def _scan_assign(
    rel, line_no, line_start, code, prefix, catalog, findings, unsupported, keyed
) -> None:
    match = _GD_ASSIGN.search(code)
    if match is None:
        return
    rhs = match.group("rhs")
    start = line_start + match.start("rhs")
    end = line_start + match.end("rhs")
    if _key_format(rel, line_no, start, rhs, prefix, catalog, "gd_prop_lit", findings, keyed):
        return
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
    rel, line_no, line_start, code, text, prefix, catalog, findings, regions, unsupported, keyed
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
    # The initializer begins at the character after `=`, which is a SPACE in `x := "…"`. The
    # format rule addresses offsets from `base`, so the base must advance past that whitespace or
    # the rewrite eats the wrong character (it left a stray quote and broke `LootValidator`).
    initializer = text[span_start:span_end]
    lead = len(initializer) - len(initializer.lstrip())
    initializer = initializer.lstrip()
    span_start += lead
    # A FORMAT is never a bare key: `"Short on %s" % args` holds placeholders, so replacing the
    # message with `"LOC_…"` would raise, and a `const` cannot call `L.t` (a const value must be a
    # constant expression). A const format is therefore left alone and reported; a `var` one is
    # resolved by the same rule the sinks use.
    if _format_operator(initializer) >= 0:
        if not is_const and policy.has_display_token(match.group("name")):
            _key_format(
                rel,
                line_no,
                span_start,
                initializer,
                prefix,
                catalog,
                "gd_prop_lit",
                findings,
                keyed,
            )
        elif not is_const:
            unsupported.append(Unsupported(rel, line_no, "a local format in a non-display name"))
        return
    wrapped = _wrapped_spans(text, span_start, span_end)
    literals: list[Finding] = []
    for literal in STRING_LIT.finditer(text, span_start, span_end):
        if _is_dict_key(text, literal.end(), span_end):
            continue
        if _in_comment(text, literal.start()):
            continue  # a quoted word in a comment is prose about the code, not a sink
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
                    # A `const` cannot hold a RESOLVED value without losing its name to a `var`
                    # (`class-variable-name` forbids `var REASON_TEXT`), so it holds the bare
                    # KEY; a `var` resolves at the declaration, exactly as a sink does.
                    "gd_const_key" if is_const else "gd_prop_lit",
                )
            )
    findings.extend(literals)
    # Only a const whose VALUE IS A KEY belongs in `keyed`: the set drives a rule that wraps a
    # keyed const where it is used, and an ordinary constant (`SCHEMA_VERSION`) wrapped in `L.t`
    # does not compile.
    if is_const and re.fullmatch(r'\s*"LOC_[A-Z0-9_]+"\s*', initializer):
        keyed.add(match.group("name"))


def _scan_return(rel, line_no, line_start, code, prefix, catalog, findings, keyed) -> None:
    match = _GD_RETURN.match(code)
    if match is None:
        return
    rhs = match.group("rhs")
    start = line_start + match.start("rhs")
    if _key_format(rel, line_no, start, rhs, prefix, catalog, "gd_return_lit", findings, keyed):
        return
    # A helper that returns a const holding a KEY hands a slug to its caller, whose `summary()`
    # then publishes it. The scanner knows the file's keyed consts, so this is visible.
    if rhs.strip() in keyed:
        findings.append(
            Finding(
                rel,
                line_no,
                start,
                line_start + match.end("rhs"),
                "",
                prefix,
                catalog,
                "gd_prop_expr",
            )
        )
        return
    literal = STRING_LIT.fullmatch(rhs)
    if literal is not None:
        english = decode(literal.group(0)[1:-1])
        if policy.is_player_text(english):
            findings.append(
                Finding(
                    rel,
                    line_no,
                    start,
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


_TRES_ID = re.compile(r'^id\s*[:=]\s*&?"(?P<id>[^"]+)"', re.MULTILINE)
## A display field whose value is a bracketed LIST (`Array[String](["a", "b"])`). Each element
## is a string a player reads — a composed persona picks one — so each gets its own key.
_TRES_ARRAY = re.compile(
    r"^[ \t]*\"?(?P<field>"
    + "|".join(policy.CONTENT_FIELDS)
    + r")\"?[ \t]*[:=][ \t]*(?:Array\[[^\]]*\][ \t]*\()?\[(?P<items>[^\]]*)\]",
    re.MULTILINE,
)


def _token(value: str) -> str:
    """A key fragment: upper-case, non-alphanumeric runs collapsed to `_`."""
    return re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_").upper() or "X"


def _line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _lines(text: str):
    """`(line_no, offset, line)` triples, so a match position maps to a file offset."""
    offset = 0
    for line_no, line in enumerate(text.splitlines(keepends=True), start=1):
        yield line_no, offset, line
        offset += len(line)


def scan_tres(rel: str, text: str, prefix: str, catalog: str) -> Scan:
    """Find every player-facing `.tres` field and give it an EXPLICIT, readable key.

    The game's data holds the KEY, not the English (`display_name = "LOC_ITEMS_X_NAME"`), and
    one def is defined once for every language. The key derives from the def's own `id` (or the
    file stem when it has none) plus the field name — stable across an English edit, which is
    the whole point — and an index for a repeated field or a list element.
    """
    ident = _TRES_ID.search(text)
    stem = rel.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    token = _token(ident.group("id")) if ident else _token(stem)
    uses: list[Use] = []
    collected: list[tuple[int, int, int, str, str]] = []  # start, end, line, key_field, value

    # A bracketed list is scanned first: its elements own indexed field names, so the
    # single-string pass must skip their lines rather than read the array opener as a value.
    array_spans: list[tuple[int, int]] = []
    for match in _TRES_ARRAY.finditer(text):
        field = match.group("field").upper()
        base = match.start("items")
        index = 0
        for literal in STRING_LIT.finditer(match.group("items")):
            value = decode(literal.group(0)[1:-1])
            if value.startswith(policy.SLUG_PREFIX):
                uses.append(Use(rel, _line_of(text, base + literal.start()), value, ""))
                continue
            if not policy.is_player_text(value):
                continue
            index += 1
            # `items` starts just after the `[`, and a STRING_LIT match INCLUDES its quotes,
            # so the span is the literal itself — no `- 1` (that is for `_TRES_ROW`, whose
            # capture excludes the quotes).
            found = base + literal.start()
            collected.append(
                (
                    found,
                    base + literal.end(),
                    _line_of(text, found),
                    f"{field}_{index}",
                    value,
                )
            )
        array_spans.append((match.start(), match.end()))

    for line_no, line_start, raw_line in _lines(text):
        if any(start <= line_start < end for start, end in array_spans):
            continue
        match = _TRES_ROW.match(raw_line)
        if match is None:
            continue
        value = decode(match.group("lit"))
        if value.startswith(policy.SLUG_PREFIX):
            # Already migrated: the field holds the KEY, so this is a reference to resolve.
            uses.append(Use(rel, line_no, value, ""))
            continue
        if not policy.is_player_text(value):
            continue
        start = line_start + match.start("lit") - 1  # include the opening quote
        collected.append(
            (
                start,
                start + len(match.group("lit")) + 2,
                line_no,
                match.group("field").upper(),
                value,
            )
        )

    counts: dict[str, int] = {}
    for _start, _end, _line, field, _value in collected:
        counts[field] = counts.get(field, 0) + 1
    seen: dict[str, int] = {}
    findings: list[Finding] = []
    for start, end, line, field, value in collected:
        seen[field] = seen.get(field, 0) + 1
        key = f"{policy.SLUG_PREFIX}_{prefix}_{token}_{field}"
        if counts[field] > 1:
            key = f"{key}_{seen[field]}"
        findings.append(Finding(rel, line, start, end, value, prefix, catalog, "tres_lit", key))
    return Scan(findings, uses, [], False)


def scan_tscn(rel: str, text: str, prefix: str, catalog: str) -> Scan:
    """A `.tscn` literal is always inventoried, but only a SCREEN/PANEL scene is a rewrite target.

    A `src/ui` scene's owner script runs `L.localize_tree` in `_bind_nodes`, so a key in the
    scene resolves at display. An app-owned scene under `game/scenes/` has no script at all, so
    a key there would draw as its own key — it stays inventoried (`tscn_app_lit`) and unrewritten
    until that scene's owner calls the pass.
    """
    under_ui = rel.replace("\\", "/").startswith("game/src/ui/")
    kind = "tscn_lit" if under_ui else "tscn_app_lit"
    # A key already in the scene is a USE: the owner's `L.localize_tree` pass resolves it, so
    # `check` must see it or it would prune a row the tree still reads.
    uses: list[Use] = []
    for line_no, _start, line in _lines(text):
        for match in _USE_ANY.finditer(line):
            uses.append(Use(rel, line_no, match.group(1), ""))
    return Scan(_scan_rows(rel, text, prefix, catalog, kind, _TSCN_ROW), uses, [], False)


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
