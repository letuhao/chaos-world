class_name MindMasteryProvider
extends StatProvider

## Publishes the eight stat ids the mind mastery tracks are fought with.
##
## ## WHAT THIS PUBLISHES, and why the ids carry the mind vocabulary in their name
##
## Eight ids, one per authored channel and shape, each with an OFFENCE half and a
## DEFENCE half:
##
## ```
## mind_status_mastery_<suffix>    how well this mind IMPOSES / PROJECTS <suffix>
## mind_composure_<suffix>          how well this mind REFUSES / HOLDS <suffix>
## ```
##
## The ids are the AUTHORED VOCABULARY and nothing is generic, because that is what
## makes the four CC shapes and the two expression channels different INVESTMENTS
## rather than one `mind_cc_power` stat that every mind technique feeds. A single
## shared id would have made the CC group one dial the design explicitly refuses.
##
## ## Which attribute each half reads, and WHY they differ
##
## This is the mechanism that stops the two tracks being reskins, so it is spelled
## out rather than left in a coefficient:
##
## - A **control** shape is imposed against conviction, so
##   `mind_composure_<shape>` reads `will`. All four.
## - `voice` argues and is answered by conviction, so `mind_composure_voice` reads
##   `will` too.
## - `intent` errs the target mid-act and is answered by CLARITY UNDER MOTION, so
##   `mind_composure_intent` reads `mental_clarity`.
##
## So `will` answers FIVE of the eight and `mental_clarity` answers one. That is not
## an accident to be evened out; it is the design's only non-symmetry, and it is
## what a test asserts: a build that invests in `will` is strong against every CC
## shape and against `voice`, and specifically weak against `intent`, so moving its
## points moves its matchup profile. A track where every counter answered the same
## attribute would be one axis with six names.
##
## ## Every id is a RATE, and that is what makes them legible
##
## All eight are `minf(CAP, attribute * step)` with the cap under `1.0`, so they
## are fractions a contest reads directly and they are registered in
## `Stat.RATE_STATS` — a `FLAT` on one means `+1000%`, and `StatusDef`'s own gate
## refuses it. The baseline is `0.0` on an actor with no mind faculty at all, and
## that is the honest degenerate case: an actor with no `will` has no composure, and
## a contest against a defender with no composure is a contest they lose — which is
## why the contest's FLOOR is what stops that being a lock, not a baseline that
## refuses to be zero.
##
## ## The OFFENCE halves all read `mental_clarity`, deliberately
##
## Imposing and projecting are acts of MIND and there is one mind attribute for
## how sharply they are done. Reading `mental_clarity` on all four offence ids is
## what makes a perception-based build NOT automatically the best CC caller — the
## same reason ADR 0183 gave `perception` a core fallback rather than folding the
## two attributes into one, preserved a second time in a second direction.
##
## ## `_or_core_fall`, exactly as `MindProvider` does it
##
## Mind's two base attributes read `0.0` on a stock actor (ADR 0183), so every id
## here carries the same `own if > 0 else core` fallback. Without it these eight
## ids would be dead on every actor the game can build — the identical defect class
## that made `MENTAL_ATTACK` read `0.0` before ADR 0183, one module over.

## The ceiling every OFFENCE id saturates at, and it is under `1.0` on purpose: a
## contest reads these ids as a RATE, and a rate that reached `1.0` would mean a
## perfectly-invested attacker always wins — which is the hard counter the yin-yang
## rule forbids. The ceiling is what stops that while still letting a specialist be
## the best answer in the game to a shape nobody else invested in.
const ATTACK_CAP := 0.45

## What one point of the attribute is worth on an offence id. Sized so the cap is
## reachable at an authored `mental_clarity` rather than being decorative: the
## largest authored value in `game/data` is well past `ATTACK_CAP / ATTACK_STEP`, so
## a specialist can actually saturate it and the contest is a real contest at both
## ends.
const ATTACK_STEP := 0.004

## The ceiling every DEFENCE id saturates at. LOWER than [constant ATTACK_CAP] on
## purpose and this is the single most load-bearing number in the file.
##
## A contest reads `edge = (o - d) / (o + d)`. A defender who saturates their
## composure against an attacker who does NOT saturate theirs is favoured; a
## defender who saturates theirs against an attacker who does is at parity at best.
## Since `MindContest` refuses to take an answer rate below `floor_resist` whatever
## the gap, the ceiling being lower than the offence ceiling is a *tilt*, not a
## wall — which is what makes a mind duel a contest a non-investor can still win a
## real share of the time rather than a coin flip.
##
## ## The ceiling is NOT the defect in `test_investing_in_the_defence`, and the
## ## measurement that says so is worth keeping
##
## This cap is reached at `DEFENCE_CAP / DEFENCE_STEP` = `133.33` points of
## `will`. A sweep of actor investment MEASURED `mind_composure_<suffix>` at
## `0.015 / 0.045 / 0.120 / 0.270` for attributes `5 / 15 / 40 / 90` — all four
## strictly below the ceiling, so nothing in that sweep saturated and the cap was
## never the reason the sweep read flat. The reason is the CONTEST, not the
## provider: `p_answer` was `floor + headroom * p_land`, and `p_land` RISES with the
## attacker's edge, so the "answer rate" rose when the attacker got stronger and
## ignored the defence entirely.
##
## The numbers are recorded here so the next reader does not blame this cap for a
## contest defect. The cap itself is measured to be reachable at roughly three
## hundred points of investment, above anything a shipped ladder actor carries
## (`test_mind_mastery_streams.gd` builds its fixtures at `will 30.0` /
## `mental_clarity 25.0`), so it is a genuine ceiling rather than a wall in the
## reachable range.
const DEFENCE_CAP := 0.4

## What one point of the attribute is worth on a defence id.
const DEFENCE_STEP := 0.003


func contribute(context: StatContext) -> Dictionary:
	var clarity := _or_core_fall(context, MindStats.MENTAL_CLARITY, Stat.WILL)
	var will := context.value(Stat.WILL)
	var out: Dictionary = {}
	# The four CONTROL shapes. Imposed against conviction.
	for shape in MindVocabulary.SHAPES:
		_publish(out, shape, clarity, will)
	# `voice` argues and is answered by conviction: the same pairing as a shape.
	_publish(out, MindVocabulary.CHANNEL_VOICE, clarity, will)
	# `intent` errs the target mid-act and is answered by CLARITY UNDER MOTION. The
	# ONE defence in the game that does not read `will`, and therefore the one axis a
	# `will` build genuinely has to think about.
	out[MindVocabulary.offence_id(MindVocabulary.CHANNEL_INTENT)] = minf(
		ATTACK_CAP, clarity * ATTACK_STEP
	)
	out[MindVocabulary.defence_id(MindVocabulary.CHANNEL_INTENT)] = minf(
		DEFENCE_CAP, clarity * DEFENCE_STEP
	)
	return out


## One offence/defence pair off the two attributes, with the caps applied. Factored
## because five of the eight entries are literally this call and a hand-written
## eighth would have been the place a cap drifted.
func _publish(
	out: Dictionary, suffix: StringName, offence_attribute: float, defence_attribute: float
) -> void:
	out[MindVocabulary.offence_id(suffix)] = minf(ATTACK_CAP, offence_attribute * ATTACK_STEP)
	out[MindVocabulary.defence_id(suffix)] = minf(DEFENCE_CAP, defence_attribute * DEFENCE_STEP)


## `own` when the body carries it, else `core` — `MindProvider._or_core_fall`'s
## shape, spelled again here rather than reaching into that file's private method,
## because a provider calling another provider's private helper is a coupling
## `tools arch` cannot see and a future refactor would break silently.
func _or_core_fall(context: StatContext, own: StringName, core: StringName) -> float:
	var authored := context.value(own)
	return authored if authored > 0.0 else maxf(0.0, context.value(core))
