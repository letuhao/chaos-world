class_name MindStatusDef
extends Resource

## ONE authored mind status: the CC group, an EXPRESSION-DAMAGE channel, or the
## defender's COMPOSURE — a single content type for the whole mind-control
## vocabulary, exactly as `StatusDef` is one type for the twenty element-riding
## statuses (ADR 0090).
##
## ## Why a SECOND content type rather than a new `StatusDef` kind
##
## A mind status is not an element-riding one. `StatusDef` refuses a def that names
## no element and does not claim `ambient = true`, because every one of the closed
## twenty is inflicted by a landed blow carrying an element. A mind technique
## inflicts its state through a CONFRONTATION — a contest the target may win — and
## names no element at all. So the closed twenty would have to be broken, or the
## gate lied.
##
## And a mind status is not an `StatusEffect` either. It is not "a flag that says
## you cannot act": it is a CONTEST with an authored defence stat, an authored
## floor, an authored headroom, and a published per-beat answer the target spends.
## Every number that makes the contest legible lives on the `.tres` below.
##
## ## The three ids, and why there are exactly three
##
## 1. `control` — the CC group. Its `battlefield` stat is the ATTACKER's stat.
## 2. `expression` — damage the attacker PROJECTS. Its `battlefield` stat is the
##    ATTACKER's stat too, but it damages rather than imposes, and its cost is
##    paid in the defender's composure.
## 3. `composure` — the DEFENDER's counterpart, and the only class whose
##    battlefield stat belongs to the target. This is the yin-yang pairing: an
##    expression channel with no composure behind it is a stat with no answer.
##
## An `expression` and a `composure` def pair by `counterpart_id`, so neither can
## be authored without the other — the refusal is at load, not at review.
##
## ## A mind status is not a HARD disable, and the fields are how that is said
##
## The owner's rule: **no CC may be unavoidable.** Three authored fields make that
## structural rather than a balance promise:
##
## - `beat` is the STEP in which the target gets to answer. A `daze` that can only
##   be answered every second is a disable wearing a duration.
## - `resist_stat` is what the target's side brings to the contest. Nothing is
##   imposed on an actor whose resolver reads `0.0` there.
## - `floor_resist` is the share of the defence the target keeps even at parity.
##   A floor is a distributional claim; a cap is a truncation, and the repo's own
##   reasoning on that is `CombatApply`'s immunity invariant.
##
## ## `headroom` is the field the 329% perma-lock could not have without
##
## `floor_resist` guarantees the answer is never nothing. It does NOT stop the
## degenerate `0.5 sigmoid neutral point`, which hands a target with NO investment
## a 50% answer rate and therefore a coin flip — and a coin flip at a 50% rate
## re-applied every beat is a perma-lock, measured at 329% of baseline kill time.
## `headroom` is the most the contest may take off a defender's floor: at the
## shipped `1.0` an unbeatable attacker is answered at least `floor_resist` of the
## time, at EVERY realm, and a saturating attacker's answer rate converges to
## `floor_resist` rather than to `0.0`. The contest's answer rate is therefore a
## bounded quantity by CONSTRUCTION rather than by a tuned constant.

## The authored content tree. Under `res://src/data/statuses/` because the module
## that inflicts a mind status owns it and `res://data/statuses` is the closed
## twenty — the same two-namespace split `StatusCatalog.AMBIENT_SOURCES_ROOT` made.
const MIND_ROOT := "res://src/data/mind_statuses"

## Which of the three roles a def plays. A closed vocabulary, so a typo is an
## authoring error reported at load rather than a status nobody can find.
const CLASSES: Array[StringName] = MindVocabulary.ROLES
const ROLE_CONTROL := MindVocabulary.ROLE_CONTROL
const ROLE_EXPRESSION := MindVocabulary.ROLE_EXPRESSION
const ROLE_COMPOSURE := MindVocabulary.ROLE_COMPOSURE

## What a `control` does to the target's ACTIONS. A closed vocabulary whose whole
## point is that `lock` is NOT in it: a status that removes the target's ability to
## act is refused at load, which is the owner's rule as an authoring gate.
##
## `slow`       — the target's reactions come later. Nothing is taken away.
## `cost`       — the target's next technique costs more of its own reserve.
## `falsify`    — the target's perception of the world is authored false.
## `invert`     — the target's damage reduction is INVERTED: it takes MORE. The
##                 sharpest of the four, and the only one whose answer is a flat
##                 damage question rather than a rate.
const CONTROL_SHAPES: Array[StringName] = MindVocabulary.SHAPES
const SHAPE_SLOW := MindVocabulary.SHAPE_SLOW
const SHAPE_COST := MindVocabulary.SHAPE_COST
const SHAPE_FALSIFY := MindVocabulary.SHAPE_FALSIFY
const SHAPE_INVERT := MindVocabulary.SHAPE_INVERT

## The projection channels. Two, deliberately, and each is the OTHER one's answer:
##
## - `voice` — the STATEMENT, not the sound. It argues; a defender answers with
##   conviction, so the battlefield on that side is `will`.
## - `intent` — the DIRECTION of the next act. It errs the target mid-attack; a
##   defender answers with composure under motion, so the battlefield there is
##   `mental_clarity`.
##
## One channel would have made the track a reskin of the CC group; four would have
## been four numbers with no matchups. Two is the smallest set where each channel
## has a defender stat that is NOT the other's, and that non-symmetry is the whole
## argument for the track existing (see `MindExpression`).
const EXPRESSION_CHANNELS: Array[StringName] = MindVocabulary.CHANNELS
const CHANNEL_VOICE := MindVocabulary.CHANNEL_VOICE
const CHANNEL_INTENT := MindVocabulary.CHANNEL_INTENT

## The stat ids a battlefield may be read from. The PREFIXES come from
## `MindVocabulary` in `contracts/`, not from a module: `status` declares only
## `contracts` + `core` in `registry.json` and may not name `MindStats`, while
## `mind_cultivation` may not name a `status` def either — so the shared SPELLING
## lives in the dependency-free layer both may reach.
const OFFENCE_PREFIX := MindVocabulary.OFFENCE_PREFIX
const DEFENCE_PREFIX := MindVocabulary.DEFENCE_PREFIX

## The three-variable closed vocabulary. `[CONTROL, EXPRESSION, COMPOSURE]` as
## strings inside a `payload` dictionary inside a `.tres` is how a dictionary value
## would be authored, and a dict-in-dict in a `.tres` is exactly the shape that
## silently truncates on a round trip. Named constants so an author and a test read
## the same three names.
const KEY_CLASS := &"class"
const KEY_SHAPE := &"shape"
const KEY_CHANNEL := &"channel"
const KEY_BATTLEFIELD := &"battlefield"
const KEY_COUNTERPART := &"counterpart_id"
const KEY_BEAT := &"beat"
const KEY_RESIST_STAT := &"resist_stat"
const KEY_RESIST_PREFIX := &"resist_prefix"
const KEY_FLOOR_RESIST := &"floor_resist"
const KEY_HEADROOM := &"headroom"
const KEY_DURATION := &"duration"
const KEY_MAGNITUDE_CAP := &"magnitude_cap"
const KEY_POOL := &"pool"
const KEY_SHARE := &"share_per_pulse"
const KEY_STAT := &"stat"
const KEY_OP := &"op"
const KEY_VALUE := &"value"
const KEY_MODIFIERS := &"modifiers"
const KEY_TEXT := &"text"
const KEY_HARM := &"harm"
const KEY_RECOVERY := &"recovery"
const KEY_STEEPNESS := &"steepness"

## How a `control` spends its potency. `slow` and `falsify` are a FLAT negative
## on a magnitude; `cost` is a FLAT on a rate; `invert` is a FLAT on a zero-baseline
## rate. Each shape's `modifiers` list is authored per unit of magnitude, so ONE
## number states the whole curve and `magnitude_cap` bounds it — the same contract
## `StatusDef.payload.modifiers` has.
##
## `duration` is `refresh` in every case, because REFRESH keeps the stronger of the
## two magnitudes (`core/status_registry.gd`), so a weaker re-application can never
## weaken a debuff and a stronger one can never be argued down.
const STACKING_REFRESH := &"refresh"

@export var id: StringName = &""
@export var display_name: String = ""
## The player's own line, authored copy rather than a sentence composed in code.
@export var description: String = ""
## `CONTROL`, `EXPRESSION` or `COMPOSURE`. The one field that decides which stat is
## read off which side, so it is authored rather than derived from the directory the
## def was found in.
@export var role: StringName = &"control"
## The authored contest: every number below is read out of this one dictionary, keyed
## by the `KEY_*` names above. It is named `payload` because the authored `.tres` files
## spell it that way and because the sibling `StatusDef` exposes the same field name
## for the same role in the same content type.
@export var payload: Dictionary = {}

# --- the contest ---------------------------------------------------------------------


## The stat id the ATTACKER brings to this contest. Prefixed from [constant OFFENCE_PREFIX].
func offence_stat() -> StringName:
	return StringName(String(payload.get(KEY_BATTLEFIELD, "")))


## The stat id the DEFENDER brings — the named counterpart of the track.
func defence_stat() -> StringName:
	return StringName(
		(
			String(payload.get(KEY_RESIST_STAT, ""))
			+ String(payload.get(KEY_RESIST_PREFIX, DEFENCE_PREFIX))
		)
	)


## The share of the defence the target KEEPS at parity and above. A floor, never
## a cap: a status whose floor is `0.0` is an unanswerable disable, which
## `problems()` refuses.
func floor_resist() -> float:
	return _share(payload.get(KEY_FLOOR_RESIST, 0.0))


## The most the contest may take OFF that floor. The bounded quantity that makes
## the apply rate legible without a tuned constant.
func headroom() -> float:
	return _share(payload.get(KEY_HEADROOM, 0.0))


## How decisive this contest is, as the slope of the apply rate over the
## scale-free edge. Clamped to `[0, 1]` because above `1.0` the coin flip is
## overcorrected into a step function — which is the SAME defect wearing a
## different shape: an edge of `0.01` would then land with certainty against a
## target who invested `0.0` and never invested against `0.02`.
##
## This is a DIAL on the authored def rather than a constant in `MindContest`,
## because it is the one number a balance pass wants to move per status and it
## does nothing about the coin flip by itself: any slope leaves parity at
## `NEUTRAL`.
func steepness() -> float:
	return _share(payload.get(KEY_STEEPNESS, 0.0))


## Seconds between the target's opportunities to answer. The step, not the effect.
func beat() -> float:
	return maxf(0.0, _float_of(payload.get(KEY_BEAT, 0.0)))


func duration() -> float:
	return maxf(0.0, _float_of(payload.get(KEY_DURATION, 0.0)))


func magnitude_cap() -> float:
	return maxf(0.0, _float_of(payload.get(KEY_MAGNITUDE_CAP, 0.0)))


## The pool a `control` or `composure` spends against. `health`, `qi` or `stamina`.
func pool() -> StringName:
	return StringName(payload.get(KEY_POOL, &""))


## The share of `magnitude` one pulse costs the pool. Zero for a def that spends
## nothing, which is a legal authoring: a pure modifier has no pulse.
func share_per_pulse() -> float:
	return maxf(0.0, _float_of(payload.get(KEY_SHARE, 0.0)))


## What ONE projection of this channel costs the target's composure, as a
## multiplier on the projection stat. `0.0` for a `control`, and the number the
## expression track is balanced on: it is in DATA because `MindExpression` is a
## module that may not own a balance constant, and because the two channels must
## be priced independently — one is a share of `will`, the other of
## `mental_clarity`, and a single coefficient would have forced one to be read
## against the wrong attribute.
func harm() -> float:
	return maxf(0.0, _float_of(payload.get(KEY_HARM, 0.0)))


## The share of what a projection took that the DEFENDER gets back on its next
## beat. This is the composure track's whole answer to a projection, and it is a
## QUANTITY rather than a chance — which is the mechanical difference from the CC
## group and the reason the two tracks are not reskins of one another.
##
## Above `1.0` the target recovers more than it lost each beat, so a projection
## that is not kept up cannot drain at all; below `0.0` there is no answer. The
## def gate refuses both, and the same gate refuses `0.0` so an expression is never
## an unanswerable drain by default.
func recovery_per_beat() -> float:
	return _share(payload.get(KEY_RECOVERY, 0.0))


## The `StatModifier` list this def contributes, PER UNIT OF MAGNITUDE.
func modifiers() -> Array:
	var out: Array = []
	for entry in payload.get(KEY_MODIFIERS, []):
		if entry is Dictionary:
			out.append(entry)
	return out


## The one-word channel this def projects, for an `expression` or a `composure`.
func channel() -> StringName:
	return StringName(payload.get(KEY_CHANNEL, &""))


## What a `control` does to the target's actions, or `&""`.
func shape() -> StringName:
	return StringName(payload.get(KEY_SHAPE, &""))


## The paired def's id. An `expression` owes a `composure`; a `composure` owes an
## `expression`. Both halves of a pair ship or neither does.
func counterpart_id() -> StringName:
	return StringName(payload.get(KEY_COUNTERPART, &""))


## The authored text, or `""`.
func text() -> String:
	return String(payload.get(KEY_TEXT, ""))


## Primitives only, so a screen and a test read one shape (AGENTS.md's testable
## contract) and neither ever touches the `Resource`.
func to_dict() -> Dictionary:
	var mods: Array = []
	for entry in modifiers():
		(
			mods
			. append(
				{
					"stat": String(entry.get(KEY_STAT, "")),
					"op": String(entry.get(KEY_OP, "")),
					"value": float(entry.get(KEY_VALUE, 0.0)),
				}
			)
		)
	return {
		"id": String(id),
		"display_name": display_name,
		"role": String(role),
		"shape": String(shape()),
		"channel": String(channel()),
		"text": text(),
		"duration": duration(),
		"beat": beat(),
		"magnitude_cap": magnitude_cap(),
		"share_per_pulse": share_per_pulse(),
		"pool": String(pool()),
		"floor_resist": floor_resist(),
		"headroom": headroom(),
		"offence_stat": String(offence_stat()),
		"defence_stat": String(defence_stat()),
		"counterpart_id": String(counterpart_id()),
		"modifiers": mods,
	}


# --- the gate -----------------------------------------------------------------------


## Every defect that must stop this def from reaching play. Empty means authored
## correctly. Called by the catalogue's loader, so a bad `.tres` is REFUSED at load
## and reported — never clamped at runtime and never silently inert.
##
## ## The four refusals that are the owner's rules, as authoring gates
##
## 1. **`floor_resist == 0.0`** — an unanswerable disable. This is the one that
##    matters: a mind cultivator who can impose something the target cannot refuse
##    is a defect, and the cheapest place to catch it is where the number is typed.
## 2. **a `control` naming a shape outside [constant CONTROL_SHAPES]** — the
##    vocabulary has no `lock` in it, so `lock` is an authoring error, not a
##    balance problem.
## 3. **an `expression` with no `composure` counterpart** and the reverse — the
##    yin-yang pairing, enforced at load rather than at review.
## 4. **`beat == 0.0`** — a status the target can never answer is the coin-flip
##    lock wearing a duration.
func problems() -> Array[String]:
	var out: Array[String] = []
	if id == &"":
		out.append("has no id")
	if display_name.is_empty():
		out.append("carries no display_name, so a screen has nothing to label it with")
	if text().is_empty():
		out.append("carries no player-facing text")
	if not CLASSES.has(role):
		out.append("unknown role '%s'; allowed: %s" % [String(role), _names(CLASSES)])
	if beat() <= 0.0:
		out.append(
			(
				(
					"beats at %.3f, so the target is never given a step to answer in; a status "
					+ "nobody can refuse is a coin-flip lock"
				)
				% beat()
			)
		)
	if magnitude_cap() <= 0.0:
		out.append("has no magnitude_cap, so an unbounded application has nothing to stop at")
	if duration() <= 0.0:
		out.append("expires the moment it lands")
	out.append_array(_role_problems())
	out.append_array(_contest_problems())
	out.append_array(_pairing_problems())
	return out


func _role_problems() -> Array[String]:
	var out: Array[String] = []
	match role:
		ROLE_CONTROL:
			if not CONTROL_SHAPES.has(shape()):
				out.append(
					(
						(
							"a control names unknown shape '%s'; allowed: %s — the vocabulary has "
							+ "no `lock` in it on purpose"
						)
						% [String(shape()), _names(CONTROL_SHAPES)]
					)
				)
			if channel() != &"":
				out.append("a control projects no channel; that is an expression's field")
		ROLE_EXPRESSION, ROLE_COMPOSURE:
			if not EXPRESSION_CHANNELS.has(channel()):
				out.append(
					(
						"names unknown channel '%s'; allowed: %s"
						% [String(channel()), _names(EXPRESSION_CHANNELS)]
					)
				)
			if shape() != &"":
				out.append("names a control shape; only a control imposes one")
	out.append_array(_spend_problems())
	return out


## ## The three ways a def acts, and at least one is required
##
## The rule began as "a def that spends a pool owes a pool and a share; a def that
## spends nothing owes a modifier list" — the `metal_sever` defect
## `StatusDef.problems()` already caught for the twenty: a channel that resolves
## nothing is a `.tres` that does nothing at all. That rule named TWO of the three
## currencies this content type can spend in, and read the missing one as a refusal,
## which is why it refused both shipped expression channels at load.
##
## 1. `share_per_pulse` — a PULSE the target pays out of a named pool.
## 2. `modifiers` — a change to the target's actions; only a `control` imposes one.
## 3. **`harm`** — what one PROJECTION costs the target's composure. This is the
##    expression track's whole verb: `MindExpression.breakdown` spends it against the
##    `mind_composure` pool, so an `expression` authoring `harm > 0.0` does exactly as
##    much as a control authoring a modifier. Demanding a `StatModifier` of it instead
##    would have forced the two channels to carry an invented stat change they have no
##    business making, and would have pushed them onto the CC group's currency — the
##    reskin `test_mind_status_no_lock.gd` refuses.
##
## And the COMPOSURE half carries its own exemption, because it is the DEFENDER's: it
## pays nothing, imposes nothing and projects nothing, and its answer is the
## `recovery_per_beat` share that comes back on the target's own beat. Refusing that
## would refuse the only thing the composure role is FOR.
##
## So all three currencies are accepted and a def naming NONE of them is the inert
## `.tres` this gate exists to catch.
func _spend_problems() -> Array[String]:
	var out: Array[String] = []
	var spends := share_per_pulse() > 0.0
	if spends and pool() == &"":
		out.append("names a share_per_pulse but no pool to spend it against")
	var projects := harm() > 0.0
	var answers_by_recovery := role == ROLE_COMPOSURE and recovery_per_beat() > 0.0
	if not spends and modifiers().is_empty() and not projects and not answers_by_recovery:
		out.append(
			(
				"spends nothing, projects nothing and modifies nothing, so it would be a .tres "
				+ "that does nothing at all"
			)
		)
	for entry in modifiers():
		if StringName(entry.get(KEY_STAT, "")) == &"":
			out.append("authors a modifier with no stat id")
			continue
		var op := StringName(entry.get(KEY_OP, ""))
		if op != &"flat" and op != &"percent":
			out.append(
				"stat '%s' declares unknown op '%s'" % [String(entry.get(KEY_STAT, "")), String(op)]
			)
	return out


func _contest_problems() -> Array[String]:
	var out: Array[String] = []
	if floor_resist() <= 0.0:
		out.append(
			(
				"declares floor_resist 0.0, so it names no defence at all; an unanswerable "
				+ "disable is refused, and a target whose resolver reads 0.0 here cannot "
				+ "even be winnable"
			)
		)
	if headroom() <= 0.0:
		out.append("declares headroom 0.0, so nothing is bounded and the contest saturates")
	if headroom() >= 1.0:
		out.append(
			(
				"declares headroom 1.0, which takes the whole floor away again and returns "
				+ "to an unanswerable disable; headroom is what BOUNDS the contest"
			)
		)
	if offence_stat() == &"":
		out.append("names no battlefield stat, so nothing on the attacking side is read")
	if role != ROLE_COMPOSURE and defence_stat() == &"":
		out.append("names no defence stat, so nothing on the target's side is read")
	return out


## The yin-yang pairing, at load. An `expression` whose `composure` is missing
## ships a projectile that nothing answers, and the refusal is here rather than in
## review because the catalogue loads every def in the tree before anything plays.
func _pairing_problems() -> Array[String]:
	var out: Array[String] = []
	var pair := counterpart_id()
	match role:
		ROLE_EXPRESSION:
			if pair == &"":
				out.append(
					(
						"an expression projects something the target has no defence against; "
						+ "name its composure counterpart"
					)
				)
		ROLE_COMPOSURE:
			if pair == &"":
				out.append("a composure with no expression behind it is a stat with no attacker")
	if pair != &"" and role == ROLE_EXPRESSION and harm() <= 0.0:
		out.append("an expression must author a positive harm, or it projects nothing")
	if pair != &"" and role == ROLE_COMPOSURE and recovery_per_beat() <= 0.0:
		out.append(
			(
				"a composure must author a positive recovery, or the projection it answers "
				+ "is a drain with no answer"
			)
		)
	return out


func _names(values: Array) -> String:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return ", ".join(out)


static func _share(value: Variant) -> float:
	return clampf(_float_of(value), 0.0, 1.0)


static func _float_of(value: Variant) -> float:
	if value is float or value is int:
		var number := float(value)
		return number if is_finite(number) else 0.0
	return 0.0
