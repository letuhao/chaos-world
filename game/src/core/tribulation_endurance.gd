class_name TribulationEndurance
extends RefCounted

## The share of tribulations this actor survives, and the one roll that decides a
## fight (ADR 0020/0041/0061).
##
## ONE curve, in `core`, for the same reason `RealmRate` is (ADR 0066): the roll
## is a mechanic, not a module's business, and a second copy of these five numbers
## is a second answer to "how often does this actor survive a tribulation". It is
## the ONLY answer: `Tribulation.endurance` was a second one, reachable from no
## `src/` caller, and is deleted (ADR 0125).
##
## `TribulationFight`'s twin is deleted too: the module now descends waves through
## `Tribulation.fight_wave` — the same verb `Breakthrough.face_tribulation` calls —
## so a fight costs `WAVE_TOLL` however the player started it.
##
## It deliberately does NOT read `Stat.BREAKTHROUGH_CHANCE`, for the reason ADR 0028
## gives: that stat is derived from the comprehension the entry gate already pins, so
## at R19+ it is past its clamp on every attempt and the fight would be certain.

## The bounds and the slope are `Tribulation`'s, not restated here: the record owns
## the rating, so it owns the range that rating is spent across, and a second copy of
## the five numbers is a second answer to "how often does this actor survive". This
## file adds the one term the record cannot know — the actor's own dao heart.
const MIN_ENDURANCE := Tribulation.MIN_ENDURANCE
const MAX_ENDURANCE := Tribulation.MAX_ENDURANCE
## One point of the actor's own dao heart is this much of the span.
const DAO_HEART_TO_ENDURANCE := 0.01
## What one point of a fight's rating is worth, off `Tribulation`'s span. The span
## itself is not re-declared here: an alias nothing reads is a second name for the
## same number, which is how the two answers to this question got started.
const RATING_TO_ENDURANCE := Tribulation.ENDURANCE_PER_RATING


## The share of fights this actor survives against the price of this one.
##
## `record` is the fight being rated. Null prices the tribulation this actor's
## lowest owed realm would carry, measured on a throwaway record, so a screen can
## price a fight before it begins and the number does not depend on the caller
## remembering to start one.
static func endurance(actor: Actor, record: Tribulation = null) -> float:
	return clampf(
		(
			MIN_ENDURANCE
			+ _dao_heart(actor) * DAO_HEART_TO_ENDURANCE
			- _price(actor, record) * RATING_TO_ENDURANCE
		),
		MIN_ENDURANCE,
		MAX_ENDURANCE
	)


## Decide one fight, from one draw. `rng` makes the roll a caller's choice rather
## than a hope; null uses the engine's. This is the ONLY place a tribulation is
## decided from a random number, so there is exactly one answer to "did this actor
## survive" and `TribulationFight`'s twin can delete.
static func survives(actor: Actor, record: Tribulation, rng: RandomNumberGenerator = null) -> bool:
	var draw := randf() if rng == null else rng.randf()
	return draw < endurance(actor, record)


static func _dao_heart(actor: Actor) -> float:
	return actor.stats.get_base(Stat.COMPREHENSION)


## What this fight is fought at: the live record's own rating while one is running,
## otherwise the rating the actor's lowest owed tribulation would carry. Reading a
## record never writes to it, so this is a read.
static func _price(actor: Actor, record: Tribulation) -> float:
	if record != null:
		return record.difficulty
	if actor.tribulation != null and not actor.tribulation.is_complete():
		return actor.tribulation.difficulty
	var realm_id := Breakthrough.owed_realm(actor)
	if realm_id == &"":
		return 0.0
	var provisional := Tribulation.new()
	provisional.start(actor, realm_id)
	return provisional.difficulty
