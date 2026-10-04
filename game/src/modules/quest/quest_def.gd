class_name QuestDef
extends Resource

## One authored quest — the SINGLE shape behind BL-0053's three kinds.
##
## `kind` selects where the quest comes from, and it is read by exactly ONE rule:
## `QuestApi.offered` hands the player an `authored` quest and does not hand them a
## `systemic` or `emergent` one, because those two complete by living rather than by
## being offered. See that method for why the distinction is the rule and not a label.
##
## **What `kind` is NOT.** It does not change how a gate is read, how a step is
## counted, or what a quest pays — all three kinds are this class, all three are
## evaluated by the same `DestinyApi.gate` and the same `WorldFactLedger`. A kind that
## needed its own Resource would be three vocabularies for one idea, and the reader (a
## ledger count) would have to be written three times.
##
## **A requirement is DATA, never GDScript** (ADR 0065/0066). It is read through
## `DestinyApi.gate`, the six-verb evaluator, so a new gated quest is a content
## edit and not a code change. An empty requirement is ungated.
##
## A step is satisfied by `WorldFactLedger.has(actor, step.fact, step.need)`.
## **This module never writes the ledger.** Quests read the world's memory; the
## systems that own the moment write it (ADR 0113).

## The closed set of kinds, as an AUTHORING vocabulary. `QuestApi.offered` is the
## one reader; `kind_valid()` exists so a test can say a `.tres` named something
## outside the set instead of a save discovering it.
const KIND_AUTHORED := &"authored"
const KIND_SYSTEMIC := &"systemic"
const KIND_EMERGENT := &"emergent"

const KINDS: Array[StringName] = [KIND_AUTHORED, KIND_SYSTEMIC, KIND_EMERGENT]

## The closed set of grant kinds (DEF-0107).
##   `fate`    — paid through `DestinyApi.earn_fate`. Fate ids are plain ids in
##               fate's OWN catalog and are never authored as `quest:*`.
##   `destiny` — paid through `DestinyApi.earn_destiny`, same rule.
##   `item`    — an id for a future inventory delivery. ItemsApi is NOT a quest
##               dependency, so this module RECORDS the grant as unspent rather
##               than calling across a module it does not depend on.
const GRANT_FATE := &"fate"
const GRANT_DESTINY := &"destiny"
const GRANT_ITEM := &"item"

const GRANT_KINDS: Array[StringName] = [GRANT_FATE, GRANT_DESTINY, GRANT_ITEM]

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var kind: StringName = KIND_AUTHORED
@export var tier: int = 0

## The gate this quest opens behind, read through `DestinyApi.gate`. Empty = open.
@export var requirement: Dictionary = {}

@export var steps: Array[QuestStepDef] = []

## Rewards, each `{kind: StringName, id: StringName, amount: int}`. `amount`
## below 1 normalizes to 1: a reward of zero is a typo, and paying nothing for a
## completed quest silently loses content.
@export var grants: Array[Dictionary] = []


## Whether `kind` is one of the three BL-0053 named.
func kind_valid() -> bool:
	return KINDS.has(kind)


## The grant kind set, as authored. An unknown kind is refused by the payer and
## reported, never guessed at.
func grant_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for grant in grants:
		out.append(StringName(grant.get("kind", "")))
	return out


## The step asking for `fact`, or null.
func step_for_fact(fact: StringName) -> QuestStepDef:
	for step in steps:
		if step != null and step.fact == fact:
			return step
	return null


## Whether any step of this quest watches `fact`. This is the question the beat
## handler asks (ADR 0114): a beat whose fact no ACTIVE quest watches is not
## this module's to resolve.
func watches_fact(fact: StringName) -> bool:
	return step_for_fact(fact) != null


## Every fact id any step names, in authored order and de-duplicated. One pass,
## bounded by the authored step count — never a walk that could fail to
## terminate.
func watched_facts() -> Array[StringName]:
	var out: Array[StringName] = []
	for step in steps:
		if step == null:
			continue
		if not out.has(step.fact):
			out.append(step.fact)
	return out


## Every `{verb, id}` the `requirement` names, flattened through the composite
## verbs, so a panel can render "what is holding this back" without re-deriving
## the six-verb grammar (the `gates_for` facade verb reads this).
##
## Bounded by the authored requirement size: an `all_of` nests exactly as deep
## as its author wrote it, and a malformed cycle is refused rather than walked.
func required_gate_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	_collect_gate_ids(requirement, out)
	return out


func _collect_gate_ids(node, out: Array[StringName]) -> void:
	if not (node is Dictionary):
		return
	var entry := node as Dictionary
	var verb := StringName(entry.get("verb", ""))
	if verb == &"all_of" or verb == &"any_of" or verb == &"none_of":
		var children = entry.get("of", [])
		if not (children is Array):
			return
		# `size()` bounds the walk: a composite names its own children, so the
		# recursion depth is the authored nesting, never an unbounded search.
		for index in range((children as Array).size()):
			_collect_gate_ids((children as Array)[index], out)
		return
	var id := StringName(entry.get("id", ""))
	if id != &"" and not out.has(id):
		out.append(id)


## A quest with no step could complete the moment it is accepted, which is not a
## quest. Exposed for a content test.
func has_steps() -> bool:
	for step in steps:
		if step != null:
			return true
	return false
