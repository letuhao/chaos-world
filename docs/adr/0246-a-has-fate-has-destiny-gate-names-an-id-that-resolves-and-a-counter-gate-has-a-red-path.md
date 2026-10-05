# 0246 a has_fate/has_destiny gate names an id that resolves, and a counter gate has a red path

- Status: Accepted
- Date: 2026-10-05
- Depends on: ADR 0149 (a counter moves only where a fact is written), ADR 0113 (an alias
  is a legal authored id), ADR 0065 (fate is earned, never chosen or removed), ADR 0196 (a
  tag may not be coined)
- Resolves: DEF-0284, DEF-0283 (INC-0016)

## Context

`_destiny_findings` validated `grants_fates`, `requires_fates`, `requires_destinies`,
`gate_aliases`, soul marks and stat ids. Three whole-tree walks existed for GATE
requirements: `_authored_counter_gates` (ADR 0149's owed check), `_authored_tagged_gates`
and `_none_of_tagged_gates` (ADR 0196). **Nothing walked a `has_fate`/`has_destiny` id.**
The only guard was GDScript (`tests/modules/quest/test_quest_content.gd`), which asserts
that at least one shipped quest gates on `has_destiny` and that its `id` is non-empty —
it never resolves the id, and it fires only when a Godot suite runs.

The severity is understated by the defect list. `data audit` currently exits 1 with ~1501
findings, every one of them `item <id>: boss <id> does not drop it` — unrelated loot churn
belonging to another line. An author who types `has_fate: first_blood_duell` therefore sees
a wall of unrelated output and **zero mention of their broken gate**, and the quest
silently never offers.

Two of the guards that DID exist had no red path at all. `_counter_findings` and
`_counter_notes` are called from `_destiny_findings` and were exercised by no case in
`tools/data_selftest.py`: a reader returning `[]` from both passes every guard case in the
repo and leaves `data audit`'s output byte-identical. That is INC-0016 — **a green guard is
not a tested guard.**

## Decision

- **A `has_fate`/`has_destiny` GATE naming an id no FateDef/DestinyDef defines, and no
  alias claims, FAILS the audit.** `DestinyGate._has_fate`/`_has_destiny` look the id up in
  the ledger, find nothing, and return an ordinary `unmet` — indistinguishable from "you
  have not earned it yet". Nothing can put an undeclared id into that ledger, so the door is
  permanently closed and reported as an ordinary prerequisite.
- **The resolver is `records["fate"] | records["destiny"] | aliases`, in one place.** An
  alias IS a legal authored id: `DestinyDef.gate_aliases` exists so story can be authored
  before the destiny it answers for ships (ADR 0113), and `DestinyGate.holds_destiny`
  resolves one in BOTH directions. Checking the `.tres` records alone fails the exact
  prerequisite the feature exists to permit — the audit and the runtime disagreeing about
  whether a content author may write something. This is the same correction
  `requires_destinies` already carries, so the two fields cannot disagree.
- **The census is the WHOLE tree and it is the UNION of two readers.** Quests, events and
  destinies alike, for `_authored_counter_gates`' stated reason: a scan limited to
  `game/data/destiny/` passes for the WRONG REASON. Measured on the shipped tree, the two
  halves genuinely do not find the same rows — `the_returned_instrument.tres` and
  `the_terms_you_drafted.tres` author theirs at the top level, while
  `the_severed_calling.tres` nests both of its rows in an `all_of`. Six gates total: 2 on
  events, 4 on quests. **A reader built on either half alone under-reports on real
  content.**
- **Composites are descended by COUNTING brackets, not by a bounded wildcard.** A non-greedy
  `"of": \[(.*?)\]` stops at the `]` a sibling `of` entry carries and drops every row after
  it — the false negative an audit in this repo already hit once, and why
  `_NONE_OF_GATE` reads the way it does. The flat half is what guarantees the
  no-false-negative property, not the descent: a counted span is still a span, and a `]`
  inside an authored string truncates it. There is ONE bracket counter,
  `_children_of(text, start, row)`, and both composite readers pass through it, because a
  second brace-tolerant walk is a second thing to keep correct.
- **Every guard gets a red path, and the severity split is tested at its OWN severity.**
  `_counter_findings` FAILS an unwired counter GATE — it closes a player door — while
  `_counter_notes` WARNS on an unproduced fact and an unwired `FateDef.counters`
  declaration, which is a census over other modules' content (DEF-0105/0106, including
  `breakthroughs`) and a field no production code reads (DEF-0168). A gate and a
  declaration are not the same check.

## Consequences

- **The shipped tree is clean on this leg: 6 authored gates, 0 findings.** All six resolve —
  4 to a FateDef/DestinyDef, and `the_returned` is live content as an alias of
  `the_one_who_returned`, so the alias route is exercised rather than hypothetical. The
  guard is proven by fixtures, not by this count: INC-0016.
- **The ~1501 boss-drop findings are untouched and unrelated.** They belong to another
  line's in-flight loot work. They also remain the reason a `has_fate` typo is currently
  invisible, so this gate's value is not yet paid in the `data audit` exit code until that
  churn lands.
- **An empty catalog deliberately reports every authored id as dangling** rather than
  short-circuiting. A tree with no fates and no destinies resolves nothing, so every gate in
  it really is broken; a "nothing to check, return []" guard would be green on a tree whose
  every gate is closed.
- **One finding per `(file, id)`, not per authored row.** The repair is to fix the id, so a
  file naming the same dangling id three times is one defect reported once.
- **`_children_of` gained a required `row` argument.** Every composite reader now names the
  shape it is looking for at its own call site. Both existing callers were updated, so this
  is a signature change with no other consumers in the repo.
- **The fixture that proves the walk is whole-tree puts its gate on an EVENT, never on a
  destiny.** A destiny-scoped fixture passes even against a reader that scans one
  directory — satisfying the case for the wrong reason. The same rule governs the counter
  pair.
