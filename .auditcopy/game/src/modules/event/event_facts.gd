class_name EventFacts
extends RefCounted

## The event module's reader of the world fact ledger (ADR 0113), and **nothing
## else**. Every verb here delegates to `WorldFact`, which owns the ledger in
## `core/`. This file exists for two reasons and no more.
##
## ## Why this file used to be a second copy, and why it is not any more
##
## It shipped its own `normalize`, its own `record` and its own row shape over
## `actor.module_data["world_facts"]`, and its docstring claimed it was "the reader,
## not a second copy of the writer" — while doing exactly the second copy. Two
## normalisers over one key truncate each other on the way out, silently:
##
##   `WorldFact.normalize_payload` -> rows `{count, since}`
##   `EventFacts.normalize`        -> rows `{id, count}`   and a top-level `sequence`
##
## So an event beat landing on the ledger **deleted the `since` of every other
## system's facts**, and `since` is precisely what `WorldFact`'s "has this happened
## exactly once" gate reads. The mirror image was equally bad: `EventFacts.record`
## stored `since` as the ledger SEQUENCE at first occurrence, while `WorldFact`
## reads it as the COUNT at first record — the same field name, two meanings, over
## one row. `test_a_beat_recorded_by_an_event_survives_the_worlds_own_reader` is the
## round trip that fails when a second normaliser is reintroduced.
##
## ## A fact is a THING THAT HAPPENED, not a reward
##
## `{count, since}` and nothing else. `WorldFact.record` is monotone: it raises a
## count and never lowers one, which is what makes "did this already happen"
## answerable by counting, and is why a beat's own id must be unique per occurrence
## (ADR 0114). Nothing here grants a fate, moves a currency or touches a stat.
##
## ## The one new verb in the requirement language
##
## `has_fact(actor, id, need)` — `true` once the ledger has recorded `fact_id` at
## least `need` times. This is `{verb: "fact", id: <fact_id>, need: n}` in a
## trigger, and it is the ONLY addition to the `DestinyGate` / `SocialGate` shape.
## The composite verbs are reused untouched, so a fact-gated event is a content edit
## rather than a new gate system.
##
## ## No `MODULE_KEY` and no `normalize` here, deliberately
##
## There is no key constant to get out of step with `WorldFact`'s, and there is no
## normaliser to disagree with it, because this module can no longer write the
## ledger at all. [method EventBeatWriter] is the single write path and it calls
## `WorldFact.record`. A reappearing `func normalize` or `func record` in this
## module fails the build — see
## `test_the_event_module_declares_no_second_writer_over_the_world_fact_ledger`.

## The closed verb this module contributes to the shared requirement language.
## Named here, not read off `EventFacts` from a sibling: a trigger's verb is part of
## the requirement language and the language names it once.
const VERB_FACT := &"fact"


## How many times `fact_id` has been recorded. 0 when never recorded: a fact is
## monotone, so a missing row and a zero row are the same answer.
static func count_of(actor: Actor, fact_id: StringName) -> int:
	return WorldFact.count(actor, fact_id)


## Whether the ledger holds `fact_id` at least `need` times. The question a gate
## asks. `need` is floored at 1 by `WorldFact.has`, so a gate is never satisfied by
## a ledger that has never heard of its fact.
static func has_fact(actor: Actor, fact_id: StringName, need: int = 1) -> bool:
	return WorldFact.has(actor, fact_id, need)


## The next occurrence id for a beat. ADR 0114's once-rule forces the CALLER to
## name the occurrence, because a monotone ledger can only answer "has this fired"
## by counting — so a beat for the third beast is `killed_boar@3` and the fourth is
## `killed_boar@4`. Built from a caller-owned count, never from a clock.
static func occurrence_id(fact_id: StringName, occurrence: int) -> StringName:
	if occurrence > 0:
		return StringName("%s@%d" % [String(fact_id), occurrence])
	return StringName(fact_id)


## Every fact id the ledger holds, canonically ordered by its STRING value.
##
## `Array[StringName].sort()` is not specified to order by the interned string and
## the ids are interned, so the order would depend on which id loaded first. The
## comparison that cannot drift is used instead — the same rule `WorldFact.ids`
## documents, for the same reason: the order is load-bearing to a codex cycling it.
static func fact_ids(actor: Actor) -> Array[StringName]:
	return WorldFact.ids(actor)
