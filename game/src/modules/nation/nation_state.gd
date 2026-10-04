class_name NationState
extends RefCounted

## The versioned nation ledger, stored as a plain dictionary under
## `actor.module_data["nation_state"]` (ADR 0027 pattern). Core persists it
## without ever naming a nation type.
##
## ## What this ledger is
##
## **One polity as lived from inside**, not the world's map: which nation the actor
## lives under, the claims it holds, how it stands with every other nation, who
## holds each seat, and the standoffs it is in. A nation outlives any one member
## and ADR 0083 records where a polity-WIDE ledger lives as an open decision; this
## one is scoped so that question can be answered later without a migration.
##
## ## String keys throughout, and no Resource, Actor or StringName inner key
##
## `Actor.to_dict` converts only the OUTER `module_data` key with `String(key)`.
## An inner `StringName` key reaches the save untouched and breaks every round
## trip, and a `Resource` or `Actor` does the same. No checker in this repo can see
## it, so the discipline is written by hand and pinned by a JSON round trip in
## `test_nation_state.gd`.
##
## ## A stance is ONE row per UNORDERED pair
##
## The key is the two institution ids ordered lexicographically and joined, so a
## read with the ids swapped returns the identical dictionary and a one-sided
## opinion is structurally impossible rather than merely forbidden. This is ADR
## 0047's symmetry, extended by ADR 0085 to every tier and made STRUCTURAL: there
## is no way to write the reversed key, so there is no second writer to check.
##
## ## An office with no holder is a row with `""`, not a missing row
##
## ADR 0083's three-state vocabulary: `{}` means it does not exist,
## `"vacant": true` means it exists and its value is absent, and
## `{"ok": false, "reason": R}` means the action is refused. A vacancy is never `0`,
## never `"-"` and never a hidden row — a nation that renders an unfilled seat as
## zero has destroyed the succession design, which exists to make a vacancy legible.

const SCHEMA_VERSION := 1
## `actor.module_data` key.
const MODULE_KEY := &"nation_state"
## The history trail is a bounded explanation of how the actor came to live under
## this nation, not a full audit log. A save cannot grow without limit.
const HISTORY_LIMIT := 64
## Every stat modifier this module contributes is tagged with this prefix, so a
## re-projection can strip and rebuild the whole contribution from the ledger.
const SOURCE_PREFIX := "nation:"
## The separator joining the two ids of a stance pair into its one canonical key.
## A character that cannot appear in an authored id, so the join is unambiguous
## and the pair can always be split back apart.
const PAIR_SEPARATOR := "|"

## The closed diplomacy verb set (ADR 0085). `war` is IN the set but is reachable
## only through the declaration verb; `set_stance` refuses it as
## `war_requires_a_prize` so no war can exist without a declared prize.
const VERBS: Array[StringName] = [&"rival", &"neutral", &"allied", &"truce", &"embargo", &"war"]

## The standoff modes. A mode changes the quota and the prize shape only, never
## how a verdict is produced (ADR 0085).
const CONTEST := &"contest"
const SIEGE := &"siege"
const TRIBUNAL := &"tribunal"
const MODES: Array[StringName] = [CONTEST, SIEGE, TRIBUNAL]

## The three prize shapes. A prize is DECLARED at declaration and paid verbatim
## at resolution; it is never computed then.
const OWNERSHIP := &"ownership"
const RECOGNITION := &"recognition"
const TRIBUTE := &"tribute"
const TRANSFERS: Array[StringName] = [OWNERSHIP, RECOGNITION, TRIBUTE]

## The refusal reasons this module authors. Collected in one place because a
## refusal is a NAMED game rule, not input validation, and a panel must render a
## reason it did not have to invent (ADR 0084).
const R_NO_ACTOR := "no_actor"
const R_ALREADY_FOUNDED := "already_under_a_nation"
const R_UNKNOWN_NATION := "unknown_nation"
## The actor lives under no nation, so there is nothing to leave or be cast out of.
## Distinct from `unknown_nation`, which names a polity this build does not ship: that
## is a content bug, and this is a player who has not settled anywhere (ADR 0083's
## first state — "no institution" is representable and is the ordinary start).
const R_NO_NATION := "no_nation"
const R_SELF_STANCE := "cannot_stance_against_yourself"
const R_UNKNOWN_VERB := "unknown_verb"
const R_WAR_REQUIRES_A_PRIZE := "war_requires_a_prize"
const R_UNKNOWN_TERRITORY := "unknown_territory"
const R_ALREADY_HELD := "territory_already_held"
const R_CLAIM_FLOOR := "standing_below_floor"
const R_HOLD_FLOOR := "claim_lapsed_below_floor"
const R_NOT_HELD := "territory_not_held"
const R_UNKNOWN_OFFICE := "unknown_office"
const R_SEAT_OCCUPIED := "seat_occupied"
const R_NO_SEATS := "office_has_no_seats"
const R_CAPACITY_FULL := "capacity_full"
const R_UNKNOWN_MODE := "unknown_mode"
const R_UNKNOWN_TRANSFER := "unknown_transfer"
const R_NO_TERRITORY := "standoff_without_a_territory"
const R_ALREADY_AT_WAR := "already_in_a_standoff"
const R_UNKNOWN_STANDOFF := "unknown_standoff"
const R_NOT_A_PARTY := "not_a_party_to_the_standoff"
const R_QUOTA_NOT_MET := "verdict_quota_not_met"
const R_UNKNOWN_WINNER := "unknown_winner"
const R_EXHAUSTED := "side_exhausted"

## ## How a standoff ends
##
## A closed standoff names exactly one of these, and every other answer it gives is
## an `OUTCOME_OPEN`. They are words, not states: a war does not become resolved
## by being counted to a quota in the ledger, it becomes resolved when a caller is
## told it was, which is why there are three names and one `closed` flag rather
## than four flags.
const OUTCOME_OPEN := ""
## The declared quota was met and the declared prize was paid, including the
## transfer. The only outcome that moves ground (ADR 0085).
const OUTCOME_RESOLVED := "resolved"
## A side broke before the quota and stopped fighting. The surrender cost is paid
## and **no ground moves** — the sharpest sentence in ADR 0085.
const OUTCOME_WITHDRAWAL := "withdrawal"
## The war was closed without a winner: the quota was not met and no side broke.
## Nobody is paid and nothing moves, because inventing a victory is the one thing
## this module may not do.
const OUTCOME_STALEMATE := "stalemate"
const OUTCOMES: Array[StringName] = [OUTCOME_RESOLVED, OUTCOME_WITHDRAWAL, OUTCOME_STALEMATE]

## The keys a resolution reports, in one place, because they are read by every
## caller of `resolve_conflict` on every stage of a war and a payload that changes
## shape with the stage cannot be read.
const VERDICT_KEYS: Array[String] = [
	"standoff_id",
	"closed",
	"outcome",
	"winner_id",
	"loser_id",
	"verdicts",
	"standing_gained",
	"standing_lost",
	"territory_transferred",
]


## The stat source id one nation contributes under.
static func source_for(nation_id: StringName) -> StringName:
	return StringName("%s%s" % [SOURCE_PREFIX, nation_id])


## True when a stat modifier source belongs to this module.
static func is_own_source(source: StringName) -> bool:
	return String(source).begins_with(SOURCE_PREFIX)


## The empty ledger.
static func empty() -> Dictionary:
	return normalize({})


## The canonical stance key for an unordered pair: the two ids ordered
## lexicographically, joined. Swapping the arguments cannot produce a different
## key, which is the whole structural claim.
static func pair_key(a_id: StringName, b_id: StringName) -> String:
	var first := String(a_id)
	var second := String(b_id)
	return first + PAIR_SEPARATOR + second if first <= second else second + PAIR_SEPARATOR + first


## Both ids of a canonical pair key, as the ordered pair they stand for.
static func split_pair_key(key: String) -> Array[String]:
	var parts := key.split(PAIR_SEPARATOR, false, 1)
	if parts.size() != 2:
		return []
	return [String(parts[0]), String(parts[1])]


## A refusal, in ADR 0083's third state: the action EXISTS and is refused. Never a
## `0`, never a `""` a caller has to interpret, and never a UI string — `reason` is
## an authored constant above, and `detail` carries the authored ids it concerns.
static func refuse(reason: String, detail: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": reason}
	for key in detail.keys():
		out[String(key)] = detail[key]
	return out


## A known-content filter for this module. `known_ids` carries the territory ids
## and office ids the build ships, keyed by id. A claim or a seat naming content
## that no longer ships is dropped rather than persisted, so a save from a wider
## content build cannot smuggle in a claim the current build does not define.
##
## Four rules, and the third is the one that earns its cost:
##   1. An empty payload returns the full skeleton immediately, never a partial.
##   2. **A payload that cannot be read is diagnosed as empty, never partially
##      applied** — half a ledger is worse than none, because it silently changes
##      what the actor is owed.
##   3. An entry naming content the build does not ship is dropped.
##   4. Every field is coerced on the way in, so a corrupt save cannot inject a
##      wrong type into the projection.
##
## `standoffs` is deliberately NOT filtered: a standoff is a political object, not
## content, and an open one must survive even if the territory it was declared over
## has since been deleted. A dangling one is refused at resolution with a named
## reason instead of being silently deleted under a player's feet.
static func normalize(payload: Dictionary, known_ids: Dictionary = {}) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION,
		"nation_id": "",
		"sequence": 0,
		"standing": 0,
		"standing_cap": 100,
		"claims": {},
		"stances": {},
		"offices": {},
		"standoffs": {},
		"applied_percent": {},
		"history": [],
	}
	if payload.is_empty():
		return out
	var data := payload as Dictionary

	out["nation_id"] = String(data.get("nation_id", ""))
	out["sequence"] = maxi(0, int(data.get("sequence", 0)))
	var cap := maxi(1, int(data.get("standing_cap", 100)))
	out["standing_cap"] = cap
	out["standing"] = clampi(int(data.get("standing", 0)), 0, cap)

	var claims = data.get("claims", {})
	if claims is Dictionary:
		for territory_id in (claims as Dictionary).keys():
			var key := String(territory_id)
			if not _known(key, known_ids):
				continue
			var entry = (claims as Dictionary)[territory_id]
			var claim := _claim_entry(entry)
			if claim.is_empty():
				continue
			out["claims"][key] = claim

	# A stance row is written under ONE key and read under either. A payload
	# carrying the same pair in both orders is a one-sided opinion by another name,
	# so the reversed key is folded into the canonical one rather than kept beside
	# it: whichever row sorts first wins, and the loser is never persisted.
	var stances = data.get("stances", {})
	if stances is Dictionary:
		# A fresh map, NOT `out["stances"]`. Mutating the skeleton's own dictionary
		# while iterating the payload's keys means a reversed duplicate is collapsed
		# onto the canonical key AND left where it was — so `normalize` would claim
		# to fold the pair and still hand back both rows. Rebuilding is what makes
		# "one row per unordered pair" true of the OUTPUT rather than of the input.
		var rebuilt: Dictionary = {}
		for raw_key in (stances as Dictionary).keys():
			var pair := split_pair_key(String(raw_key))
			if pair.size() != 2 or pair[0] == pair[1]:
				continue
			var entry = (stances as Dictionary)[raw_key]
			if not (entry is Dictionary):
				continue
			var key := pair_key(StringName(pair[0]), StringName(pair[1]))
			if not rebuilt.has(key):
				rebuilt[key] = _stance_entry(entry as Dictionary)
		out["stances"] = rebuilt

	var offices = data.get("offices", {})
	if offices is Dictionary:
		for office_id in (offices as Dictionary).keys():
			var key := String(office_id)
			if not _known(key, known_ids):
				continue
			var holder = (offices as Dictionary)[office_id]
			if not (holder is String):
				continue
			out["offices"][key] = String(holder)

	var standoffs = data.get("standoffs", {})
	if standoffs is Dictionary:
		for standoff_id in (standoffs as Dictionary).keys():
			var entry = (standoffs as Dictionary)[standoff_id]
			if not (entry is Dictionary):
				continue
			var standoff := _standoff_entry(entry as Dictionary)
			if standoff.is_empty():
				continue
			out["standoffs"][String(standoff_id)] = standoff

	# What the projection last applied. A `StatModifier` cannot be lowered by a
	# stripped base attribute and `remove_modifiers_from` only knows a source tag,
	# so a rebuild has to know what it previously added. This is `RaceState`'s
	# `applied_race` / `granted` pair, verbatim. Deliberately NOT filtered: a
	# deleted `.tres` still has to be subtracted, and losing a seat is exactly when
	# it would otherwise be left behind.
	var applied = data.get("applied_percent", {})
	if applied is Dictionary:
		for stat_id in (applied as Dictionary).keys():
			var value = (applied as Dictionary)[stat_id]
			if value is float or value is int:
				out["applied_percent"][String(stat_id)] = float(value)

	var history = data.get("history", [])
	if history is Array:
		for record in history as Array:
			if record is Dictionary:
				out["history"].append((record as Dictionary).duplicate(true))
			if out["history"].size() >= HISTORY_LIMIT:
				break
	return out


## The nation the actor lives under, or `""` when they live under none. Living
## under no nation is the normal starting state (ADR 0083), not a failure: the
## three tiers are not nested, and "no institution" must be representable.
static func nation_id(ledger: Dictionary) -> StringName:
	return StringName(String(ledger.get("nation_id", "")))


## Whether the ledger names a nation at all.
static func founded(ledger: Dictionary) -> bool:
	return String(ledger.get("nation_id", "")) != ""


## The standing floor a claim must clear, as a normalized share of the cap.
static func normalized_standing(ledger: Dictionary) -> float:
	var cap := int(ledger.get("standing_cap", 0))
	if cap <= 0:
		return 0.0
	return clampf(float(ledger.get("standing", 0)) / float(cap), 0.0, 1.0)


## The holder of a territory claim, or `""` when nobody holds it. An unheld claim
## is NOT a vacancy — `{}` in `claims` means it does not exist, and a claim that
## exists with no holder is a claim that was declared and abandoned.
static func holder_of(ledger: Dictionary, territory_id: StringName) -> String:
	var entry = (ledger.get("claims", {}) as Dictionary).get(String(territory_id), null)
	if not (entry is Dictionary):
		return ""
	return String((entry as Dictionary).get("holder_id", ""))


## The one canonical stance row for a pair, whichever order the ids are given.
static func stance(ledger: Dictionary, a_id: StringName, b_id: StringName) -> Dictionary:
	var entry = (ledger.get("stances", {}) as Dictionary).get(pair_key(a_id, b_id), null)
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}


## The office id → holder row. A holder of `""` is a VACANT seat: the row exists,
## the value is absent, and `summary()` reports it as `"vacant": true` (ADR 0083).
static func offices(ledger: Dictionary) -> Dictionary:
	return (ledger.get("offices", {}) as Dictionary).duplicate(true)


## The next sequence number. Strictly increasing, so history and ledger order are
## the same order after a restore as they were before it.
static func next_sequence(ledger: Dictionary) -> int:
	return maxi(0, int(ledger.get("sequence", 0))) + 1


## Whether `verb` is one of the closed diplomacy set.
static func is_verb(verb: String) -> bool:
	return VERBS.has(StringName(verb))


## Whether `mode` is one of the declared standoff modes.
static func is_mode(mode: String) -> bool:
	return MODES.has(StringName(mode))


## ## The ONE shape a resolution reports
##
## Every key of `VERDICT_KEYS`, present whatever the war has decided so far, with
## the value this stage means. A verdict is read in three stages — it arrived and
## the war is still being fought, it closed the war, or it arrived after the war
## was already closed — and a caller must ask the same questions of all three. It
## used to be handed a different key set for each, so `closed` and `outcome` were
## absent from everything but the last, and `standing_gained` was absent from
## everything but the second and third. Reading either of them was a runtime error
## rather than an answer, which is how four assertions in `test_nation_conflict.gd`
## came to abort their bodies while their suite reported green.
##
## `detail` carries what the CALLER knows that the standoff cannot: the id it asked
## about, and the standing a settlement just paid. It wins the merge, because those
## are its own facts. Everything else is this stage's answer, which is why a caller
## that only ever reads this cannot be surprised by an absent key.
static func verdict_view(
	standoff: Dictionary, closed: bool, outcome: String, detail: Dictionary = {}
) -> Dictionary:
	var loser := String(detail.get("loser_id", ""))
	var stored: Dictionary = standoff.get("sides", {}) as Dictionary
	var view := {
		"closed": closed,
		"outcome": outcome,
		"winner_id": String(detail.get("winner_id", "")),
		"loser_id": loser,
		"verdicts": int((stored[loser] as Dictionary).get("lost", 0)) if loser != "" else 0,
		# Nothing is paid and nothing moves until a war actually ends, which is what
		# an open war means and what a stalemate means once it has.
		"standing_gained": 0,
		"standing_lost": 0,
		"territory_transferred": String(detail.get("territory_transferred", "")),
	}
	view.merge(detail, true)
	return view


## Whether the injected verdict ends this war NOW rather than on its declared quota,
## and under what name. `OUTCOME_OPEN` means the quota decides, which is ordinary.
##
## Only a LOSING side that is already broken ends a war early, as a `withdrawal`: it
## did not win the war it is standing in, and it cannot be paid a victory it did not
## take. A caller naming an outcome for a war the quota has not decided gets a
## `stalemate` instead — closed, unpaid, no ground moved — because a quota is a
## declaration both sides agreed to, and letting one of them rewrite it at resolution
## is how a declaration stops being one.
static func forced_close(
	standoff: Dictionary, loser: String, forced: String, break_at: float
) -> String:
	if loser == "":
		return OUTCOME_STALEMATE
	var exhausted := float((standoff.get("sides", {}) as Dictionary)[loser].get("exhaustion", 0.0))
	if exhausted >= break_at:
		return OUTCOME_WITHDRAWAL
	if forced != "":
		return OUTCOME_STALEMATE
	return OUTCOME_OPEN


static func _known(key: String, known_ids: Dictionary) -> bool:
	return known_ids.is_empty() or known_ids.has(key)


static func _claim_entry(entry) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	var data := entry as Dictionary
	var territory_id := String(data.get("territory_id", ""))
	if territory_id == "":
		return {}
	var out := {
		"territory_id": territory_id,
		"holder_id": String(data.get("holder_id", "")),
		"held_since": int(data.get("held_since", 0)),
		"tier_index": int(data.get("tier_index", 0)),
		"challenger_id": "",
		"yield_accrued": maxi(0, int(data.get("yield_accrued", 0))),
	}
	# A challenger is an id, never a number. The default is a DENIAL (`""`), which
	# is ADR 0083's first state: this claim has no challenger, and the row still
	# says so rather than omitting the key.
	out["challenger_id"] = String(data.get("challenger_id", ""))
	return out


static func _stance_entry(entry: Dictionary) -> Dictionary:
	return {
		"verb": String(entry.get("verb", "")),
		"other_id": String(entry.get("other_id", "")),
		"sequence": int(entry.get("sequence", 0)),
	}


## A standoff, normalized field by field. **The prize is preserved field for
## field**, because it was declared and not computed: keeping what the two sides
## agreed to through a save is what makes the declaration the authority rather than
## a hint that resolution re-derives. `standoff_id` and `territory_id` are carried
## as data rather than left implicit in the map key, so a resolve never has to
## re-parse an id to learn what the standoff was over.
static func _standoff_entry(entry: Dictionary) -> Dictionary:
	var sides = entry.get("sides", {})
	var normalized_sides := {}
	if sides is Dictionary:
		for side_id in (sides as Dictionary).keys():
			normalized_sides[String(side_id)] = _side_entry((sides as Dictionary)[side_id])
	var out := {
		"standoff_id": String(entry.get("standoff_id", "")),
		"other_id": String(entry.get("other_id", "")),
		"territory_id": String(entry.get("territory_id", "")),
		"mode": String(entry.get("mode", "")),
		"quota": maxi(1, int(entry.get("quota", 1))),
		"winner_id": String(entry.get("winner_id", "")),
		"outcome": String(entry.get("outcome", "")),
		"closed": bool(entry.get("closed", false)),
		"declared_sequence": int(entry.get("declared_sequence", 0)),
		"sides": normalized_sides,
		"prize": _prize_entry(entry.get("prize", {})),
	}
	var tributes = entry.get("tributes", {})
	var out_tributes := {}
	if tributes is Dictionary:
		for side_id in (tributes as Dictionary).keys():
			out_tributes[String(side_id)] = maxi(0, int((tributes as Dictionary)[side_id]))
	out["tributes"] = out_tributes
	return out


static func _side_entry(entry) -> Dictionary:
	if not (entry is Dictionary):
		return {"won": 0, "lost": 0, "exhaustion": 0.0}
	var data := entry as Dictionary
	return {
		"won": maxi(0, int(data.get("won", 0))),
		"lost": maxi(0, int(data.get("lost", 0))),
		"exhaustion": maxf(0.0, float(data.get("exhaustion", 0.0))),
	}


## The declared prize, preserved field for field. An unknown transfer kind is
## DROPPED rather than defaulted: a prize nobody declared is not a prize anybody
## pays, and defaulting it would invent the one thing ADR 0085 forbids inventing.
## A prize with no transfer at all is kept with an empty `transfer`, because the
## two sides declaring "nothing moves, only standing" is a legal declaration.
static func _prize_entry(prize) -> Dictionary:
	if not (prize is Dictionary):
		return {}
	var data := prize as Dictionary
	var transfer := String(data.get("transfer", ""))
	if transfer != "" and not TRANSFERS.has(StringName(transfer)):
		return {}
	var out := {"mode": String(data.get("mode", "")), "transfer": transfer, "standing": {}}
	var standings = data.get("standing", {})
	if standings is Dictionary:
		var rows := {}
		for side_id in (standings as Dictionary).keys():
			rows[String(side_id)] = int((standings as Dictionary)[side_id])
		out["standing"] = rows
	return out
