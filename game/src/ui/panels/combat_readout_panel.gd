class_name CombatReadoutPanel
extends PanelContainer

## The readout for ONE resolved hit: what the damage spine's stages did to a single
## blow. It exists because the engine computes all of it and, until ADR 0174, nothing
## in `ui/` rendered any of it.
##
## ## What it owns, and what it may not
##
## Every `%d`, every decimal, every verdict word, every effect id turned into English:
## this panel, never the screen (AGENTS.md "No number formatting in a screen", ADR 0030
## and ADR 0038). A screen that printed its own figures would give one number two places
## to change.
##
## It holds **no game rule**. It renders the primitives `CombatOutcome.to_dict()`
## published, verbatim. In particular it does NOT re-derive a threshold, a mitigation
## share or a verdict: `neutral` and `clean` are the ENGINE's booleans, read as booleans,
## because a panel that decided "this was a miss" would be a second opinion about what
## the engine meant.
##
## ## Why the effect ids are spelled HERE and not read from the module
##
## `effects[]` entries carry a `kind` id, and a `ui/` file may not hold a typed
## reference to `BodyWounds` / `MindDamage` / `StatusApply` — that would name a class
## outside `api.gd` and is a facade-rule violation. So the three ids are this panel's own
## `StringName` constants, and an id it does not recognise is rendered RAW rather than
## dropped: a live effect the panel cannot name is a gap a reader can see, which is
## strictly better than a silent omission. This is `LootBossPanel._status_name`'s shape
## (ADR 0106) and it is deliberately lossy — a readout can never change what the engine
## computed.
##
## Contract: `summary()` is the testable surface, primitives only, and publishes the
## rendered strings beside the raw numbers so a headless test asserts the sentence a
## player reads rather than a pixel.

## The engine's own empty-miss convention, stated rather than left blank: a swing that
## never arrived has nothing to decompose, and printing `0` for it would teach the reader
## that a whiff and a gut-punch are the same event.
const MISS_TEXT := "The blow never arrived. Nothing was spent."
## A payload that is not a `to_dict()` result at all — nothing has been struck yet.
const NO_DATA := "No blow has been struck yet."
const NO_EFFECTS := "The blow changed nothing beyond the damage itself."
const NO_WOUNDS := "No meridian carries a wound."

## The three `effects[]` kinds the shipped mechanisms emit. See the module docblock for
## why these are restated rather than imported.
const KIND_WOUND := &"body.wound"
const KIND_EROSION := &"mind.erosion"
const KIND_STATUS := &"status_application"
## `DamageProposal.KIND` is the key every effect carries its own id under. It is a
## contracts-layer constant and this is the one string in the shape the UI must know.
const KEY_KIND := "kind"

## The three mechanism names `CombatBoot` chooses between, restated for the same reason
## the three effect ids are: they are module constants a `ui/` file may not name, and the
## readout's whole claim is that a player can SEE which of the three mechanisms answered
## a blow rather than being told there is a `DamageMechanism`.
##
## These are the CLASS names, spelled as strings, because that is what
## `CombatBoot.mechanism_for_hit` publishes and what `summary()` must hand a test that
## asserts the route. The plain-word half is the panel's own wording and never leaves it.
const MECHANISM_QI := &"QiDamage"
const MECHANISM_BODY := &"BodyDamage"
const MECHANISM_MIND := &"MindDamage"

var _outcome: Dictionary = {}
var _band: Dictionary = {}
var _actor: Dictionary = {}
var _mechanism: StringName = &""
var _wounds: Array = []
var _verdict_label: Label = null
var _stages_label: Label = null
var _effects_label: Label = null
var _wounds_label: Label = null
var _actor_label: Label = null
var _bound: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one resolved hit. `outcome` is `CombatOutcome.to_dict()` VERBATIM, `band` is
## `CombatEngineApi.band(attacker, target)`, `actor` is `CombatEngineApi.summary(actor)`
## and `mechanism` is the name the composition root selected for this hit. All four are
## read for figures only; `{}`/`&""` for any of them leaves that half blank rather than
## fabricating a value.
func show_hit(
	outcome: Dictionary, band: Dictionary = {}, actor: Dictionary = {}, mechanism: StringName = &""
) -> void:
	_bind_nodes()
	_outcome = (outcome if outcome != null else {}).duplicate(true)
	_band = (band if band != null else {}).duplicate(true)
	_actor = (actor if actor != null else {}).duplicate(true)
	_mechanism = mechanism
	_render()


## The wound ledger, as `{severity: {...}, necrotic: {...}}` — `BodyWounds.to_dict()`,
## which is what a save carries. Kept on its own verb rather than folded into
## `show_hit` because a wound ledger is state that OUTLIVES the blow: a player reading
## the injury ledger should not have to strike something to see the injuries they
## already have.
##
## Flattened into one row per channel here, so a test indexes rows rather than walking
## two dictionaries that have to agree with each other.
func show_wounds(wounds: Dictionary) -> void:
	_bind_nodes()
	_wounds = _rows_of(wounds if wounds != null else {})
	_render()


## Everything this panel shows, primitives only, with the rendered sentences beside the
## raw numbers so a test asserts what a player reads.
func summary() -> Dictionary:
	_bind_nodes()
	return {
		"has_hit": not _outcome.is_empty(),
		"missed": not _outcome.is_empty() and not bool(_outcome.get("landed", false)),
		"base": float(_outcome.get("base", 0.0)),
		"proposed": float(_outcome.get("proposed", 0.0)),
		"amount": float(_outcome.get("amount", 0.0)),
		"absorbed": float(_outcome.get("absorbed", 0.0)),
		"overflow": float(_outcome.get("overflow", 0.0)),
		"health_delta": float(_outcome.get("health_delta", 0.0)),
		"reflected": float(_outcome.get("reflected", 0.0)),
		"lifesteal": float(_outcome.get("lifesteal", 0.0)),
		"crit": bool(_outcome.get("crit", false)),
		"parried": bool(_outcome.get("parried", false)),
		"blocked": bool(_outcome.get("blocked", false)),
		"landed": bool(_outcome.get("landed", false)),
		"clean": bool(_outcome.get("clean", false)),
		"neutral": bool(_outcome.get("neutral", false)),
		"chain_dropped": bool(_outcome.get("chain_dropped", false)),
		## `""` when the composition root named none — the screen publishes this as a
		## `String` rather than the raw `StringName` so the whole payload stays
		## primitives JSON can carry verbatim.
		"mechanism": String(_mechanism),
		"has_mechanism": _mechanism != &"",
		"draw": float(_band.get("draw", 0.0)),
		"has_band": not _band.is_empty(),
		"effect_count": _effects().size(),
		"effect_kinds": _effect_kinds(),
		"wound_count": _wounds.size(),
		"wound_rows": _wounds.duplicate(true),
		"verdict_line": verdict_text(),
		"mechanism_line": mechanism_text(),
		"stages_line": stages_text(),
		"effects_line": effects_text(),
		"wounds_line": wounds_text(),
		"actor_line": actor_text(),
	}


## Which of the three mechanisms produced this blow, named in the reader's own words.
##
## It is a separate line rather than one more stage row because it is not a STAGE: it is
## the answer to "who answered this", and it is the one fact `CombatOutcome.to_dict()`
## cannot carry — the outcome decomposes a blow, and every blow looks the same in shape
## whichever mechanism made it. A name this panel does not recognise is shown RAW rather
## than dropped, for the reason the effect kinds are: a fourth mechanism must be able to
## be visible before it can be readable.
func mechanism_text() -> String:
	match _mechanism:
		MECHANISM_QI:
			return "elemental share (qi)"
		MECHANISM_BODY:
			return "flat subtraction at a meridian (body)"
		MECHANISM_MIND:
			return "sea erosion (mind)"
		&"":
			return ""
		_:
			return String(_mechanism).replace("_", " ")


## The one line naming what happened, read off the engine's OWN booleans and never
## re-derived. A parry or a block is a DEFENSIVE RESPONSE (ADR 0068), so the wording
## answers rather than exempts, and `neutral` is stated separately because "it cost me
## nothing" is the fact a player acts on.
func verdict_text() -> String:
	if _outcome.is_empty():
		return NO_DATA
	if not bool(_outcome.get("landed", false)):
		return MISS_TEXT
	var parts: Array[String] = ["hit"]
	var named := mechanism_text()
	if not named.is_empty():
		parts.append("answered by " + named)
	if bool(_outcome.get("crit", false)):
		parts[0] = "critical hit"
	if bool(_outcome.get("parried", false)):
		parts.append("parried")
	if bool(_outcome.get("blocked", false)):
		parts.append("blocked")
	if bool(_outcome.get("chain_dropped", false)):
		# ADR 0068: a DROP is visible truncation, and silence would read as a
		# rounding rather than as a chain that hit its depth limit.
		parts.append("reflect chain dropped")
	if bool(_outcome.get("neutral", false)):
		# The one legal refusal that costs nothing at all (ADR 0067's invariant), and
		# the fact a player most needs: the blow arrived and was answered.
		parts.append("answered without cost")
	return " · ".join(parts)


## The spine's stages as the figures the engine published, in its own order. Every `%d`
## and decimal on the whole readout is this one function's — which is why it is a list
## and not a sentence per stage: a reader comparing two rows compares numbers.
func stages_text() -> String:
	if _outcome.is_empty() or not bool(_outcome.get("landed", false)):
		return ""
	var rows: Array[String] = [
		"S1 base %.2f" % float(_outcome.get("base", 0.0)),
		"S4 proposed %.2f" % float(_outcome.get("proposed", 0.0)),
		"S6 amount %.2f" % float(_outcome.get("amount", 0.0)),
		"S9 absorbed %.2f" % float(_outcome.get("absorbed", 0.0)),
		"S9 overflow %.2f" % float(_outcome.get("overflow", 0.0)),
		"S9 health %.2f" % absf(float(_outcome.get("health_delta", 0.0))),
		"S10 reflected %.2f" % float(_outcome.get("reflected", 0.0)),
		"S11 leech %.2f" % float(_outcome.get("lifesteal", 0.0)),
	]
	# The band row is APPENDED, never concatenated into the typed literal: `[]` is an
	# untyped `Array` and assigning one where `Array[String]` is declared throws AT
	# RUNTIME, which is invisible until a readout actually lands a hit — so a panel
	# whose whole job is to print a landed blow printed `""` on every one of them.
	if not _band.is_empty():
		rows.append("band draw %.3f" % float(_band.get("draw", 0.0)))
	return " · ".join(rows)


## `effects[]`, in the order the proposal carried them. The three kinds are the paths'
## OWN state writes (ADR 0067), applied AFTER health — so a wound row here is a fact
## about the defender's ledger, not a second estimate of the damage.
func effects_text() -> String:
	var rows := _effects()
	if rows.is_empty():
		return NO_EFFECTS
	var parts: Array[String] = []
	for entry in rows:
		var effect := entry as Dictionary
		var kind := StringName(effect.get(KEY_KIND, &""))
		match kind:
			KIND_WOUND:
				parts.append(_wound_line(effect))
			KIND_EROSION:
				parts.append(_erosion_line(effect))
			KIND_STATUS:
				parts.append(_status_line(effect))
			_:
				# An id this panel does not know is SHOWN, never hidden: a fourth
				# mechanism must be able to be visible before it can be readable.
				parts.append(String(kind).replace("_", " ") if kind != &"" else "unnamed effect")
	return " · ".join(parts)


## The wound ledger, one line per channel. A NECROSED channel is called out because
## necrosis is IRREVERSIBLE downward (ADR 0070): it is the one wound a player must never
## think will fade.
func wounds_text() -> String:
	if _wounds.is_empty():
		return NO_WOUNDS
	var parts: Array[String] = []
	for entry in _wounds:
		var row := entry as Dictionary
		var label := String(row.get("meridian", "")).replace("_", " ")
		var tail := " NECROSED" if bool(row.get("necrotic", false)) else ""
		parts.append("%s %.3f%s" % [label, float(row.get("severity", 0.0)), tail])
	return " · ".join(parts)


## The attacker's own numbers, as `CombatEngineApi.summary` published them. This is the
## stat half a player builds against, and it is the same facade read the loot readout
## takes — never a second stat formula here.
func actor_text() -> String:
	if _actor.is_empty():
		return ""
	return (
		(
			"ATK %d spiritual / %d physical · DEF %d spiritual / %d physical"
			% [
				int(_actor.get("attack_spiritual", 0.0)),
				int(_actor.get("attack_physical", 0.0)),
				int(_actor.get("defense_spiritual", 0.0)),
				int(_actor.get("defense_physical", 0.0)),
			]
		)
		+ (
			" · crit %d%% · reduction %d · realm %s x%.3f"
			% [
				int(round(100.0 * float(_actor.get("crit_chance", 0.0)))),
				int(_actor.get("damage_reduction", 0.0)),
				String(_actor.get("realm_id", "")),
				float(_actor.get("realm_rate", 1.0)),
			]
		)
	)


# --- Plumbing ---------------------------------------------------------------


## Resolved lazily, never in `@onready`: the headless suite drives this panel before a
## scene tree exists (ADR 0038). Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _bound:
		return
	_verdict_label = get_node_or_null("%VerdictLabel") as Label
	_stages_label = get_node_or_null("%StagesLabel") as Label
	_effects_label = get_node_or_null("%EffectsLabel") as Label
	_wounds_label = get_node_or_null("%WoundsLabel") as Label
	_actor_label = get_node_or_null("%ActorLabel") as Label
	_bound = _verdict_label != null


func _render() -> void:
	if _verdict_label == null:
		return
	_verdict_label.text = verdict_text()
	_verdict_label.theme_type_variation = _verdict_variation()
	_stages_label.text = stages_text()
	_stages_label.theme_type_variation = &"MetaLabel"
	_effects_label.text = effects_text()
	_effects_label.theme_type_variation = &"EffectLabel"
	_wounds_label.text = wounds_text()
	_wounds_label.theme_type_variation = _wounds_variation()
	_actor_label.text = actor_text()
	_actor_label.theme_type_variation = &"MetaLabel"


## Style by VARIATION only — `theme_override_*` is banned (AGENTS.md). A crit and a
## parry must not read the same, because they are the two answers a player reacts to.
func _verdict_variation() -> StringName:
	if _outcome.is_empty() or not bool(_outcome.get("landed", false)):
		return &"MetaLabel"
	return &"WarnLabel" if bool(_outcome.get("crit", false)) else &"OkLabel"


## A necrotic channel is a permanent loss, so its line is styled as one rather than as
## a number that happens to be large.
func _wounds_variation() -> StringName:
	for entry in _wounds:
		if bool((entry as Dictionary).get("necrotic", false)):
			return &"WarnLabel"
	return &"MetaLabel"


## The `effects[]` array, always an Array even when the payload carried none — a typed
## read of a missing key is what turns a miss into a null dereference.
func _effects() -> Array:
	var raw: Variant = _outcome.get("effects", [])
	return raw if raw is Array else []


func _effect_kinds() -> Array:
	var out: Array = []
	for entry in _effects():
		out.append(String((entry as Dictionary).get(KEY_KIND, "")))
	return out


## `{severity: {...}, necrotic: {...}}` flattened to one row per channel. Both maps are
## read defensively: a hand-edited save can carry a non-dictionary under either key, and
## a readout must degrade to "no wound" rather than fail to load.
func _rows_of(wounds: Dictionary) -> Array:
	var out: Array = []
	var severity: Variant = wounds.get("severity", {})
	if not (severity is Dictionary):
		return out
	var raw_flags: Variant = wounds.get("necrotic", {})
	var flags: Dictionary = raw_flags if raw_flags is Dictionary else {}
	for key in (severity as Dictionary).keys():
		(
			out
			. append(
				{
					"meridian": String(key),
					"severity": float((severity as Dictionary)[key]),
					"necrotic": bool(flags.get(String(key), false)),
				}
			)
		)
	return out


func _wound_line(effect: Dictionary) -> String:
	return (
		"wound %s %.2f"
		% [
			String(effect.get("meridian", "")).replace("_", " "),
			float(effect.get("severity", 0.0)),
		]
	)


## The sea's three writes in one row, because `MindDamage` puts them in ONE effect entry
## and a panel that showed turbulence without the clarity it cost would be lying by
## omission (ADR 0071).
func _erosion_line(effect: Dictionary) -> String:
	return (
		"erosion (%s) turbulence %+.3f clarity %+.3f awareness %+.3f"
		% [
			String(effect.get("strike_kind", "")).replace("_", " "),
			float(effect.get("turbulence", 0.0)),
			float(effect.get("clarity", 0.0)),
			float(effect.get("awareness", 0.0)),
		]
	)


## S12's result, applied or refused BY NAME. A refusal is the balance question a status
## row exists to answer (ADR 0087), so `resisted` and `already_held` are printed rather
## than flattened into "nothing happened".
func _status_line(effect: Dictionary) -> String:
	if not bool(effect.get("applied", false)):
		return "status withheld: %s" % String(effect.get("refused", "")).replace("_", " ")
	return (
		"status %s potency %.2f"
		% [
			String(effect.get("status_id", "")).replace("_", " "),
			float(effect.get("potency", 0.0)),
		]
	)
