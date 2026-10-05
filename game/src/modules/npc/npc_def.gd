class_name NpcDef
extends Resource

## An authored INDIVIDUAL (ADR 0077). `WorldInhabitantDef` is the species — a bear; this
## is Bearcutter Lao, the smith who owes you a debt and will remember it.
##
## The split matters: a species is spawnable population and is owned by `world`, while an
## individual is a cast member with a tier, a stage ladder and a roster entry. One def for
## both would force a species to carry a stage ladder it has no use for.
##
## **Tiers are data, not behaviour.** `tier` answers only "is this one remembered"; what
## it does in a room is read from `stages` and `tags`, never from an `if tier == major`.

## The stable identity across saves. The roster keys on this, never on a display name.
@export var npc_id: StringName = &""

@export var display_name: String = ""

## The species this individual is built from. The module never names `WorldInhabitantDef`
## (that is `world`'s type); it records the id and `app/` resolves it, so `npc` never
## declares a dependency on `world`.
@export var inhabitant_id: StringName = &""

## The authored tier. An untracked def has no roster entry and leaves no trace.
@export var tier: StringName = NpcTier.DEFAULT

@export var faction: StringName = &""
@export var tags: Array[StringName] = []

## The realm the individual starts at, so a rival cultivator is a rival *cultivator* and
## not a mob with a name. Authored, exactly as a boss seed authors its realm (ADR 0074).
@export var realm_id: StringName = &""

## Base attributes for this individual, before any realm or stage scale. An empty map
## falls back to the species'.
@export var base: Dictionary = {}

## The stage ladder, authored in order.
@export var stages: Array[NpcStageDef] = []

## Where this individual starts. Must be a stage this def declares, or the first one.
@export var initial_stage: StringName = &""

## ## The custody term this individual may be TAKEN on (ADR 0247)
##
## An empty `capture_term` means **this individual is not capturable at all** — not "capturable
## with a default". So capturability is CONTENT, and a cast that authors no term ships a custody
## page whose primary verb has nothing to press rather than a free grab with no cause.
##
## It is a TERM and a COUNT OF PERIODS, exactly as ADR 0104 defines a custody claim, and never a
## price: there is no `RARITY_WEIGHT` on a person and no realm scaling behind these two fields.
## Mechanical and clinical, like every other field on this def.
@export var capture_term: StringName = &""

## The periods this individual is owed when taken. Zero falls back to a single authored period
## at the seam, so a half-authored term is a one-period claim and fails as `no_terms` rather than
## as a capture with no term at all.
@export var capture_periods: int = 0


## Whether this individual may be taken at all: a def authors a custody term, or it is not
## capturable. One question, one conjunction, so nothing can be capturable by accident.
func capturable() -> bool:
	return capture_term != &""


## This def's capture beat as primitives, or `{}` when it is not capturable. The shape is
## `{term_id, periods}` and nothing else — no prose field, because ADR 0104's rule that a custody
## record carries no `description`, `flavor` or `display_name` holds on the AUTHORED side too.
func capture_term_row() -> Dictionary:
	if not capturable():
		return {}
	return {"term_id": String(capture_term), "periods": maxi(1, capture_periods)}


func tracked() -> bool:
	return NpcTier.is_tracked(NpcTier.normalize(tier))


func normalized_tier() -> StringName:
	return NpcTier.normalize(tier)


## The stage def for `stage_id`, or null. Null rather than a guess: a gate that silently
## fell through to the first stage would let a half-authored def open everything.
func stage(stage_id: StringName) -> NpcStageDef:
	for stage_def in stages:
		if stage_def.stage_id == stage_id:
			return stage_def
	return null


func stage_index_of(stage_id: StringName) -> int:
	for stage_def in stages:
		if stage_def.stage_id == stage_id:
			return stage_def.index
	return -1


## The stage this individual is born at, resolving an unset `initial_stage` to the first
## authored stage.
func starting_stage_id() -> StringName:
	if initial_stage != &"" and stage(initial_stage) != null:
		return initial_stage
	if stages.is_empty():
		return &""
	return stages[0].stage_id


## The stage that follows `stage_id`, or an empty id when this is the end of the ladder.
## One step, never a loop: a caller walks the ladder or stops.
func next_stage_id(stage_id: StringName) -> StringName:
	var current := stage_index_of(stage_id)
	if current < 0:
		return starting_stage_id()
	for stage_def in stages:
		if stage_def.index > current:
			return stage_def.stage_id
	return &""


func stage_count() -> int:
	return stages.size()
