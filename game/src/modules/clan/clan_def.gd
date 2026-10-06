class_name ClanDef
extends Resource

## One authored clan: a **standing with obligations**, and the recognition vocabulary
## later social features will read (ADR 0064).
##
## A clan is a lineage that persists across generations and holds a position. It is
## NOT `Actor.faction` (ADR 0047) — faction is the political alignment, clan is the
## family. The two answer different questions and are deliberately not unified.
##
## ## `standing_cap` is the AUTHORED CEILING, and it is not the ladder's top
##
## `standing_bands` says what standing **publishes** — which rung that standing reads as.
## `standing_cap` says what the house can **hold**. They are different statements and
## keeping them apart is ADR 0064, not a duplication: the two readings can disagree, and
## that disagreement is the politics (a member may stand far past every published rung and
## still hold nothing, which is a legitimate character and not a data error).
##
## So `standing_cap` **does not clamp `ClanState.standing`**, and a member's earned number
## is never silently truncated by a content field. What it bounds is the RATIO: it is the
## `standing_cap` a claim built from this ledger carries, so
## `InstitutionClaim.normalized()` is a computable ratio rather than a division against a
## default this def never authored (the gap ADR 0083's one claim shape leaves otherwise).
##
## **The shipped default sits BELOW all three shipped top bands** — 100 against ironpact's
## 120, saltledger's 150 and quiethouse's 160 — which is safe for exactly one reason: nothing
## clamps. A house whose ladder reaches past the ceiling must author its own, and the `.tres`
## edit that does it is named in `docs/deferred.jsonl` rather than guessed at here, because
## a value above every ladder would be a constant no content justifies.
##
## ## A clan grants recognition, never power
##
## **This Resource has no stat-granting field, and that is the design.** There is no
## `percent_modifiers`, no `base_attributes`, no `grants`. Every sibling lineage module
## has one; this one deliberately does not. A clan that handed out a combat number
## would be a second way to buy power, and the recognition a clan actually confers —
## *who will vouch for you* — is worth more in a reputation system than in a modifier
## stack. The founding bloodline below is read as a **standing multiplier** by the
## social layer, never as a stat the clan grants (see ADR 0064).
##
## ## Standing and rank are two numbers
##
## `standing_bands` is the *published* mapping from a standing threshold to the rank a
## band implies. It is the same length as `ranks`: `standing_bands[i]` is the standing
## at which the clan regards `ranks[i]` as the earned floor, ascending. Equal length
## rather than one shorter because the lowest band is a real statement ("you are an
## outer member at 0 standing") rather than an implicit default, and an author who
## wants a different floor moves the first number instead of counting bands.
##
## **The ledger does not apply this mapping.** `rank_for_standing` is the *display*
## answer — what rank this standing would justify — and a clan screen may show it next
## to the rank the member actually holds. The stored rank is written by the clan, and
## the gap between the two IS the politics ADR 0064 exists to leave room for.
##
## Adding a clan is authoring a `.tres` under `game/data/clans/`, never code.

@export var id: StringName = &""
@export var display_name: String = ""
## Clinical and mechanical, in the game's own voice. A clan here feeds the
## succubus/birth and social systems, so this copy describes institutions, terms and
## obligations and nothing else (AGENTS.md).
@export var description: String = ""

## The bloodline this clan was founded on, or `&""` when it claims no founding line.
## Read on a member as a standing multiplier and named on a clan screen; never
## granted, and admission may only ever require the member to already carry it.
@export var founding_bloodline: StringName = &""

## Positions within the clan, ordered low to high. The conventional ladder is
## `outer, inner, core, heir, head`; an author may shorten it, never lengthen it past
## the bands it publishes.
@export var ranks: Array[StringName] = []
## Thresholds separating `ranks`, same length as `ranks`, ascending. See the class
## note for why equal length is the chosen convention.
@export var standing_bands: Array[int] = []

## What this clan owes a member: PUBLISHED TERMS ONLY. A screen renders these; nothing
## in this module pays them. The settlement verb belongs to the social features that
## land later (ADR 0064), so a term is a promise the world can betray, not a script.
@export var patronage: Dictionary = {}
## What the member owes this clan: PUBLISHED TERMS ONLY, and equally unenforced.
@export var duty: Dictionary = {}

## Clans this one is opposed to. Antagonism is authored data so the world reads it as
## a relationship rather than inferring it from shared tags.
@export var rival_clans: Array[StringName] = []
@export var tags: Array[StringName] = []

## The ceiling an `InstitutionClaim` built from this house's ledger clamps against, and
## the denominator of its `normalized()` ratio. **Never a clamp on `ClanState.standing`** —
## see the class note, and `test_clan_migration.gd` for the shipped content this default
## sits below.
@export var standing_cap: int = 100

# --- Admission ---------------------------------------------------------------

## Concentration the member must already carry of `founding_bloodline` to be admitted.
## 0.0 admits anyone. **Passing this gate never raises purity** (ADR 0063) — a clan
## cannot manufacture a lineage it does not have, it can only recognise one.
@export var min_purity: float = 0.0
## Body plan the member must have, or `&""` when the clan takes any. Also a
## *recognition* requirement: it narrows who can vouch for whom, it never changes what
## the body can do.
@export var required_race: StringName = &""
## Realm ordinal the member must already have reached, or 0 for no floor.
@export var min_realm: int = 0


## The rank this standing would justify on a published reading — `ranks[0]` below the
## first band, and the top rank at or above the last. Pure and deterministic: no
## actor, no catalog, no state.
##
## This is NOT how the ledger resolves a member's rank; see the class note.
func rank_for_standing(standing: int) -> StringName:
	if ranks.is_empty():
		return &""
	var found := ranks[0]
	var value := maxi(0, standing)
	for index in mini(standing_bands.size(), ranks.size()):
		if value >= standing_bands[index]:
			found = ranks[index]
	return found


## The position `rank` names, or -1 when this clan publishes no such position. An
## unknown rank index is -1 rather than 0 so a caller cannot mistake "core" for the
## bottom of the ladder by accident.
func rank_index(rank: StringName) -> int:
	return ranks.find(rank)


## The lowest published position. A new member's default, and the only rank the
## admission path itself ever grants.
func entry_rank() -> StringName:
	return ranks[0] if not ranks.is_empty() else &""


## Whether `rank` is a position this clan publishes.
func has_rank(rank: StringName) -> bool:
	return ranks.has(rank)


## Whether `clan_id` is one this clan names as a rival. One-directional by design: the
## relationship is authored on both sides or on one, and a caller that wants symmetry
## asks both.
func is_rival_of(clan_id: StringName) -> bool:
	return rival_clans.has(clan_id)


## How many rival houses this clan names. A published measure of how embedded in the
## politics it is, and the bound the provider clamps against.
func rival_count() -> int:
	return rival_clans.size()


## How many terms each side of the ledger publishes. Zero on both is legal — a clan
## that owes nothing and asks nothing is a content choice, not a parse failure.
func patronage_count() -> int:
	return patronage.size()


func duty_count() -> int:
	return duty.size()


## The stat source id this clan would contribute under. Namespaced, so a future
## recognition grant can be found and rebuilt from the ledger without guessing. **No
## `StatModifier` is ever built under it** — see the class note.
func source_id() -> StringName:
	return ClanState.source_for(id)
