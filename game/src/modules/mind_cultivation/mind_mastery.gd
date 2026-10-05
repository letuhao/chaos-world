class_name MindMastery
extends RefCounted

## TWO mastery tracks, advanced by USE, stored in a `MindMasteryState` component.
##
## ## Mastery is NOT realm rank, and the difference is the whole design
##
## Realm rank answers "how much cultivation has this body absorbed". Mastery
## answers "how much has this mind been FORCED to do something difficult". The
## two are orthogonal by construction here, and that is what gives the track a
## loop rather than a tech tree:
##
## - Realm rank advances on `cultivate` work through a breakthrough gate. It is a
##   ladder, gated, expensive, and paid once per tier.
## - Mastery advances on EVERY act through [method earn]. It is continuous, cheap,
##   paid constantly, and it advances a VECTOR — one entry per channel and per
##   control shape — rather than a single ordinal.
##
## So a deep-realm cultivator who has never CONFRONTED anyone has mastery at zero
## and a first-realm one who has fought a hundred duels has mastery past a deep
## realm's. That is the property a test can pin and a tech tree cannot produce,
## because a tech tree is index-addressed and this is not.
##
## ## The two tracks are NOT two dials on one curve
##
## `status` and `expression` are separate vectors with separate earn sources,
## separate caps and separate ladders, and — the load-bearing part — DIFFERENT
## SPEND CURRENCIES:
##
## - `status` mastery sharpens the CONTEST: it raises `steepness`, so a win is
##   more decisive. It makes the ATTACKER better at imposing, not better at
##   damaging.
## - `expression` mastery sharpens the PROJECTION: it raises `harm`, so what is
##   projected costs more composure. It makes the ATTACKER better at eroding,
##   not better at imposing.
##
## Neither track moves the other's number, and the test suite asserts that
## structurally by advancing one and reading the other's cap. A design where both
## tracks raised `p_land` would have been two names for one curve — which is
## exactly the reskin the owner's brief forbids.
##
## ## The caps are RATES, and the ladders are bounded by construction
##
## Every cap here is under `1.0`, so a mastery that maxes out improves a contest
## without ever making it certain: `steepness` at `1.0` is still
## `clampf(0.5 + edge, 0, 1)`, and `edge` is a RATIO that cannot exceed `1.0`
## however large the gap. This is AGENTS.md's rule that a cap may never bound an
## input — the ladder is bounded at the OUTPUT, which is the one place a bound is
## correct.
##
## ## `THRESHOLD_STEP` is on the EMISSION, not the spend
##
## The ladder is geometric in the track's cap, so a cap of `0.4` takes `0.3` more
## uses to move one step than a cap of `0.1` — effort tracks the size of what you
## are getting good at. It is a small named constant rather than a per-def authored
## number because the ladder is ONE curve for both tracks, the same way
## `RealmRate` is one curve for all three paths: two authored numbers would drift.

## The component key a `MindMasteryState` lives under.
const STATE_COMPONENT := &"mind_mastery"

## The two tracks, restated from the vocabulary both modules share. A caller reads a
## track by name and never indexes a vector by position, so a track added later
## cannot silently renumber the one that shipped. Asserted EQUAL to
## `MindVocabulary.TRACKS` by `test_mind_mastery_streams.gd` rather than trusted,
## because the two lists cannot be merged: one belongs to a contracts value object,
## the other to the module that banks against it.
const TRACK_STATUS := MindVocabulary.TRACK_STATUS
const TRACK_EXPRESSION := MindVocabulary.TRACK_EXPRESSION
const TRACKS: Array[StringName] = MindVocabulary.TRACKS

## Uses a single act must contribute before it counts. Below this an act is a
## gesture, and a gesture that moved mastery would make the ladder a
## click-speed stat.
const MIN_EARN := 0.0

## Uses per ladder step, expressed as a fraction of the track's own cap. See the
## docblock for why the ladder is one curve for both tracks.
const THRESHOLD_STEP := 0.04

## Every channel and control shape a mastery entry may be filed under. The set is
## the AUTHORED vocabulary, so a `.tres` naming a channel nothing projects is
## visible at earn time rather than silently banking into a key nobody reads.
const VOICES: Array[StringName] = MindVocabulary.CHANNELS
const SHAPES: Array[StringName] = MindVocabulary.SHAPES


## The two counters a mastery state carries, keyed by track and then by the
## authored vocabulary id it was earned against. Ordered so `to_dict` is stable.
static func empty_ledger() -> Dictionary:
	return {TRACK_STATUS: {}, TRACK_EXPRESSION: {}}


## The track a def's role belongs to, or `&""`. One mapping, read by [method earn]
## and by the facade, so "which track does this project count toward" cannot be
## answered two ways.
static func track_for(def: MindStatusDef) -> StringName:
	if def == null:
		return &""
	match def.role:
		&"control":
			return TRACK_STATUS
		&"expression", &"composure":
			return TRACK_EXPRESSION
	return &""


## The vocabulary id a def banks mastery under: its control SHAPE for a `control`,
## its channel for an `expression`, and the channel it answers for a `composure`.
## A composure is a defender's answer, so it earns toward the same track its
## projection does — the target's practice at resisting is mastery too.
static func key_for(def: MindStatusDef) -> StringName:
	if def == null:
		return &""
	if def.role == &"control":
		return def.shape()
	return def.channel()


## Whether `id` names something in the authored vocabulary. A caller asking this
## before banking an entry is the difference between a visible authoring error and
## a number nobody ever reads.
static func knows(id: StringName) -> bool:
	return VOICES.has(id) or SHAPES.has(id)


## Bank one act. Returns `{ok, track, key, uses, threshold, step}` so a screen and
## a test read the same outcome rather than re-deriving it.
##
## ## Why this is the ONLY writer of mastery
##
## There is no other verb. Mastery cannot be bought, cannot be granted by a
## breakthrough and cannot be set by a load. It is earned by the act, and the act
## is the contest. That is what makes it a LOOP rather than a tech tree: the only
## way to move a mastery number is to have used the thing.
##
## ## The guard is the vocabulary, not a magnitude check
##
## `MIN_EARN` is `0.0` and this file has no positive floor: a caller that banks a
## gesture SHOULD bank nothing, and the honest way to express "this act was worth
## nothing" is to pass `0.0`. What the function refuses is an id outside the
## authored vocabulary — a bank that can open an arbitrary key is a bank that can
## create a stat nothing reads, which is the dead-content defect this repo has
## shipped four times (BL-0104/0114/0154/0163).
static func earn(state: MindMasteryState, def: MindStatusDef, uses: float = 1.0) -> Dictionary:
	var refused := {"ok": false, "reason": &"", "track": &"", "key": &"", "uses": 0.0}
	if state == null:
		refused["reason"] = &"no_state"
		return refused
	var track := track_for(def)
	if track == &"":
		refused["reason"] = &"untracked_role"
		return refused
	var key := key_for(def)
	if not knows(key):
		refused["reason"] = &"unknown_vocabulary"
		return refused
	var earned := _finite(uses)
	if earned <= MIN_EARN:
		refused["reason"] = &"no_contribution"
		return refused
	state.bank(track, key, earned)
	return {
		"ok": true,
		"reason": &"",
		"track": String(track),
		"key": String(key),
		"uses": earned,
		"threshold": state.uses_to_next(track, key),
		"step": THRESHOLD_STEP,
	}


## The `steepness` a `status`-track mastery has earned, for `key`. A def authors
## its own `steepness`; this is the MASTERY BONUS on top of it, and it is additive
## rather than multiplicative so a mastery-maxed defender-of-the-contest never
## erases an author's intent.
##
## It cannot exceed the bounded headroom ceiling of `1.0`, which is the reason
## this can never make an apply rate certain: `steepness` of `1.0` still resolves
## `clampf(0.5 + edge, 0, 1)` over an `edge` that is itself a ratio.
static func status_bonus(state: MindMasteryState, key: StringName) -> float:
	return clampf(_level_of(state, TRACK_STATUS, key), 0.0, 1.0)


## The `harm` multiplier an `expression`-track mastery has earned, for `key`.
## Multiplicative here rather than additive, and the asymmetry is deliberate: a
## composure drain that compounded additively would eventually exceed the pool it
## spends and the projection's cost would stop responding to it, so the bonus is a
## multiplier on a share and its ceiling is `1.0` on the multiplier's step rather
## than an unbounded additive.
static func expression_bonus(state: MindMasteryState, key: StringName) -> float:
	return 1.0 + clampf(_level_of(state, TRACK_EXPRESSION, key), 0.0, 1.0)


## The mastery NORMALISED to `[0, 1]` for one entry, which is what the ladder
## divides through. Reading a level is always through this so the two tracks
## cannot be compared on different scales.
static func _level_of(state: MindMasteryState, track: StringName, key: StringName) -> float:
	if state == null:
		return 0.0
	return clampf(state.level(track, key), 0.0, 1.0)


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0
