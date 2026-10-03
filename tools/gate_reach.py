"""Can the authored world ever satisfy the gate it declares? A content census.

`game/data/event/` shipped eighteen `requires` rows, twelve of which carry a count
(six are an opening stage's empty `requires`), and two of the twelve asked for a fact
twice when the authored tree produces it exactly once. Both ladders were dead:
`EventApi.advance` offers a stage's `on_enter` beats ONCE, on entry
(`api.gd:332`), and while a stage holds it returns before re-firing them
(`api.gd:275`), so `need: 2` on a fact one beat supplies is unsatisfiable by
construction. Every gate validated clean, because nothing compared a demand with
what the content offers. That is the gap this module closes.

## The question, stated so it can be answered mechanically

The world's memory is ONE monotone ledger, `WorldFact` (ADR 0113). A fact demand is
`{verb: fact, id, need}` in an event `trigger` or stage `requires`, and
`{fact, need}` on a quest step. A fact is supplied only by a BEAT - an
`{fact, amount}` row in some event's opening `on_enter` or a stage's `on_enter` -
offered through `EventBeatWriter`, the only writer inside the event module.

So the whole question is arithmetic: **for every fact demand, is the demand at or
below the total amount every authored beat in the tree offers for that fact?**

## Why the ceiling is content plus a scanned code constant, and why that is a fact

`WorldFact.record` is the only verb that writes the ledger. It has three call sites
in `res://src`: `EventBeatWriter.offer` (event_beat_writer.gd), which takes
`beat["fact"]`; `BeatDirector.offer` (beat_director.gd), which takes `WorldBeat.fact`;
and `app/character_creation_flow.gd`, which takes a `const FACT_ID` it declares
itself. The first two read an id out of a value a `.tres` authored. The third is a
CODE-OWNED producer - `&"character_created"` exists nowhere in `game/data` - so
`census()` reads `res://src` as well and counts it. Content alone would have been a
ceiling with a hole in it, and a `.tres` demanding `character_created` would have
been reported dead while the game supplied it.

Both halves of that claim are pinned in code rather than asserted here:
`game/tests/arch_rules/test_fact_ledger_writers.gd` fails the build on a FOURTH
`WorldFact.record` call site in `res://src`, and on any call site that passes a fact
id as a literal rather than reading one out of a value object or a same-file `const`.
When it fires, this census has to be taught the new producer - in the same change,
not later.

## What it still cannot see, said out loud

Four things, because a validator with unstated blind spots reads as an all-clear:

1. **A producer assembled at run time.** `code_owned_supply` resolves a `const` in the
   same file and nothing else: an id built by arithmetic (`"killed_" + species`), or
   read out of a payload, is deliberately NOT counted, because inventing a supply
   figure is how a census starts lying. If a gate is ever reported dead while
   `gate_reach report` shows no producer for the fact, this is the first thing to
   check.
2. **A save written by another build.** `WorldFact.normalize_payload` drops rows it
   cannot read, and a hand-edited save can carry any count. The census models the
   authored ceiling, which is the right thing to gate on and the wrong thing to treat
   as "the ledger can never hold more".
3. **Requirements this module does not model.** Only `fact` is read. `has_fate`,
   `has_destiny`, `counter` and `declare` are `destiny`'s and `sect`'s to answer;
   their supply is a different ledger and this census says nothing about it. Measured
   on 2026-10-03, four of the five fate/destiny demands in content have no producer,
   which is the same defect in the next ledger and is NOT counted here.
4. **Every ledger that is not `world_facts`.** `DestinyState` counters
   (`{verb: counter, id, need}`, read by `DestinyGate._counter`), sect standing, and
   npc tallies are separate monotonic stores with their own producers. DEF-0168
   already records that a fate naming a counter nothing increments refuses silently;
   this module deliberately does not grow a second model of them.

Two consequences worth stating rather than hiding:

- **A fact no authored beat produces is reported as `unbacked_demand`, and it is a
  hard failure by default.** It is not a softer finding than a contradiction: with
  the writer set above, zero supply means the gate can never open, full stop. The
  two classes differ in the REMEDY (a content edit versus a missing producer), not in
  whether they are dead. `--allow-unbacked` exists for whoever decides a fact is
  legitimately the job of an unwired subsystem, and it prints what it suppressed.
- **A demand inside `any_of` or `none_of` is soft and never fails.** `any_of` passes
  when any branch passes, so an unsatisfiable branch is an alternative nobody takes;
  `none_of` needs its child to FAIL, so a fact count there is a prohibition and
  needs no supply at all. Gating on those would report content that works.

## Where it runs

`check` is wired into `tools check` beside the other content audits. It needs no
engine, so it costs about a second where `tools test` costs minutes, and an author
sees it on the next commit rather than the next release.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from .common import GAME_DIR, ToolError, fail, info, ok, warn

DATA_DIR = GAME_DIR / "data"
SRC_DIR = GAME_DIR / "src"

# A code-owned producer: a file in `res://src` that calls the ledger's one writer
# with a fact id it declared as a constant. `app/character_creation_flow.gd` is the
# live example - `const FACT_ID := &"character_created"` fed to
# `WorldFact.record(actor, FACT_ID, 1)`. The census has to read these, because a fact
# produced by a code constant is IN the ledger and a `.tres` demanding it would
# otherwise be reported unbacked while the game supplies it. This is the one producer
# class that is not authored content, and it is why `census()` reads `res://src` too.
_WRITER_CALL = re.compile(
    r"WorldFact\.record\(\s*[A-Za-z_][A-Za-z0-9_.]*\s*,\s*([^,]+?)\s*,\s*([^)]+?)\s*\)"
)
_STRING_CONST = re.compile(r'^\s*const\s+([A-Z0-9_]+)\s*:?=\s*&"([a-z0-9_]+)"', re.MULTILINE)
_NAMED_STRING = re.compile(r"^[A-Z0-9_]+$")

# A roster of static fact ids: `const NAME: Array[Dictionary] = [` then rows of
# `{"fact": &"id", ...}` to the closing `]`. Measured 2026-10-03 against
# `app/world_pulse.gd:143 AMBIENT_FACTS`, whose four ids fed four shipped event
# triggers the census called permanently dead. Two shapes were documented before and
# neither is this one: the ids are not a bare `&"..."` at the writer call, and they are
# not a scalar StringName const either. A producer nobody had named, and a gate that
# reported a satisfiable gate as dead because of it - the exact ceiling-with-a-hole-in-it
# failure this module exists to prevent, self-inflicted.
_ROSTER_OPEN = re.compile(r"^\s*const\s+([A-Z0-9_]+)\s*:[^=]*=\s*\[", re.MULTILINE)
_ROSTER_FACT = re.compile(r'"fact"\s*:\s*&"([a-z0-9_]+)"')

# A file can reach the ledger two ways: it calls `WorldFact.record` itself, or it hands
# a beat to a dispatcher that does (`app/world_pulse.gd:262 offer` ->
# `app/beat_director.gd:122 WorldFact.record`). The second is the ADR 0114 chain and the
# shipped path, so requiring a direct `record` would miss every correctly-dispatched
# producer and report its gate dead - a false red, which is worse than a false green
# because it sends an agent to author a producer that already exists. Matched on the
# dispatcher CALL (`_director.offer(`), not the class name: a filename check would be a
# claim about one file rather than about reachability.
_DISPATCH_CALL = re.compile(r"\.offer\s*\(\s*[A-Za-z_][A-Za-z0-9_.]*\s*,")

# `class_name Foo`, to resolve a roster to the file that DECLARES it.
_CLASS_NAME = re.compile(r"^\s*class_name\s+([A-Z][A-Za-z0-9_]*)", re.MULTILINE)
# A static call into another class: `WorldAmbient.due(`, `Foo.bar(`. The leading dot is
# what makes it static, so an instance call cannot be mistaken for one.
_STATIC_CALL = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\.[a-z_][A-Za-z0-9_]*\s*\(")
# A roster whose ids are handed onward - a `for` over the roster feeding a call out of
# the file. Without this a table nothing dispatches would read as supply.
_ROSTER_DISPATCH = re.compile(r"for\s+\w+\s+in\s+\w*ROSTER\w*\s*:")


# `WorldFact.has` floors `need` at 1 (world_fact.gd:187) and `QuestStepDef
# .required_count()` does the same, so a demand of 0 or less is a demand of one. The
# census mirrors both rather than restating the number an author typed.
MIN_DEMAND = 1
# `WorldBeat.make` and `EventBeatWriter.offer` both treat an absent `amount` as one,
# and an amount of zero or less is refused outright - so an omitted amount supplies
# one and a non-positive amount supplies NOTHING (it is a beat that never lands).
DEFAULT_AMOUNT = 1

# The requirement-language verbs this census reads. `fact` is the world ledger;
# the three composites are structural; everything else belongs to `destiny` or
# `sect` and is listed in blind spot 3 above.
VERB_FACT = "fact"
VERB_ALL_OF = "all_of"
VERB_ANY_OF = "any_of"
VERB_NONE_OF = "none_of"

# A cheap pre-filter so 15k `.tres` files are read but not parsed. Every shape this
# module understands contains one of these tokens, so a file holding none of them
# cannot hold a producer or a demand and skipping it loses nothing. The tokens are
# the KEY with no trailing space on purpose: a `fact = "x"` spelled with a plain
# String rather than a `&"x"` StringName still has to be seen, and a filter that
# misses one file is a census that silently under-counts.
TOUCH_TOKENS = ('"fact"', "fact =", "need =", "requires =", "trigger =", "on_enter =")

_BLOCK_HEAD = re.compile(r"^\[(?P<kind>[a-z_]+)(?P<rest>.*)\]\s*$")
_PROP = re.compile(r"^(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?P<value>.*)$")
# A typed array literal: `Array[EventStageDef]([...])`, `Array[StringName]([...])`,
# `Array[ExtResource("2_step")]([...])`. The element type is skipped rather than
# understood - the census wants the values. Missing this reads the whole property as
# the bareword `Array`, which is the WORST failure this parser can have: it makes
# every stage beat invisible, drops the supply ceiling to zero, and then reports
# fourteen satisfiable gates as dead.
_TYPED_ARRAY = re.compile(r"Array\[[^\[\]]*\]\s*\(")
# A resource reference as a value: `SubResource("Stage_lots_read")`. The census
# wants the NAME, not the constructor, so the argument is the value.
_RESOURCE_REF = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\s*\(")


class ParseError(ToolError):
    """A `.tres` fragment this module cannot read. Never swallowed."""


# --- The Godot literal subset ------------------------------------------------


def parse_value(text: str, index: int) -> tuple[object, int]:
    """One value from `text` at `index`, and the index just past it.

    The subset a text resource actually uses for a requirement or a beat:
    dictionaries, arrays, `&"StringName"` / `"String"`, integers, floats, `true`,
    `false` and bare identifiers. A hand-rolled recursive descent rather than a
    regex, because a requirement is nested (`all_of` inside `all_of`) and a regex
    over braces is exactly the kind of reader that silently miscounts depth.
    """
    index = _skip_space(text, index)
    if index >= len(text):
        raise ParseError("value expected, found end of input")
    typed = _TYPED_ARRAY.match(text, index)
    if typed is not None:
        inner, after = parse_value(text, typed.end())
        after = _skip_space(text, after)
        if after >= len(text) or text[after] != ")":
            raise ParseError(f"expected ')' closing a typed array at offset {after}")
        return inner, after + 1
    reference = _RESOURCE_REF.match(text, index)
    if reference is not None:
        inner, after = parse_value(text, reference.end())
        after = _skip_space(text, after)
        if after >= len(text) or text[after] != ")":
            raise ParseError(f"expected ')' closing a resource reference at offset {after}")
        return inner, after + 1
    char = text[index]
    if char == "{":
        return _parse_dict(text, index)
    if char == "[":
        return _parse_list(text, index)
    if char in "&\"'":
        return _parse_string(text, index)
    if char == "-" or char.isdigit():
        return _parse_number(text, index)
    return _parse_bareword(text, index)


def _skip_space(text: str, index: int) -> int:
    while index < len(text) and text[index] in " \t\r\n":
        index += 1
    return index


def _parse_dict(text: str, index: int) -> tuple[dict, int]:
    out: dict = {}
    index = _skip_space(text, index + 1)
    if index < len(text) and text[index] == "}":
        return out, index + 1
    while True:
        index = _skip_space(text, index)
        key, index = _parse_key(text, index)
        index = _skip_space(text, index)
        if index >= len(text) or text[index] != ":":
            raise ParseError(f"expected ':' after key {key!r} at offset {index}")
        value, index = parse_value(text, index + 1)
        out[key] = value
        index = _skip_space(text, index)
        if index >= len(text):
            raise ParseError(f"unterminated dictionary at key {key!r}")
        if text[index] == ",":
            index += 1
            continue
        if text[index] == "}":
            return out, index + 1
        raise ParseError(f"expected ',' or '}}' at offset {index}, found {text[index]!r}")


def _parse_key(text: str, index: int) -> tuple[str, int]:
    if index < len(text) and text[index] in "&\"'":
        value, index = _parse_string(text, index)
        return str(value), index
    return _parse_bareword(text, index)


def _parse_list(text: str, index: int) -> tuple[list, int]:
    out: list = []
    index = _skip_space(text, index + 1)
    if index < len(text) and text[index] == "]":
        return out, index + 1
    while True:
        value, index = parse_value(text, index)
        out.append(value)
        index = _skip_space(text, index)
        if index >= len(text):
            raise ParseError("unterminated array")
        if text[index] == ",":
            index += 1
            continue
        if text[index] == "]":
            return out, index + 1
        raise ParseError(f"expected ',' or ']' at offset {index}, found {text[index]!r}")


def _parse_string(text: str, index: int) -> tuple[str, int]:
    # A leading `&` is Godot's StringName sigil and is not part of the value.
    if text[index] == "&":
        index += 1
    quote = text[index]
    out: list[str] = []
    index += 1
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text):
            out.append(text[index + 1])
            index += 2
            continue
        if char == quote:
            return "".join(out), index + 1
        out.append(char)
        index += 1
    raise ParseError("unterminated string")


def _parse_number(text: str, index: int) -> tuple[int | float, int]:
    start = index
    if text[index] == "-":
        index += 1
    seen_dot = False
    while index < len(text) and (text[index].isdigit() or text[index] in "._"):
        if text[index] == ".":
            seen_dot = True
        index += 1
    raw = text[start:index].replace("_", "").replace(".", "", 1)
    return (float(raw) if seen_dot else int(raw)), index


def _parse_bareword(text: str, index: int) -> tuple[str, int]:
    start = index
    while index < len(text) and (text[index].isalnum() or text[index] == "_"):
        index += 1
    if start == index:
        raise ParseError(f"expected a value at offset {index}, found {text[index]!r}")
    return text[start:index], index


# --- Blocks and properties ---------------------------------------------------


@dataclass
class Block:
    """One `[header]` section of a `.tres`, with its properties and their lines."""

    kind: str
    ident: str
    props: dict[str, tuple[object, int]] = field(default_factory=dict)


def read_blocks(text: str, path: Path) -> list[Block]:
    """Every `[sub_resource]` / `[resource]` block, with `key = value` properties.

    Godot's text format is one property per line except when the value is a
    bracketed literal that the writer wrapped, so a property's lines are gathered
    until the brackets balance. Quoted strings are tracked so a `}` inside a
    description does not close a literal early.
    """
    blocks: list[Block] = []
    current: Block | None = None
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        head = _BLOCK_HEAD.match(line.strip())
        if head is not None:
            current = Block(kind=head.group("kind"), ident=_block_ident(head.group("rest")))
            blocks.append(current)
            index += 1
            continue
        prop = _PROP.match(line.strip())
        if prop is None or current is None:
            index += 1
            continue
        value_lines = [prop.group("value")]
        while not _balanced("\n".join(value_lines)):
            index += 1
            if index >= len(lines):
                raise ParseError(f"{path.name}: property {prop.group('key')!r} never closes")
            value_lines.append(lines[index].strip())
        value, _ = parse_value("\n".join(value_lines), 0)
        current.props[prop.group("key")] = (value, index + 1)
        index += 1
    return blocks


def _block_ident(rest: str) -> str:
    found = re.search(r'id="([^"]*)"', rest)
    return found.group(1) if found else ""


def _balanced(fragment: str) -> bool:
    """Whether every bracket in a value literal has been closed.

    Quote tracking matters because a `}` or `[` inside a `display_name` would
    otherwise close the literal early and the next property would be read as part of
    this one. `&` is skipped rather than treated as a quote: it is Godot's StringName
    SIGIL, so `&"x"` is one string and reading the sigil as the opening delimiter
    would look for a closing `&` that never comes."""
    depth = 0
    in_string = ""
    escaped = False
    for char in fragment:
        if escaped:
            escaped = False
            continue
        if in_string:
            if char == "\\":
                escaped = True
            elif char == in_string:
                in_string = ""
            continue
        if char in "\"'":
            in_string = char
        elif char == "&":
            continue
        elif char in "{[":
            depth += 1
        elif char in "}]":
            depth -= 1
    return depth <= 0 and not in_string


# --- The census --------------------------------------------------------------


@dataclass
class Supply:
    """What the authored tree offers for one fact id, and where it offers it."""

    fact: str
    total: int = 0
    sites: list[str] = field(default_factory=list)
    #: True once a code-owned verb has been shown reachable from production code, which is
    #: what lets `total` mean "no ceiling" rather than "one occurrence".
    repeatable: bool = False


@dataclass
class Demand:
    """One authored claim that the world hold `need` of `fact`."""

    fact: str
    need: int
    where: str
    line: int
    kind: str
    hard: bool


@dataclass
class Finding:
    """A gate the authored world cannot open, with the numbers that say so."""

    code: str
    demand: Demand
    supply: int
    note: str


def _beat_amount(beat: object) -> int:
    """How much a beat supplies. An absent `amount` is one; a non-positive one is
    nothing, because `WorldFact.record` refuses it and `BeatDirector.offer` refuses
    it before the writer is reached."""
    if not isinstance(beat, dict):
        return 0
    raw = beat.get("amount", DEFAULT_AMOUNT)
    if not isinstance(raw, (int, float)):
        return 0
    return int(raw)


def _beat_fact(beat: object) -> str:
    if not isinstance(beat, dict):
        return ""
    fact = beat.get("fact", "")
    return str(fact) if isinstance(fact, str) else ""


def _collect_supply(block: Block, label: str, supply: dict[str, Supply]) -> None:
    """Sum every `{fact, amount}` beat a block offers, at any beat `kind`.

    `EventBeatWriter.offer` records the fact FIRST and only then tallies an npc, so
    a `kind: npc_tally` beat supplies exactly as much as a plain one. Reading the
    kind would be a second, wrong rule."""
    beats = block.props.get("on_enter", ([], 0))[0]
    if not isinstance(beats, list):
        return
    for beat in beats:
        fact = _beat_fact(beat)
        if fact == "":
            continue
        amount = _beat_amount(beat)
        row = supply.setdefault(fact, Supply(fact=fact))
        row.total += max(0, amount)
        row.sites.append(f"{label} ({amount})")


def _walk_requirement(
    requirement: object, hard: bool, kind: str, where: str, line: int, out: list[Demand]
) -> None:
    """Every `fact` demand inside a requirement, with its hardness.

    `all_of` passes only if every child passes, so its facts are hard demands. In
    `any_of` a fact is one alternative among several, and in `none_of` it is a
    prohibition that is SATISFIED by failing - neither needs supply, and gating on
    them would report content that works."""
    if not isinstance(requirement, dict) or requirement == {}:
        return
    verb = str(requirement.get("verb", ""))
    if verb == VERB_FACT:
        fact = str(requirement.get("id", ""))
        if fact == "":
            return
        raw = requirement.get("need", MIN_DEMAND)
        need = int(raw) if isinstance(raw, (int, float)) else MIN_DEMAND
        out.append(
            Demand(
                fact=fact,
                need=max(MIN_DEMAND, need),
                where=where,
                line=line,
                kind=kind,
                hard=hard,
            )
        )
        return
    child_hard = hard if verb == VERB_ALL_OF else False
    if verb not in (VERB_ALL_OF, VERB_ANY_OF, VERB_NONE_OF):
        return
    children = requirement.get("of", [])
    if not isinstance(children, list):
        return
    for child in children:
        _walk_requirement(child, child_hard, kind, where, line, out)


def scan_file(
    path: Path, supply: dict[str, Supply], demands: list[Demand], unread: list[tuple[str, int, str]]
) -> None:
    """One `.tres`: its beats into `supply`, its gates into `demands`.

    A stage is recognised MECHANICALLY, by the presence of a `stage_id` property,
    and its POSITION comes from the `stages` array that names it - not from the order
    the sub-resources happen to be written in, because `[gd_resource]` block order is
    an editor detail and the array is what `EventDef.stage_at` walks.

    An event's first stage is flagged in `unread` when it carries a non-empty
    `requires`, because `EventApi.advance` only ever evaluates `following.requires`
    (api.gd:297): the opening stage's own gate is read by nothing, so authoring one
    is a claim the engine makes no attempt to keep.
    """
    relative = path.relative_to(GAME_DIR).as_posix()
    text = path.read_text(encoding="utf-8")
    blocks = read_blocks(text, path)
    main = next((b for b in blocks if b.kind == "resource"), None)

    if main is not None:
        event_id = str(main.props.get("id", ("", 0))[0])
        label = f"{relative}:{event_id}"
        _collect_supply(main, f"{label} opening", supply)
        trigger, line = main.props.get("trigger", ({}, 0))
        # A trigger is read BEFORE `begin` writes a single beat (api.gd:150), so it
        # asks about the world as it already was. Nothing inside a ladder can supply
        # that, and the demand is still checked - as an `unbacked_demand`.
        _walk_requirement(trigger, True, "event trigger", label, line, demands)
        for index, stage in enumerate(_ladder(main, blocks)):
            stage_label = f"{label} stage {index}"
            _collect_supply(stage, stage_label, supply)
            requires, requires_line = stage.props.get("requires", ({}, 0))
            _walk_requirement(
                requires, True, "event stage gate", stage_label, requires_line, demands
            )
            if index == 0 and isinstance(requires, dict) and requires:
                stage_id = str(stage.props.get("stage_id", ("", 0))[0])
                unread.append((stage_label, requires_line, stage_id))

    # A quest step is the same ledger and the same demand shape: `fact` + `need`
    # read by `QuestStepDef.required_count()`, satisfied by nothing the tree does
    # not author. Recognised by the property pair rather than by directory, so a
    # step authored anywhere is counted rather than missed.
    for block in blocks:
        if block.kind != "sub_resource" or "fact" not in block.props:
            continue
        fact = str(block.props["fact"][0])
        need_raw = block.props.get("need", (MIN_DEMAND, 0))[0]
        need = int(need_raw) if isinstance(need_raw, (int, float)) else MIN_DEMAND
        step_id = str(block.props.get("step_id", ("", 0))[0])
        demands.append(
            Demand(
                fact=fact,
                need=max(MIN_DEMAND, need),
                where=f"{relative}:{step_id}",
                line=block.props["fact"][1],
                kind="quest step",
                hard=True,
            )
        )


def _ladder(main: Block, blocks: list[Block]) -> list[Block]:
    """The stages in the order `EventDef.stages` holds them.

    Resolved through the `SubResource("...")` names in the array against each
    sub-resource's own `id`, so the ladder is the array's order rather than the
    editor's block order. A stage the array does not name is a stage the engine
    cannot reach, so it is DROPPED here - it contributes no beat, which is exactly
    what the runtime does with it, and it is reported by `unread_gate` if it also
    carries a gate."""
    by_ident = {
        block.ident: block
        for block in blocks
        if block.kind == "sub_resource" and block.ident and "stage_id" in block.props
    }
    raw = main.props.get("stages", ([], 0))[0]
    if not isinstance(raw, list):
        return []
    ordered: list[Block] = []
    for entry in raw:
        # The parser already unwrapped `SubResource("...")` to its name, so the entry
        # IS the sub-resource id.
        block = by_ident.get(str(entry))
        if block is not None:
            ordered.append(block)
    return ordered


def code_owned_supply(supply: dict[str, Supply]) -> None:
    """Add every fact a `res://src` file produces by declaring its id in code.

    Three shapes reach the ledger, and only the first is authored content:

    - the id is a member expression (`beat["fact"]`, `claim.fact`) - the value arrived
      from a beat a `.tres` authored, so `census()` has already counted it;
    - the id is a name the same file declared as a `const` holding a `StringName`
      literal - a code-owned producer, invisible to a content scan and therefore
      counted HERE or the ceiling is wrong; and
    - the id is a row of a static roster (`{"fact": &"id", ...}`) that the file, or a
      class it calls, hands to a dispatcher. Measured 2026-10-03 as three further hops
      than any shape this function had been taught: `app/world_ambient.gd:60 ROSTER` ->
      `due()` -> `app/world_pulse.gd:332` -> `offer()` -> `app/beat_director.gd:122`
      `WorldFact.record`. A per-file scan is structurally blind to that, so four shipped
      event triggers were reported permanently dead while the producer was running.

    A writer is pinned by `tests/arch_rules/test_fact_ledger_writers.gd`: the writer
    SET is asserted there, and the id-literal rule there is what keeps this function
    from having to guess about an id it cannot resolve. An id expression this cannot
    resolve - arithmetic on a string, a name from elsewhere - is deliberately NOT
    counted, because inventing a supply figure is how a census starts lying.

    The roster shape is the one place that rule could have been bent, because a roster
    genuinely IS supply and refusing to see it produces a FALSE RED - which is worse
    than a false green here, since a false red sends an agent to author a producer that
    already exists. So it counts under one condition, and the condition is the whole
    design: a roster counts only when some file that REACHES the writer names its class
    in a static call. A table nothing dispatches is not supply, and counting it would
    make the missing-producer finding disappear - the quiet lie this module exists to
    refuse.
    """
    dispatchers = _dispatcher_classes()
    # Seeded with every dispatcher up front, not accumulated during the walk: `app/` sorts
    # BEFORE `app/world_ambient.gd`'s own neighbours in any ordering that puts `ambient`
    # first, so a single pass would read the caller's reference before the table exists
    # and silently count zero. Two passes over 15k files is cheaper than an order-
    # dependent answer.
    dispatched: set[str] = set(dispatchers)
    for path in sorted(SRC_DIR.rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        reaches_writer = "WorldFact.record" in text or _DISPATCH_CALL.search(text) is not None
        if reaches_writer:
            dispatched |= _static_class_calls(text, dispatchers)
        if not reaches_writer and not _static_class_calls(text, dispatchers):
            continue
        consts = dict(_STRING_CONST.findall(text))
        relative = path.relative_to(GAME_DIR).as_posix()
        for index, line in enumerate(text.split("\n")):
            code = line.split("#")[0]
            call = _WRITER_CALL.search(code)
            if call is None:
                continue
            id_expr, amount_expr = call.group(1).strip(), call.group(2).strip()
            if id_expr.startswith('&"') or id_expr.startswith('"'):
                fact = id_expr.strip('&"')
            elif _NAMED_STRING.match(id_expr) and id_expr in consts:
                fact = consts[id_expr]
            else:
                continue
            if fact == "":
                continue
            amount = int(amount_expr) if amount_expr.isdigit() else DEFAULT_AMOUNT
            row = supply.setdefault(fact, Supply(fact=fact))
            row.total += max(0, amount)
            row.sites.append(f"{relative}:{index + 1} ({amount}, code const)")
            _note_reachability(row, relative)

    for roster_relative, ids, start in _roster_files(dispatched):
        for fact in ids:
            row = supply.setdefault(fact, Supply(fact=fact))
            row.total += DEFAULT_AMOUNT
            row.sites.append(f"{roster_relative}:{start} ({DEFAULT_AMOUNT}, code roster)")


#: A code-owned producer is a VERB, and a verb can be called again. Its authored ceiling is
#: therefore not one occurrence but "as many as the game can reach" — and the only honest
#: reading of that needs the call graph, which this module does not walk. So the supply is
#: conditional on REACHABILITY, measured the way `tools/acquisition` measures a route: is the
#: recording verb called from production code OUTSIDE the module that declares it?
#:
#: This is not a convenience. `SectDuty.serve` discharged obligations correctly and had zero
#: production callers, and a census that counted its three terms would have reported a
#: `need: 3` gate satisfiable by a verb nothing drives — the ADR 0066 quiet lie with a
#: number attached. Conditional supply keeps the finding honest in both directions: an
#: unwired verb stays red, and wiring it turns the gate green for the real reason.
REPEATABLE = -1  # "callable again", so no authored ceiling applies


def _record_verb_is_reachable(relative: str) -> bool:
    """Is the class that records this fact called from production code OUTSIDE its module?

    `relative` is the declaring file. Two things this must not get wrong, both of which I
    got wrong first:

    - the identity is the `class_name`, not the filename. `combat_facts.gd` declares
      `CombatFacts`, and a caller writes `CombatFacts.record_duel_won(` - matching the
      snake_case stem as a substring finds nothing and silently reports every site
      unreachable, which reads as a tool limitation rather than a bug.
    - "outside the module" means outside the MODULE, not outside the file. `duel_hit.gd`
      calls `CombatFacts.record_duel_won`, but both live in `modules/combat/`, and a writer
      only its own module calls is exactly the dead writer this is meant to catch.
    """
    owner = Path(relative).stem
    declaring = (GAME_DIR / relative).read_text(encoding="utf-8")
    found = _CLASS_NAME.search(declaring)
    class_name = found.group(1) if found else _to_pascal(owner)
    if not class_name:
        return False
    module = str(Path(relative).parent)
    for path in sorted(SRC_DIR.rglob("*.gd")):
        candidate = path.relative_to(GAME_DIR).as_posix()
        if str(Path(candidate).parent) == module:
            continue
        text = path.read_text(encoding="utf-8")
        if re.search(rf"\b{class_name}\s*\.", text):
            return True
    return False


def _to_pascal(stem: str) -> str:
    """`combat_facts` -> `CombatFacts`. Read from the file when it declares a different
    `class_name`, because that is the identifier a caller actually writes."""
    return "".join(part.capitalize() for part in stem.split("_") if part)


def _note_reachability(row: Supply, relative: str) -> None:
    """Upgrade a code-owned site's ceiling to REPEATABLE, but only if it is driven.

    No guard on the amount expression. My first version skipped a site whose amount was the
    literal `1`, on the reasoning that an authored quantity stands on its own - and that
    silently exempted exactly the case that matters: `CombatFacts.record_duel_won` passes a
    literal `1` meaning "one duel per call", and a `need: 3` gate then read dead with no
    note explaining why. A literal at a code-owned writer is an amount PER OCCURRENCE. The
    ceiling is a property of how many times the game can call the verb, never of the number
    written at one call site.
    """
    if row.repeatable:
        return
    if not _record_verb_is_reachable(relative):
        row.sites.append(f"{relative} (UNDECLARED CEILING: verb reached only from itself)")
        return
    row.total += REPEATABLE
    row.repeatable = True
    row.sites.append(f"{relative} (repeatable: verb reached from production code)")


def _roster_files(dispatched: set[str]) -> list[tuple[str, list[str], int]]:
    """Every static roster declared by a class named in `dispatched`.

    The class is resolved through `class_name`, so the roster is read from the file that
    DECLARES the table (`app/world_ambient.gd`), not from the caller that dispatches it
    (`app/world_pulse.gd`). Reading the caller's copy would be reading a reference to a
    table - `const AMBIENT_FACTS := WorldAmbient.ROSTER` - which carries no ids at all,
    and would report zero supply for a producer that ships.
    """
    by_class: dict[str, Path] = {}
    for path in sorted(SRC_DIR.rglob("*.gd")):
        name = _CLASS_NAME.search(path.read_text(encoding="utf-8"))
        if name:
            by_class[name.group(1)] = path

    out: list[tuple[str, list[str], int]] = []
    for cls in sorted(dispatched):
        source = by_class.get(cls)
        if source is None:
            continue
        text = source.read_text(encoding="utf-8")
        for ids, start in _static_rosters(text):
            out.append((source.relative_to(GAME_DIR).as_posix(), ids, start))
    return out


def _dispatcher_classes() -> set[str]:
    """Every `class_name` whose file hands a fact id to a ledger dispatcher.

    A class qualifies only if its file both declares a static roster and calls out of
    itself - `WorldAmbient.due` is not the writer, but `world_pulse._offer_ambient`
    loops its answer straight into `offer()`. Requiring the call is what stops an
    unreferenced table from reading as supply.
    """
    out: set[str] = set()
    for path in sorted(SRC_DIR.rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        if not _static_rosters(text):
            continue
        name = _CLASS_NAME.search(text)
        if name and _ROSTER_DISPATCH.search(text):
            out.add(name.group(1))
    return out


def _static_class_calls(text: str, known: set[str]) -> set[str]:
    """Classes this file names in a static call, e.g. `WorldAmbient.due(...)`."""
    found: set[str] = set()
    for cls in _STATIC_CALL.findall(text):
        if cls in known:
            found.add(cls)
    return found


def _static_rosters(text: str) -> list[tuple[list[str], int]]:
    """Every `const NAME: Array[...] = [ ... {"fact": &"id", ...} ... ]` roster in a file.

    Returns the ids each roster declares with the 1-based line the `const` opens on, so
    a supply site points at the declaration a reader can go and look at.

    Only a roster that actually names a `fact` key is read, and only ids it literally
    declares are counted - the same refusal as the scalar const. A roster is a static
    table by construction, so there is nothing here to guess at.
    """
    found: list[tuple[list[str], int]] = []
    for match in _ROSTER_OPEN.finditer(text):
        start = text.count("\n", 0, match.start()) + 1
        end = text.find("\n]", match.end())
        if end == -1:
            continue
        body = text[match.end() : end]
        ids = _ROSTER_FACT.findall(body)
        if ids:
            found.append((ids, start))
    return found


def census() -> tuple[dict[str, Supply], list[Demand], list[tuple[str, int, str]], int]:
    """Walk every authored `.tres` under `game/data`, plus the code-owned producers.

    All of `game/data`, not just `data/event`, and that is the point: a census scoped
    to the directory where the defect was found cannot see a producer authored
    anywhere else, and would report a satisfiable gate as dead the first time a
    second domain started supplying the fact. Two domains share one ledger here
    (`event` supplies, `quest` demands), and the next one is nobody's guess.
    """
    supply: dict[str, Supply] = {}
    demands: list[Demand] = []
    unread: list[tuple[str, int, str]] = []
    scanned = 0
    for path in sorted(DATA_DIR.rglob("*.tres")):
        text = path.read_text(encoding="utf-8")
        if not any(token in text for token in TOUCH_TOKENS):
            continue
        scanned += 1
        try:
            scan_file(path, supply, demands, unread)
        except ParseError as exc:
            raise ToolError(f"{path.relative_to(GAME_DIR).as_posix()}: {exc}") from exc
    code_owned_supply(supply)
    return supply, demands, unread, scanned


def judge(
    supply: dict[str, Supply], demands: list[Demand], unread: list[tuple[str, int, str]]
) -> list[Finding]:
    """Every gate the authored world cannot open.

    A demand is judged against the TOTAL the tree offers, not against what this one
    ladder offers. Cross-ladder supply is real: `EventDef.trigger` reads facts other
    events' beats write, and nothing orders one event's ladder against another's, so
    a ladder-local ceiling would report a satisfied gate as dead. Total supply is the
    only reading that never invents a defect - and it still catches `need: 2` on a
    fact one beat supplies, because the ceiling is a ceiling, not a guess.
    """
    findings: list[Finding] = []
    for demand in demands:
        if not demand.hard:
            continue
        offered = supply.get(demand.fact)
        # A REPEATABLE contributor means a verb the game can call again, so the authored
        # tree imposes no ceiling on this fact and `need` cannot outrun it. Counting the
        # sentinel arithmetically would be wrong in the other direction - a `need: 3` gate
        # would read as unsatisfiable against a total of -1.
        if offered is not None and offered.repeatable:
            continue
        total = offered.total if offered else 0
        if demand.need <= total:
            continue
        if total > 0:
            code = "dead_gate"
            note = (
                f"the authored tree offers {total} in total and this gate asks for "
                f"{demand.need}; nothing can raise it"
            )
        else:
            code = "unbacked_demand"
            note = (
                "no authored beat produces this fact at all; the fix is a producer, "
                "not a smaller number"
            )
        findings.append(Finding(code=code, demand=demand, supply=total, note=note))
    for label, line, stage_id in unread:
        findings.append(
            Finding(
                code="unread_gate",
                demand=Demand(
                    fact="",
                    need=0,
                    where=label,
                    line=line,
                    kind="event stage gate",
                    hard=True,
                ),
                supply=0,
                note=(
                    f"stage {stage_id!r} is the opening stage and nothing ever evaluates "
                    "its `requires` (EventApi.advance reads only `following.requires`)"
                ),
            )
        )
    return findings


def _report(
    findings: list[Finding], supply: dict[str, Supply], demands: list[Demand], scanned: int
) -> None:
    """Every finding, one per line, with the numbers that produced it.

    Printed in full rather than truncated. A finding list that stops at twelve is a
    finding list that reads as all-clear past the twelfth, which is the hazard
    `test_no_stranded_mutation.gd` names in the other direction."""
    for finding in sorted(findings, key=lambda f: (f.code, f.demand.where, f.demand.line)):
        demand = finding.demand
        if finding.code == "unread_gate":
            info(f"  {finding.code} {demand.where}:{demand.line}: {finding.note}")
            continue
        info(
            f"  {finding.code} {demand.where}:{demand.line}: {demand.kind} needs "
            f"{demand.need} of {demand.fact!r}; {finding.note}"
        )
    hard = sum(1 for d in demands if d.hard)
    info(
        f"  census: {scanned} candidate file(s), {len(supply)} fact(s) produced, "
        f"{len(demands)} gate(s) read ({hard} hard, {len(demands) - hard} soft)"
    )


def _check(args) -> int:
    supply, demands, unread, scanned = census()
    findings = judge(supply, demands, unread)
    counts = {code: 0 for code in ("dead_gate", "unbacked_demand", "unread_gate")}
    for finding in findings:
        counts[finding.code] += 1

    if counts["dead_gate"] or counts["unread_gate"]:
        fail(
            f"{counts['dead_gate']} dead gate(s) the authored world cannot open, "
            f"{counts['unread_gate']} gate(s) no code path reads"
        )
        _report(findings, supply, demands, scanned)
        return 1
    ok("every hard gate the tree authors is satisfiable by a beat the tree authors")

    if counts["unbacked_demand"] == 0:
        ok("and every one of them names a fact some authored beat produces")
        return 0

    if getattr(args, "allow_unbacked", False):
        warn(
            f"ALLOW-UNBACKED: {counts['unbacked_demand']} gate(s) name a fact no "
            f"authored beat produces. Suppressed by flag; each is a gate that cannot "
            f"open until a producer exists:"
        )
        _report(findings, supply, demands, scanned)
        return 0

    fail(
        f"{counts['unbacked_demand']} gate(s) name a fact no authored beat produces. "
        f"With the writer set pinned by tests/arch_rules/test_fact_ledger_writers.gd, "
        f"zero supply means the gate can never open."
    )
    _report(findings, supply, demands, scanned)
    return 1


def _show(args) -> int:
    supply, demands, unread, scanned = census()
    findings = judge(supply, demands, unread)
    info("produced facts (the ceiling every gate is judged against)")
    for fact in sorted(supply):
        row = supply[fact]
        info(f"  {fact:<40} {row.total:>3}   {'; '.join(row.sites)}")
    info("")
    info("gates read")
    for demand in sorted(demands, key=lambda d: (d.kind, d.where)):
        held = "hard" if demand.hard else "soft"
        info(f"  [{held}] {demand.kind:<17} {demand.where} need {demand.need} {demand.fact}")
    info("")
    info(f"findings: {len(findings)}")
    _report(findings, supply, demands, scanned)
    return 0


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "gate_reach",
        help="is every authored world-fact gate satisfiable by an authored beat?",
    )
    actions = parser.add_subparsers(dest="action", required=True)
    check = actions.add_parser(
        "check", help="the guard: fail a gate the authored world cannot open"
    )
    check.add_argument(
        "--allow-unbacked",
        action="store_true",
        help=(
            "do not fail a gate naming a fact nothing produces; the suppression is "
            "printed. Not for a clean tree - it converts a dead gate into a note"
        ),
    )
    check.set_defaults(func=_check)
    report = actions.add_parser("report", help="print the whole census: supply, gates, findings")
    report.set_defaults(func=_show)


def run(args) -> int:
    return args.func(args)
