class_name NpcReadModel
extends RefCounted

## The `summary()` and `presence_here()` read models (ADR 0092). Split out of the facade
## so the facade stays the verbs a consumer calls and this stays the projection a panel
## renders — the same split `techniques` already makes with `TechniqueReadModel`.
##
## **Every value here is a primitive.** A panel tests this dictionary; nothing in it names
## an `NpcDef`, an `NpcRosterEntry` or an `Actor`.

## Bounded read size for `presence_here`. A busy settlement reports `truncated` rather
## than silently dropping an npc the player can see.
const MAX_PRESENCE_READ := 16


## The read model for one npc: tier, stage, presence and identity as primitives.
##
## Accepts either a stable `npc_id` or a live instance key (`drifter#3`), so
## `presence_here` can pass registry keys straight through without a second lookup.
##
## ## `live_location_id` is the place the LIVE body was minted for, not the place the
## ## roster last remembers it at (BL-0715)
##
## These are two different facts and the row has to answer the one it was asked. A live
## actor's place comes from `NpcRegistry`, because an untracked npc has no roster entry
## to remember it in at all; the roster entry's `location_id` is "where you LAST met
## them", which for someone standing in front of you may be a settlement you left an hour
## ago. A presence read filters on the live place, so reading the remembered one is what
## made a freshly stocked room filter itself to nothing. Empty when the caller has no
## live place to offer — a summary asked for somebody who is not here — which is the one
## case where the remembered value is the only value there is.
static func summary(
	key: StringName,
	entry: NpcRosterEntry,
	def: NpcDef,
	is_live: bool,
	live_presence: StringName,
	live_location_id: StringName = &""
) -> Dictionary:
	if entry == null:
		return {
			"npc_id": String(key),
			"instance": String(key),
			## ## `known` is NOT `not composed` (the lazy-identity bug this key carried)
			##
			## This branch — the one with no roster entry — used to publish the same `known` the
			## ENTRY branch below computes, and a def with no entry has no entry state at all.
			## Answering it from the TIER made a `transient` read `known: true`: `known` is
			## `NpcTier.is_tracked(tier)` in the entry branch, `transient` is untracked, so an
			## entry-less row that borrowed the tier answer contradicted the row that had one.
			##
			## `known` means **the player has a roster row for this individual**, and this is the
			## branch where there provably is not one, so it is `false` — never a re-derivation.
			## Whether an UNTRACKED tier composes a persona is a different fact and is published
			## under its own name: `composed`.
			"known": false,
			"composed": NpcTier.COMPOSED.has(def.normalized_tier()) if def != null else false,
			"tracked": def.tracked() if def != null else false,
			"tier": NpcTier.label(def.normalized_tier()) if def != null else "",
			"presence": NpcPresence.label(NpcPresence.PRESENT if is_live else NpcPresence.UNKNOWN),
			"display_name": def.display_name if def != null else "",
			"faction": String(def.faction) if def != null else "",
			"stage_id": "",
			"stage_label": "",
			"stage_index": 0,
			"stage_count": def.stage_count() if def != null else 0,
			"location_id": String(live_location_id),
		}
	var stage_def := def.stage(entry.stage_id) if def != null else null
	return {
		"npc_id": String(entry.npc_id),
		"instance": String(key),
		"known": true,
		## ## A roster row is AUTHORED content by definition, so this one is a CONSTANT
		##
		## Published under the same name as the entry-less row's, and deliberately not derived:
		## an individual with a roster entry has a `.tres` behind them, so `composed` can only
		## ever be `false` here. Deriving it from the tier would make the two branches of this
		## function disagree about the same key for the same person.
		"composed": false,
		"tracked": entry.tracked(),
		"tier": NpcTier.label(entry.tier),
		"presence": NpcPresence.label(live_presence),
		"display_name": def.display_name if def != null else "",
		"faction": String(def.faction) if def != null else "",
		"stage_id": String(entry.stage_id),
		"stage_label": stage_def.display_name if stage_def != null else "",
		"stage_index": entry.stage_index(),
		"stage_count": def.stage_count() if def != null else 0,
		"location_id": String(live_location_id if is_live else entry.location_id),
	}


## Who is here right now, tracked and untracked in one read. `summaries` is the already
## built list, so this owns only the envelope, the location filter and the truncation flag.
##
## **A non-empty `location_id` FILTERS.** It used to be echoed straight into the result, so
## the read model labelled its answer with a place it had never checked — a caller asking
## "who is in `spirit_peaks`" was handed everyone, captioned as spirit_peaks. An empty id
## means "everywhere", which is what a boot-time settlement wants.
##
## ## The filter is now real, and that is why the write has to carry a place (BL-0715)
##
## It was already a real filter before that fix — it just had nothing to match. Every
## row was built with `location_id: ""`, so a room load that stocked four bodies and then
## asked "who is in `mortal_plains`" was handed nobody, and nothing in the read path
## could say so: `count` was a true answer to a question about the wrong table. A filter
## this sharp is only safe because the WRITE records where it put each body; the two
## halves are one invariant and this function is where it is paid.
static func presence(
	location_id: StringName, _keys: Array[StringName], summaries: Array
) -> Dictionary:
	var kept: Array = []
	for index in range(summaries.size()):
		if summaries[index].get("location_id", String(location_id)) != String(location_id):
			continue
		kept.append(summaries[index])
	var total := kept.size()
	if total > MAX_PRESENCE_READ:
		total = MAX_PRESENCE_READ
		kept = kept.slice(0, MAX_PRESENCE_READ)
	return {
		"location_id": String(location_id),
		"count": kept.size(),
		"truncated": kept.size() < summaries.size(),
		"npcs": kept,
	}


## ## `alive` — the whole alive layer as ONE primitive row (ADR 0253)
##
## Four capabilities, four keys, one call, because a panel that had to make four reads to
## draw one npc would be the "unreachable surface" this repo keeps finding. It is a read
## model like every other function in this file: **primitives and arrays of primitives
## only**, no `Resource`, no `Actor`, no `NpcPersona`.
##
## ## ## TIER POLICY IS DECIDED HERE, IN ONE PLACE, AND NEVER BRANCHED ON AGAIN
##
## The four tiers answer four different questions and that is the whole table (ADR 0092
## says a tier answers ONE question — whether an individual is remembered — and this is
## what each remembered-ness costs):
##
## | tier | tracked | round | opinion | memory | tells |
## |---|---|---|---|---|---|
## | `story` | yes | authored | authored | full | authored |
## | `major` | yes | authored | authored | full | authored |
## | `minor` | **no** | composed | composed | none | generic |
## | `transient` | no | none | none | none | generic |
##
## **`tracked` decides which half of the row is composed.** An untracked def therefore has
## **no** `memory`, **no** authored `opinion` and **no** `tells` — and that is not a
## compromise:
##
##   - **No memory.** There is no bond to remember with: ADR 0092 makes a minor leave no
##     roster entry, so there is no row, and a second one here would invert the ADR.
##   - **No opinion.** An opinion is a position held about the world, and a minor who
##     does not persist cannot hold one across visits — it would be the same view they
##     held last time, by construction, which is precisely a persisted opinion.
##   - **No authored round.** A daily round exists to make a TRACKED person be somewhere
##     else when you return. An untracked npc is already somewhere else — they are not
##     the same person — so a schedule for them is inventing a continuity nothing has.
##
## **`transient` gets less than `minor` because it is the one tier whose whole promise is
## population.** It composes no persona at all and takes the generic body, which is the
## cheapest honest answer there is.
##
## The tier is read through the two NAMED SETS below — `NpcTier.TRACKED` and
## `NpcTier.COMPOSED` — and never through an `if tier == "major"` anywhere in this module
## (ADR 0092 line 18).
##
## ## ## `composed` is WHAT WAS BUILT, not WHAT THE TIER QUALIFIES FOR
##
## It is assigned from `NpcTier.COMPOSED.has(tier)`, which is the AUTHOR'S question —
## "for which tiers is a composition the right answer" — and it is the key the roster panel
## asserts `false` on for a `transient`. The transient branch below then REFUSES the
## composition and returns, so the row used to ship `composed: true` beside a generic body
## and no opinion: a row claiming work it had not done, which is the shape of the bug this
## key has to avoid.
##
## The shipped value is therefore **the work, after the branch** — a `transient` is
## `composed: false` because it composed nothing, and a `minor` is `true` because it did.
## Assignment is unconditional at the top and re-stated after the refusal, which keeps the
## key from depending on a caller's tier vocabulary: an UNKNOWN tier normalizes to `minor`,
## and a `minor` really is composed.
static func alive(
	def: NpcDef,
	player: Actor,
	npc_id: StringName,
	period: int,
	location_id: StringName,
	ordinal: int = 0
) -> Dictionary:
	var tier := def.normalized_tier() if def != null else NpcTier.MINOR
	# The two NAMED SETS, read separately, because they answer different questions and
	# conflating them is what produced both of this file's row bugs:
	#   `untracked` — does this individual persist? Decides WHICH HALF of the row is built.
	#   `composes`  — is a composition the right ANSWER for its tier? Decides the `composed`
	#                key, and is `false` for a `transient`, which composes nothing.
	var untracked := not NpcTier.is_tracked(tier)
	var composes := NpcTier.COMPOSED.has(tier)
	var out := {
		"npc_id": String(npc_id),
		"tier": String(tier),
		"tracked": not untracked,
		# Provisional, and CORRECTED at the branch below: the shipped value is the work.
		"composed": composes,
		"period": period,
		"round": {},
		"opinion": {},
		"memory": {"count": 0, "dropped": 0, "carried": 0, "rows": []},
		"tells": {},
		"power_scale": 0.0,
	}
	# ## THE SOCIAL GATE — the one axis `regard` was missing from behaviour (ADR 0264)
	#
	# Published for EVERY tier, including the composed ones, and the reason is the default:
	# an ungated def reads `gate_open: true, warmth: 0`, which is byte-identical to the row as
	# it shipped. A composed minor that authored no gate therefore costs zero evaluations.
	out["gate_open"] = true
	out["gate_reason"] = ""
	out["warmth"] = NpcGates.WARMTH_NEUTRAL
	if untracked:
		# ## COMPOSED ON INTERACTION — the untracked tiers, and the tier IS the ask
		#
		# `transient` is refused rather than composed, which is the one place this module
		# reads a tier beyond the tracked question, and it does so through the CONTENT:
		# `NpcTier` holds the named set, and a tier that composes is a list rather than a
		# comparison. A transient npc is population — it is minted, it is legibly a body,
		# and there is no plan to save the reader a `tier == transient` branch here.
		if not composes:
			out["composed"] = false
			out["tells"] = _generic_tell()
			return out
		var persona := NpcMinorComposer.compose(location_id, tier, ordinal, def)
		out["opinion"] = {
			"subject_id": String(persona.opinion_subject),
			"stance": String(persona.opinion_stance),
			"prose": persona.opinion_prose,
		}
		out["tells"] = {
			"verb": String(persona.tell_verb),
			"body": persona.tell_body,
			"consequence": String(persona.tell_consequence),
		}
		out["power_scale"] = persona.power_scale
		# The name and the manner travel on the row too: a composed persona IS its name,
		# and a panel that had to ask a second question for it would compose twice.
		out["display_name"] = persona.display_name
		out["manner"] = persona.manner
		out["activity"] = persona.activity
		return out

	# ## TRACKED — authored round, authored opinion, full memory, authored body
	#
	# `round` is passed `period` and ADVANCES on this call. **The read is the trigger**
	# (ADR 0173(c)): there is no tick and no `if someone_is_here`.
	out["round"] = NpcAliveness.round(def, npc_id, period)
	var bond := NpcAliveness.memory(player, def, npc_id)
	out["memory"] = bond
	var authored := NpcAliveness.opinions(def)
	out["opinion"] = _one_opinion(authored)
	out["tells"] = NpcAliveness.tell(
		player,
		def,
		_bond_class(player, npc_id),
		StringName(String((out["round"] as Dictionary).get("slot_id", ""))),
		int(bond.get("carried", 0)) > 0
	)
	out["display_name"] = def.display_name if def != null else ""
	out["power_scale"] = def.minor_power_scale if def != null else 0.0
	# ## The gate is read LAST, and it does not replace the authored body
	#
	# `NpcGates.evaluate` answers on the def's own `social_gate` and returns the SHIPPED shape
	# unchanged when the def authors none. **The authored `tells` above are left alone either
	# way**: a gate is a fact a panel must be able to SHOW (ADR 0044 — a refused verb writes
	# nothing), and silently swapping an authored body for a gated one would hide the gate
	# from the player entirely, which is the worse of the two failures.
	var gate := NpcGates.evaluate(player, def.social_gate if def != null else {})
	out["gate_open"] = bool(gate.get("gate_open", true))
	out["gate_reason"] = String(gate.get("gate_reason", ""))
	out["warmth"] = int(gate.get("warmth", NpcGates.WARMTH_NEUTRAL))
	return out


## The most opinions `alive` renders on a tracked npc: one is what a panel draws on a row
## and the full set is a screen. Deliberately a cap of ONE, so the row stays a row.
const MAX_ALIVE_OPINIONS := 1

## The `social` facade, preloaded and reached for exactly one verb. `npc` declares
## `social` in `tools/arch/registry.json`, so this is a declared edge, and reading the bond
## class anywhere else would mean keeping a second copy of the ladder.
const SOCIAL_FACADE := preload("res://src/modules/social/api.gd")

## The body a TRANSIENT npc wears. Named constants rather than an empty row: an empty row
## reads as "this npc has nothing to say", and "she does not look up" is a reaction the
## player can act on. `minor` composes one from the place instead.
const GENERIC_TELL_VERB := &"does_not_look_up"
const GENERIC_TELL_BODY := "does not look up from what they are doing"
const GENERIC_TELL_CONSEQUENCE := &"ignores"


static func _one_opinion(authored: Dictionary) -> Dictionary:
	var rows := authored.get("rows", []) as Array
	if rows.is_empty():
		return {}
	return rows[0] as Dictionary


## The derived bond class, read through the `social` facade and never re-derived here
## (ADR 0091: the class is a pure function of the axes and nothing stores it).
static func _bond_class(player: Actor, npc_id: StringName) -> StringName:
	if player == null:
		return StringName(String(SocialBondClass.STRANGER))
	var row := SOCIAL_FACADE.bond_entry(player, npc_id)
	return StringName(String(row.get("bond", SocialBondClass.STRANGER)))


static func _generic_tell() -> Dictionary:
	return {
		"verb": String(GENERIC_TELL_VERB),
		"body": GENERIC_TELL_BODY,
		"consequence": String(GENERIC_TELL_CONSEQUENCE),
	}
