class_name SocialAlignmentMatrix
extends RefCounted

## The alignment matrix: the two authored tables that answer "what kind of person has
## this player been, and how fast does that move a bond?" (ADR 0253).
##
## **Both tables live in THIS file and nowhere else** (ADR 0066). An alignment weight
## and an alignment rate are one tuning problem — a designer retunes "cruel to the
## powerless" and the corrupt band together — so splitting them across a cause
## `Resource` and a provider would produce exactly the two-copies drift ADR 0066 exists
## to prevent. The weights are ALSO the anti-farm boundary: a cause absent from
## `WEIGHTS` is not merely worth zero, it is an act with no moral reading at all.
##
## **Every row is keyed by NAME, never by an index** (ADR 0050). Inserting a cause
## cannot shift another cause's weight.

# --- The axes ------------------------------------------------------------------

## Kept faith. Debts honoured, oaths sworn, ground defended, promises kept. This is the
## 刚正 upright pole: a debt paid and an oath answered.
const JUSTICE := &"justice"
## Spared the weak. Lives spared, pupils taught, the hungry sheltered. The 仁善
## benevolent pole. Spared a life is worth three of these; a gift is worth one.
const MERCY := &"mercy"
## Used the powerless. A supplicant's trust spent, a ward's back broken, a bound
## servant beaten. The 霸道 domineering pole, and the ONLY axis corruption reads.
const DOMINION := &"dominion"

## Canonical axis order, so every published read model is byte-identical.
const AXES: Array[StringName] = [JUSTICE, MERCY, DOMINION]

## The magnitude bound on every axis. Chosen so the axis cannot be pushed to infinity
## by repetition: the taper below means a long career lands a little under one cap, and
## `CORRUPTION_AT` sits a quarter of the way up it.
const AXIS_CAP := 20.0

## How much of the previous repetition of the SAME act still counts. Genre-correct
## (太吾绘卷 falls to ×20% above a threshold; 鬼谷八荒 halves per heart tier) and the
## load-bearing guard against a linear accumulator that trivialises repeated acts.
## Exactly `0.5` so a decay is exact in binary and a test can assert the literal sum.
const REPEAT_TAPER := 0.5

## Distinct causes tracked per actor. Bounds the `seen` ledger in a save: the shipped
## catalog is 34 rows, so this is generous, and a save can never grow an unbounded
## per-actor dictionary. Bounds MEMORY, in a repo that has crashed a 95 GB machine.
const SEEN_LEDGER_LIMIT := 64

# --- Matrix A: the weight table -------------------------------------------------

## cause id → {axis: authored whole-number weight}. Authored, never derived from the
## cause's `standing` and never from its position (ADR 0050) — a −6.0 cause is not
## automatically three units of moral weight, and a market cause is not moral at all.
##
## **`standing` carries no moral reading and this table says so by omission.** No
## `market` cause appears: winning a lot, being outbid, and defaulting are commerce,
## not alignment. That is the same anti-farm argument as the distinct-KIND rule — a
## bidder's hundred auctions must not be a moral career — and it is why the whole
## auction tier is absent rather than merely small.
const WEIGHTS := {
	# --- Justice: promises kept -------------------------------------------
	&"honoured_a_debt": {JUSTICE: 2},
	&"shared_brotherhood": {JUSTICE: 1, MERCY: 1},
	&"accepted_the_oath": {JUSTICE: 1},
	&"witnessed_an_oath": {JUSTICE: 1},
	&"sworn_to_sect": {JUSTICE: 1},
	&"sworn_to_a_clan": {JUSTICE: 1},
	&"defended_territory": {JUSTICE: 2},
	&"fought_for_a_nation": {JUSTICE: 2},
	&"kept_a_guest_safe": {JUSTICE: 1, MERCY: 2},
	# --- Justice broken ---------------------------------------------------
	&"betrayed_oath": {JUSTICE: -4},
	&"betrayed_a_supplicant": {JUSTICE: -3, DOMINION: 2},
	&"defaulted_on_a_bid": {JUSTICE: -3},
	&"slandered": {JUSTICE: -2},
	# --- Mercy: the weak spared -------------------------------------------
	&"spared_in_combat": {MERCY: 3},
	&"protected_from_death": {MERCY: 3},
	&"taught_technique": {MERCY: 2},
	&"sheltered_a_supplicant": {MERCY: 3, DOMINION: -2},
	&"gifted_item": {MERCY: 1},
	&"bound_in_intimacy": {MERCY: 1},
	&"helped_in_combat": {MERCY: 1},
	# --- Mercy refused, and dominion taken ---------------------------------
	&"cruel_to_the_powerless": {MERCY: -3, DOMINION: 3},
	&"killed_their_kin": {MERCY: -4},
	&"attacked_unprovoked": {MERCY: -3, DOMINION: 1},
	&"robbed": {MERCY: -2, DOMINION: 1},
	&"refused_the_oath": {MERCY: -1},
}

# --- Matrix B: the rate table ---------------------------------------------------

## 站 clean — the player has not become a person who uses the powerless.
const CLEAN := &"clean"
## 浊 corrupt — the player has, past `CORRUPTION_AT`.
const CORRUPT := &"corrupt"

## Dominion at which a player reads as corrupt. A quarter of `AXIS_CAP`, and reachable:
## five cruel acts on the powerless clear it while the taper keeps the eighth worth
## almost nothing. A threshold that took forty acts would be a threshold nobody ever
## crossed, which is how 太吾绘卷's ×20% cliff becomes a rule nobody feels.
const CORRUPTION_AT := 5.0

## band → {goodwill: rate, hatred: rate}. The two halves are a PAIR and ship together
## (AGENTS.md's yin-yang rule): corruption makes you worse at earning goodwill AND
## better at earning hatred. Shipping only the second would make corruption strictly
## profitable; shipping only the first would make it a tax with no upside to offset it.
##
## `goodwill` is deliberately 0.5 and not 0.0 — an NPC with a positive bond to you
## still warms, just slower. See `SocialBond.apply_swayed` and ADR 0253's DOS2 section
## for why a corrupt player must never be able to flip an existing relationship.
const RATES := {
	CLEAN: {"goodwill": 1.0, "hatred": 1.0},
	CORRUPT: {"goodwill": 0.5, "hatred": 2.0},
}

## The rate a cause contributes nothing at — the unafflicted baseline, and what trust is
## multiplied by in every band. Trust is deliberately NEVER swayed: a corrupt person can
## still keep a promise, and making trust unswayable stops the corruption band from
## quietly rewriting a confidant bond into an acquaintance.
const NEUTRAL_SWAY := 1.0


## Which band an alignment reads in. Pure function of the DOMINION axis — one axis, one
## threshold, so "when am I corrupt" has a single answer no other table can contradict.
static func band_for(domination: float) -> StringName:
	return CORRUPT if domination >= CORRUPTION_AT else CLEAN


## The rate for one band and one direction. Unknown band and unknown direction both
## return `NEUTRAL_SWAY`, so an author who misspells a band gets a neutral world rather
## than a zeroed one — the same "refuse rather than silently move nothing" shape
## `SocialApi.apply_cause` uses.
static func rate(band: StringName, direction: String) -> float:
	var row: Dictionary = RATES.get(band, {})
	var value := float(row.get(direction, NEUTRAL_SWAY))
	return value if value > 0.0 else NEUTRAL_SWAY


## How far the sway for one band pushes the OTHER direction, in tenths of a stand, so a
## caller can split a cause's signed standing without knowing which band it is in.
## Reads `RATES`, never a second number.
static func hatred_rate(band: StringName) -> float:
	return rate(band, "hatred")


static func goodwill_rate(band: StringName) -> float:
	return rate(band, "goodwill")


## ## What one act contributes to every axis, this time, on this actor
##
## This is the combination rule's only arithmetic. `seen` is how many times THIS cause
## has already moved THIS actor, so the taper is per-actor and per-act — two people who
## each spared one life are not penalised for the world containing the other one.
##
## **Three inputs, one output, no branch that depends on who is asking.** `cause_id`,
## `seen`, `scale`. There is no npc argument because there is no per-NPC weight: one
## player's alignment is read identically by every bond in the world, and the signature
## is what makes that structural rather than a promise (ADR 0253).
static func contribution(cause_id: StringName, seen: int, scale: float) -> Dictionary:
	var authored: Dictionary = WEIGHTS.get(String(cause_id), {})
	var repeats := maxi(0, seen)
	var sway := pow(REPEAT_TAPER, float(repeats)) * maxf(0.0, scale)
	var out := {}
	for axis in AXES:
		out[String(axis)] = float(authored.get(axis, 0)) * sway
	return out


## Whether the catalog ships an act this matrix has a moral reading for. False is a
## legitimate answer — it is how the market tier stays out — so this is a question, not
## a failure.
static func judges(cause_id: StringName) -> bool:
	return WEIGHTS.has(String(cause_id))
