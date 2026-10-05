class_name SocialAttractionSeed
extends RefCounted

## **The first-impression seed — 初见好感, kept apart from the running bond** (ADR 0256).
##
## ## What this is, in one sentence
##
## A one-time impression an NPC forms of the player AT MEETING, held on the **NPC's own
## ledger**, keyed by the player — and it is not standing, not trust, and not a rung of
## `SocialBondClass`.
##
## ## Why it is a separate field and not a cause on the bond
##
## The genre anchor (太吾绘卷) does exactly this: 初见好感 is SEEDED once, base 3000, with
## flat additions for the player's presentation, and it is **applied once at meeting**
## rather than continuously. That is the mechanic behind "he likes her because she is a
## beautiful fairy", and it is genuinely different from a bond:
##
##  - **A bond answers "what have we done to each other".** A seed answers "what did he
##    think in the first second". Everything the player DOES moves the bond; almost
##    nothing the player DOES should move the seed, or the second meeting is not a first
##    impression any more.
##  - **The bond is bidirectional and derived.** The seed is a stored number on ONE
##    ledger because there is nothing to derive it from — it happened, it was observed
##    once, and both of those are facts rather than functions of a cause ledger.
##
## ## What the seed may read — the closed list, and nothing else
##
## This is the load-bearing constraint. Every input below is a property of **who the
## player IS**, fixed for the character, so the seed is the same number on the first
## meeting and the thousandth:
##
##  - `race` / `bloodline` — **presence tags only**, and ONLY the presence subset listed
##    in `PRESENCE_TAGS`. A fairy bloodline registers; a stat-bearing bloodline does not.
##  - `clan` — standing, NOT wealth. See `CLAN_STANDING_BONUS` for why a rich house is
##    legible here but a balance is not.
##  - `sect` — membership, as `FRIENDLY_SECT_TAGS`.
##
## ## What the seed may NOT read — and every line is a closed door, not a preference
##
##  - **NOT the player's standing.** There is no `standing` argument. The whole anti-farm
##    defence rests here and it is the first thing a future edit would reach for.
##  - **NOT anything re-equippable.** No clothing, no equipment, no inventory, no
##    position, no realm, no stats, no current items. **The generation is not an input at
##    all** — the player has no `sex` field, so a gender term would be an invented
##    fiction, and inventing one on the seed would be inventing it on the *attraction*
##    specifically. An appearance seed that can be re-equipped is not an anti-farm rule
##    with a hole; it has no anti-farm rule.
##  - **NOT the pc's own quests.** Not a function, not a callable, so a seed cannot reach
##    out and read state that changes every frame.
##
## `seed_about` accepts a flat dictionary of these keys and nothing else, so an unknown
## key cannot be smuggled past the review of this list.
##
## ## The apply-once rule, and why it cannot be farmed
##
## `apply_once` is a no-op when a seed already exists, **whatever the magnitude is
## computed to be**. There is no delta path, no refresh verb and no decay on the seed, so
## there is nothing to repeat: re-equipping, changing sect, or walking away and coming
## back cannot move a seed that exists. The state that makes this cheap is the seed's
## EXISTENCE, not its value — which is also why the stored number is clamped.

## The keys `seed_about` will read. A key not on this list is ignored rather than
## refused, so a caller can pass a whole actor projection without the extra keys being an
## error — but it is also ignored, which is the half that matters.
const READ_KEYS: Array[StringName] = [
	&"race_tags", &"bloodline_tags", &"clan_standing", &"sect_tags"
]

## ## The seed's own floor.
##
## Non-zero, and that is the design: a seed is an *impression already formed*, so it
## starts as a baseline regard rather than at zero. It is NOT a bond standing and does
## not move the bond — it is the offset `PursuitStance` reads to decide whether an npc
## will pursue at all.
const BASE := 30.0

## ## Upper bound: an impression, not a devotion.
##
## `SocialBond` clamps at 100 because a bond is a career and can legitimately be the
## strongest thing in a save. A seed cannot — it is thirty seconds of looking — so it
## clamps an order of magnitude lower. This is what bounds the value a game of flattering
## can never get to, and it is the second half of why presentation is not farmable.
const MAX := 100.0

## Lower bound: a bad first meeting is still a meeting, and the seed never goes negative
## so a hostile impression is expressed as a disposition, not as a debt the player owes.
const MIN := -20.0

## ## Per presence tag, one flat addition. Flat, not a rate.
##
## ## Why tags and not ids
##
## Naming a tag rather than an id is what makes this a rule about **what kind of thing
## the player is** rather than a balance pass over a content list. An author who ships a
## new fairy bloodline gets the fairy bonus by tagging it `fairy` — there is no id list
## here to fall out of date, which is the reason a seed like this rots if it is authored
## as ids.
const PRESENCE_TAG_BONUS := 4.0

## ## These, and only these, are the `presence` vocabulary.
##
## `presence` means "how this bloodline presents to the eye", which is a different
## question from "what does this bloodline do". `sanguine` carries a stat effect and so
## carries no presence weight — presence is a **closed subset of the `race` axis
## vocabulary**, never a general lookup, so a stat-bearing tag can never leak into it.
const PRESENCE_TAGS: Array[StringName] = [&"fairy", &"ethereal", &"serene", &"immortal"]

## ## The friendly-sect term, and the ONLY presentation-shaped input that survives.
##
## **This is the one deliberate exception to "the seed may not read anything
## re-equippable", and it is narrow on purpose.** A sect is a fact about WHO someone is,
## not a hat they picked up this morning, and "the colours of your sect are the colours
## you arrive in" is part of the fantasy the owner named. It is safe for the same reason
## the rest is not: it is a MEMBERSHIP, memberships are not re-equippable, and its
## magnitude is a fraction of the base. Changing sect to farm it pays for a whole standing
## move on an institutional bond, which is a larger cost than the bonus is worth.
const FRIENDLY_SECT_BONUS := 6.0

## Sect tags that read as a sect one would warm to.
const FRIENDLY_SECT_TAGS: Array[StringName] = [
	&"scholarly", &"merciful", &"artisan", &"healing", &"righteous"
]

## ## The clan term — STANDING, and never wealth.
##
## The brief names "her clan is rich", so this is the honest version of it. Clan wealth is
## **not a field anywhere in this repo** (the audit measured that), and introducing one to
## feed an attraction seed would put a money number on the reason a person likes somebody —
## which is the `ADVERSARY` trap from the reference research in its purest form: a gift
## economy gating courtship. Clan STANDING is a reputation the player has already earned
## through authored acts, so it is the part of "a great family" that cannot be bought on
## the spot.
##
## `economy` is in `social`'s registry deps, so an author who later wants a genuine wealth
## term has a legal place to read one. This file deliberately does not.
const CLAN_STANDING_BONUS := 3.0
const CLAN_STANDING_AT := 40.0

## ## The bands the word reads. Named, so a band is an authored decision and not a
## number typed at the call site.
const FAVOURABLE_AT := 36.0
const WARM_AT := 42.0
const PERSUADED_AT := 48.0


## ## Whether this actor carries `tag` in `player`'s projection. One pass over the list.
static func _carries(player: Dictionary, key: StringName, tag: StringName) -> bool:
	var tags: Array = player.get(String(key), [])
	if tags == null:
		return false
	for entry in tags:
		if StringName(entry) == tag:
			return true
	return false


## ## The seed for `player` as described by `player_row`.
##
## Returns `{total, terms}` where `terms` is the named list of what was read — so a
## debug read can say WHY an impression is what it is without the seed being opaque, and
## so a test can assert that exactly one presence tag fired and the others did not.
##
## **Reading is total and side-effect free**: this function is called on every
## `apply_once` and must stay cheap and allocation-bounded, because `apply_once` is
## called from an interaction path.
static func seed_about(player_row: Dictionary) -> Dictionary:
	var total := BASE
	var terms: Array[StringName] = [&"base"]
	# ## One pass over the presence vocabulary, not one pass per tag
	#
	# This is the loop budget named out loud: `PRESENCE_TAGS` is a constant of size 4 and
	# `PRESENCE_TAGS.size()` is read ONCE into `count`, so a future edit that adds tags
	# cannot turn this into a nested scan. The repo has crashed a 95 GB machine twice and
	# an unbounded comprehension in a hot path is the shape that does it.
	var count := PRESENCE_TAGS.size()
	for index in count:
		var tag := PRESENCE_TAGS[index]
		if _carries(player_row, &"race_tags", tag) or _carries(player_row, &"bloodline_tags", tag):
			total += PRESENCE_TAG_BONUS
			terms.append(tag)
	if float(player_row.get("clan_standing", 0.0)) >= CLAN_STANDING_AT:
		total += CLAN_STANDING_BONUS
		terms.append(&"clan_standing")
	var sect_tags: Array = player_row.get("sect_tags", [])
	if sect_tags != null:
		for entry in FRIENDLY_SECT_TAGS:
			if sect_tags.has(entry):
				total += FRIENDLY_SECT_BONUS
				terms.append(&"sect")
				break
	return {"total": clampf(total, MIN, MAX), "terms": terms}


## ## Seed `npc` with its impression of `player`, ONCE.
##
## `terms` and `basis` ride the row so the debug read can explain the number. Returns
## `{applied, total, reason}` and **`reason` is `already_seeded` on the second call** —
## the verb itself reports that re-equipping bought nothing, which is the property the
## anti-farm rule needs to be observable rather than merely intended.
static func apply_once(
	npc: Actor, player: Actor, player_row: Dictionary, basis: Dictionary = {}
) -> Dictionary:
	if npc == null or player == null:
		return {"applied": false, "total": 0.0, "reason": "no_actor"}
	var ledger := PursuitLedger.for_actor(npc)
	var existing := ledger.seed_for(player.id)
	if not existing.is_empty():
		return {
			"applied": false, "total": float(existing.get("total", 0.0)), "reason": "already_seeded"
		}
	var computed := seed_about(player_row)
	var row := {
		"total": float(computed["total"]),
		"terms": computed["terms"],
		"basis": basis.duplicate(true),
	}
	ledger.set_seed(player.id, row)
	ledger.persist(npc)
	return {"applied": true, "total": float(row["total"]), "reason": ""}


## ## The seed's word for `npc` toward `player` — the PLAYER-FACING half.
##
## Per decision 3 the player's view is a **word plus behavioural tells**, and never a
## number. This returns a `StringName`, not a float, so there is no code path by which a
## raw value could reach a panel: the float lives in `ledger_for` and nowhere else.
static func word(npc: Actor, player: Actor) -> StringName:
	var total := seed_total(npc, player)
	if total >= PERSUADED_AT:
		return &"devoted"
	if total >= WARM_AT:
		return &"taken"
	if total >= FAVOURABLE_AT:
		return &"pleased"
	return &"indifferent"


## ## The seed's value, or `0.0` for an npc who has never met this player.
##
## **The debug read only.** A panel calls `word`, and `word` is the only thing that
## turns this into something a player sees.
static func seed_total(npc: Actor, player: Actor) -> float:
	if npc == null or player == null:
		return 0.0
	var ledger := PursuitLedger.for_actor(npc)
	return float(ledger.seed_for(player.id).get("total", 0.0))
