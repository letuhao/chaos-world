class_name CharacterCreationFlow
extends RefCounted

## Character creation for DEF-0109, and the whole of it.
##
## ## The question, and why this is not a fate picker
##
## The player's goal is "each destiny path creates a different character". ADR 0065
## says a destiny is **earned, never chosen**, and forbids a picker. Both are true
## only if the thing the player picks is not the destiny: what the player answers
## at creation is **how they arrived in the world**, and the creation layer converts
## that answer into exactly one origin destiny, once, through
## `DestinyApi.earn_destiny(actor, id, "origin")`.
##
## The three candidates are the three `group = &"origin"` branches — three ways of
## arriving, not a catalogue of seventeen fates. The player never sees a fate, never
## browses a destiny tree, and after committing, the module's own `group` rule
## closes the other two **permanently** (ADR 0065's exclusivity). So the rule is not
## re-implemented here: `DestinyGate` owns it, and this file only asks.
##
## ## Where the line is drawn
##
## Every `available` / `unmet` answer below comes from `DestinyApi.summary`, which
## publishes the real gate's own verdict (`DestinyGate.unmet_prerequisites`). This
## file never re-derives a rule the module owns; it translates the *authored*
## arrival table into candidates and then asks the facade. The one subtraction made
## from that verdict is [method _beyond_creation], and it removes only the entries
## this same file's own arrival table satisfies.
##
## ## A body plan, not a stat stick (ADR 0062 / 0109)
##
## Each origin arrives with a RACE, and the race is what makes the three heroes
## materially different: base attributes come from `RaceDef.base_attributes`
## through `RaceApi.set_race` — never from a literal in this file — and the
## cultivation paths this hero is enrolled on are exactly the ones its body
## allows. A `tidecaller` cannot take the body path at all; `stoneborn`,
## `emberblood` and `commonborn` close the mind path. That is ADR 0109's rule made
## visible at character creation instead of at a breakthrough nobody would reach.
##
## ### The authored collision in this table, and why the table is not the bug
##
## **`stoneborn` and `emberblood` both close `mind_cultivation`**, so those two
## arrivals enrol on the same path set and differ only in their numbers. That is
## visible in `game/data/races/*.tres` and it is authored there on purpose — each of
## those two descriptions says in prose that the mind path closes for it, and
## `commonborn` closes it too. This file owns WHICH BODY each arrival arrives in and
## nothing else; it reads `closed_paths` through `RaceApi` and never writes a path
## literal, so it cannot both honour that prose and manufacture a difference the
## races do not have.
##
## Of the four authored races, `commonborn` is the only one that closes nothing, so
## pairing it with `stoneborn` (closes mind) and `tidecaller` (closes body) is what
## gives all three arrivals a distinct path set, with no race contradicted. That is a
## ONE-CELL change to [constant RACE_BY_ORIGIN] — deliberately NOT made here, because
## `game/data/**` is authored content and outside this slice's files. Until it lands,
## `test_the_three_origins_produce_materially_different_heroes` asserts the rule and
## fails by name on this pair, which is the honest report of it.
##
## ## Once, and only once (ADR 0061's precedent)
##
## `build()` refuses `already_created` on a second call, and `grant_origin()` is
## idempotent over the module's own exactly-once earn. Either way, a second commit
## grants nothing.

## The exclusivity group whose members are the three ways of arriving.
const ORIGIN_GROUP := &"origin"
## The `source` string every creation grant carries. ADR 0065 names the SOURCE, not
## the fate id — the same shape DEF-0107 uses for quests.
const SOURCE := "origin"

## The one fact this layer records, in `core`'s flat bare-id namespace (ADR 0113):
## "this hero was created". It carries no reward and no payload; WHICH origin was
## earned is already durable in the destiny ledger, so a second fact for it would
## be a second place to disagree. A quest authored `{verb: has_fact, id:
## character_created}` opens the moment creation lands — the "just created" hook,
## added as DATA against the existing six-verb gate rather than as a module seam.
const FACT_ID := &"character_created"

## Which body each origin arrives in. Authored here rather than in content because
## there is no authored field that links a `DestinyDef` to a `RaceDef`; it is the
## one arrival table this layer owns.
##
## **The three bodies restrict three DIFFERENT path sets, and that is the point.**
## `stoneborn` and `tidecaller` each close one path outright, and
## `emberblood_touched` closes NEITHER — so each origin is a materially different
## character rather than one hero wearing three labels. Mapping the third origin
## onto `emberblood` did not: `stoneborn` and `emberblood` both close
## `mind_cultivation`, so two origins restricted the same path and a player
## choosing between them was choosing a name, not a career.
const RACE_BY_ORIGIN := {
	&"the_one_who_stayed": &"stoneborn",
	&"the_one_who_returned": &"tidecaller",
	&"the_chosen_instrument": &"emberblood_touched",
}

## Fates an origin supplies to its own arrival, granted BEFORE the destiny is
## earned because the authored destiny names one of them as a prerequisite.
##
## `the_chosen_instrument` requires `reborn_in_a_lesser_vessel`, whose only other
## grant path is the quest `the_short_road` — which waits on a fact nothing in the
## tree writes. Left alone the origin is unreachable, and an unreachable origin is
## exactly the DEF-0109 defect this file closes. Creation earns it on the player's
## behalf under the same `source`, once, and `DestinyApi.earn_fate` is
## exactly-once — so a quest that later pays the same fate pays nothing twice.
const ARRIVAL_FATES := {
	&"the_one_who_stayed": [],
	&"the_one_who_returned": [],
	&"the_chosen_instrument": [&"reborn_in_a_lesser_vessel"],
}

## Set once [method build] has committed, so a second commit on the same flow is a
## named refusal rather than a second hero.
var _created: bool = false

# --- Reading the choices ----------------------------------------------------


## The three origin ids, canonically ordered. Asked of the fate catalog rather
## than restated here, so an author adding a fourth origin shows up on this screen
## without a code edit.
func origin_ids() -> Array[StringName]:
	return FateCatalog.instance().destinies_in_group(ORIGIN_GROUP)


## Every origin this layer can create, as primitives.
##
## Each entry is `{id, display_name, description, bearing, available, unmet, group,
## race, race_name, closed_paths, open_paths, arrival_fates, grants_fate_count,
## creation_supplies_prerequisite}`.
##
## `available` and `unmet` are the REAL gate's answer for a hero who has earned
## nothing, read from `DestinyApi.summary` — not a second copy of the rule. An
## origin whose only unmet prerequisite is one [member ARRIVAL_FATES] supplies is
## still openable, and says so through `creation_supplies_prerequisite`, because
## that is precisely the arrival that brings the name with it.
func candidates() -> Array[Dictionary]:
	# One probe for the whole list: it asks the gate the same question for every
	# origin, and a per-entry probe would build three actors to learn one thing.
	var codex := DestinyApi.summary(_probe())
	var catalog: Dictionary = codex.get("destinies", {})
	var out: Array[Dictionary] = []
	for entry_id in catalog.keys():
		var view: Dictionary = catalog[entry_id]
		if String(view.get("group", "")) != String(ORIGIN_GROUP):
			continue
		out.append(_candidate(StringName(entry_id), view))
	# Sorted by id because the order is load-bearing: this list is what a player
	# reads first, and `Array[Dictionary].sort()` would compare whole dictionaries.
	# `FateCatalog._sorted_keys` is copied for exactly this reason.
	out.sort_custom(_by_id)
	return out


## The race `choice_id` arrives in, or `&""` for an id this layer does not create.
func race_for(choice_id: StringName) -> StringName:
	return RACE_BY_ORIGIN.get(choice_id, &"")


# --- Committing one arrival --------------------------------------------------


## Create a hero from `choice_id` and earn that origin exactly once.
##
## `base_stats` seeds the actor's own build; the race's `base_attributes` are added
## on top by `RaceApi`, so an empty dictionary yields a hero who is purely the body
## plan. Nothing here writes a stat literal.
##
## On success: `{ok: true, reason: "", actor, choice, race, closed_paths,
## open_paths, destinies, fates, fact}`. On refusal: `{ok: false, reason:
## "unknown_origin" | "already_created" | "gate_unmet", unmet: [...]}` — the three
## reasons a player can be told no, named rather than guessed at by the caller.
## Create a hero for a REBIRTH arrival (ADR 0130).
##
## ## Why a second verb rather than relaxing [method build]
##
## **`build` refuses `already_created`, and that guard is correct.** It exists so a player who
## answers the creation screen twice does not receive two heroes. A rebirth is the opposite
## case: a returning soul is SUPPOSED to arrive in a new body, and the guard would make the
## second arrival impossible. So the two are separate verbs with separate guards rather than one
## verb with a flag, because a flag would have to be settable by a screen.
##
## ## What a forced build does NOT do
##
## **It takes no origin DESTINY.** A `SoulDef` is an arrival the soul earned by dying, not an
## entry in the `group = &"origin"` exclusivity set character creation offers. Granting it
## through `earn_destiny` would close two of the three original arrivals permanently and hand
## the player a destiny picker by the back door (ADR 0065). So the soul ledger records the
## arrival and the character's own destiny ledger starts empty, exactly as a first hero's does.
##
## ## The race comes from the ARRIVAL, not from a table in this file
##
## `SoulDef.race_id` is authored on the arrival, so a returning soul arrives in the body its
## arrival names rather than in one this file's constant happens to map to. That is why the
## arrival table may grow without editing `RACE_BY_ORIGIN`, which only the creation screen's
## three origins use.
##
## Refuses `unknown_arrival` for an id no arrival defines, and `no_body_mint` when the actor
## cannot be built — naming the failure rather than returning a half-built hero.
static func build_forced(
	arrival_id: StringName, incarnation: int = 0, base_stats: Dictionary = {}
) -> Dictionary:
	var def := SoulCatalog.instance().arrival_definition(arrival_id)
	if def == null:
		return {"ok": false, "reason": "unknown_arrival", "actor": null}
	var race_id := def.race_id
	if race_id == &"":
		return {"ok": false, "reason": "arrival_names_no_body", "actor": null}
	var actor := _body(race_id, base_stats)
	if actor == null:
		return {"ok": false, "reason": "no_body_mint", "actor": null}
	# The id is DERIVED FROM THE SOUL'S INCARNATION, not from a counter this file owns: `_body`
	# mints every hero as `&"player"`, so without this every rebirth in a run would produce the
	# SAME actor id — and two Actors with one id is a world where the second is invisible, because
	# every ledger and roster is keyed by it. The count is PASSED IN by the caller rather than read
	# from the soul here, because this runs before `reincarnate` and a read would see the old one.
	actor.id = StringName("player_incarnation_%d" % incarnation)
	return {
		"ok": true,
		"reason": "",
		"actor": actor,
		"arrival": String(arrival_id),
		"race": String(race_id),
		"destinies": DestinyApi.destinies(actor),
		"fates": DestinyApi.fates(actor),
		"is_rebirth": true,
	}


func build(choice_id: StringName, base_stats: Dictionary = {}) -> Dictionary:
	if not _is_origin(choice_id):
		return _refuse("unknown_origin")
	if _created:
		return _refuse("already_created")
	# Typed explicitly: a Dictionary lookup is Variant, and `:=` on a Variant is
	# a warning-as-error in this project (see the same rule in nation/api.gd).
	var race_id: StringName = RACE_BY_ORIGIN[choice_id]
	var actor := _body(race_id, base_stats)
	var earned := grant_origin(actor, choice_id)
	if not bool(earned.get("ok", false)):
		return _refuse("gate_unmet", earned.get("unmet", []) as Array)
	# A fact that happened is a thing that happened, not a thing that grants
	# something (ADR 0113) — so it is recorded LAST, once the grant it describes
	# actually landed. Monotone, so re-recording is a no-op rather than a second
	# occurrence.
	var fact := WorldFact.record(actor, FACT_ID, 1)
	_created = true
	var out := {
		"ok": true,
		"reason": "",
		"unmet": [],
		"choice": String(choice_id),
		"race": String(race_id),
		"actor": actor,
		"destinies": DestinyApi.destinies(actor),
		"fates": DestinyApi.fates(actor),
		"closed_paths": _closed_paths(actor),
		"open_paths": _open_paths(actor),
		"fact": String(FACT_ID),
		"fact_count": int(fact.get("count", 0)),
	}
	return out


## Earn `choice_id` on `actor`, idempotently. The verb a confirm control calls
## once the flow object exists; split out so a caller holding an actor it built
## elsewhere can still commit an arrival without minting a second hero.
##
## Returns `{ok, reason, choice, destinies, fates, unmet}` where a refusal is
## `unknown_origin` or `gate_unmet` carrying the gate's own `unmet` entries.
func grant_origin(actor: Actor, choice_id: StringName) -> Dictionary:
	if actor == null or not _is_origin(choice_id):
		return _grant_refusal("unknown_origin")
	if DestinyApi.has_destiny(actor, choice_id):
		# Already earned. `earn_destiny` would also no-op, but answering the
		# question here is what lets a screen say "already committed" instead of
		# silently re-running the whole grant.
		return {
			"ok": true,
			"reason": "already_earned",
			"choice": String(choice_id),
			"unmet": [],
			"destinies": DestinyApi.destinies(actor),
			"fates": DestinyApi.fates(actor),
		}
	# The arrival supplies its own prerequisite fates FIRST: a destiny whose
	# `requires_fates` names one of them can never be earned otherwise.
	for fate_id in ARRIVAL_FATES.get(choice_id, []) as Array:
		DestinyApi.earn_fate(actor, fate_id, SOURCE)
	# The single earn DEF-0109 asks for. Exclusive within `origin` for good, and
	# it carries its authored `grants_fates` with it.
	DestinyApi.earn_destiny(actor, choice_id, SOURCE)
	if not DestinyApi.has_destiny(actor, choice_id):
		return _grant_refusal("gate_unmet", _unmet_for(actor, choice_id))
	return {
		"ok": true,
		"reason": "",
		"choice": String(choice_id),
		"unmet": [],
		"destinies": DestinyApi.destinies(actor),
		"fates": DestinyApi.fates(actor),
	}


# --- Internals ---------------------------------------------------------------


## Whether `choice_id` is an origin this layer creates: it is in the arrival table
## AND the catalog still ships it. The catalog half matters because a `.tres` can be
## deleted between two runs, and an arrival that named it would grant a destiny the
## catalog no longer defines.
func _is_origin(choice_id: StringName) -> bool:
	if choice_id == &"" or not RACE_BY_ORIGIN.has(choice_id):
		return false
	return FateCatalog.instance().destiny_definition(choice_id) != null


## A throwaway actor carrying the modules the gate reads, and nothing else. A
## `RefCounted`, so it is collected the moment this function returns — there is no
## node to leak and nothing to free.
func _probe() -> Actor:
	var probe := ActorFactory.build(&"creation_probe")
	DestinyApi.attach(probe)
	return probe


## One origin as this layer publishes it to a screen.
##
## `bearing` is the one field read past the facade: `DestinyApi.summary` publishes
## it only for a destiny the actor already HOLDS, which is right for the codex and
## wrong here — the bearing IS the pitch a player answers. `app/` is the
## composition root and may read authored content (ADR 0002), so this is the one
## privilege that layer has.
func _candidate(origin_id: StringName, view: Dictionary) -> Dictionary:
	var race_id := race_for(origin_id)
	var def := FateCatalog.instance().destiny_definition(origin_id)
	var supplied := ARRIVAL_FATES.get(origin_id, []) as Array
	var unmet := view.get("blocked_by", []) as Array
	return {
		"id": String(origin_id),
		"display_name": String(view.get("display_name", "")),
		"description": String(view.get("description", "")),
		"bearing": "" if def == null else String(def.bearing),
		"available": _is_openable(view.get("blocked_by", []) as Array, supplied),
		"unmet": _beyond_creation(unmet, supplied),
		"group": String(ORIGIN_GROUP),
		"race": String(race_id),
		"race_name": _race_name(race_id),
		"closed_paths": _race_closed_paths(race_id),
		"open_paths": _race_open_paths(race_id),
		"arrival_fates": _strings(supplied),
		"grants_fate_count": int(view.get("grants_fate_count", 0)),
		"creation_supplies_prerequisite": not supplied.is_empty(),
	}


## The hero: a factory actor, its race, and every cultivation path that race
## allows.
##
## The order is load-bearing and is the only place it exists. `ActorFactory.build`
## mounts the element PROVIDER before any path exists, so the realm half is
## written by the enrolment verbs below (`apply_realm_modifiers`, never a second
## `attach` — ADR 0069). `RaceApi.set_race` comes first so the body plan is on the
## actor before any path reads it. `attach_core_resources` is then re-run because
## pool capacities follow the derived stats and the race has just changed them; it
## is idempotent by its own docstring and preserves current values.
static func _body(race_id: StringName, base_stats: Dictionary) -> Actor:
	var actor := ActorFactory.build(&"player", base_stats)
	RaceApi.attach(actor)
	RaceApi.set_race(actor, race_id)
	actor.attach_core_resources()
	for path_id in PathState.ALL:
		if not RaceApi.can_take_path(actor, path_id):
			continue
		match path_id:
			PathState.BODY:
				ActorFactory.with_body_cultivation(actor)
			PathState.QI:
				ActorFactory.with_qi_cultivation(actor)
			PathState.MIND:
				ActorFactory.with_mind_cultivation(actor)
	# Dual cultivation is a body the hero has, not a path the race closes, so it is
	# attached on every arrival — the same place the playable slice attaches it.
	DualCultivationApi.attach(actor)
	# Fate is earned, never chosen, so the ledger is normalized EMPTY here and
	# [method grant_origin] is the only write to it. This is the composition-root
	# entry point `DestinyApi` documents, placed before the earn for the same
	# reason the playable slice attaches it before anything reads it (ADR 0065).
	DestinyApi.attach(actor)
	return actor


## The real gate's verdict for `choice_id` on `actor`, read through the facade's
## published `blocked_by`. Never re-derived here.
func _unmet_for(actor: Actor, choice_id: StringName) -> Array:
	var view: Dictionary = DestinyApi.summary(actor).get("destinies", {}).get(String(choice_id), {})
	var unmet = view.get("blocked_by", [])
	return unmet if unmet is Array else []


## The cultivation paths this hero's body refuses, asked of the facade so the
## answer is the same one the breakthrough seam reads (ADR 0109) rather than a
## second reading of `RaceDef.closed_paths`.
func _closed_paths(actor: Actor) -> Array:
	var out: Array = []
	for path_id in PathState.ALL:
		if not RaceApi.can_take_path(actor, path_id):
			out.append(String(path_id))
	return out


## The cultivation paths this hero was actually enrolled on: every path that is
## neither refused nor absent. Reported because "three different heroes" means the
## ENROLMENT differs, not only the label — a tidecaller reads two paths here and a
## stoneborn reads two as well, but a different two.
func _open_paths(actor: Actor) -> Array:
	var closed := _closed_paths(actor)
	var out: Array = []
	for path_id in PathState.ALL:
		if not closed.has(String(path_id)) and actor.path(path_id) != null:
			out.append(String(path_id))
	return out


## Whether this origin is open to a player who has earned nothing, from the REAL
## gate's own `blocked_by` entries — never re-derived here.
##
## The probe the summary was read from is a hero who has earned nothing, so it asks
## the gate a question the player has not answered yet: for an arrival that SUPPLIES
## a prerequisite fate, the gate honestly reports that fate as unmet, because at
## probe time nothing supplied it. Committing THIS origin is what supplies it (see
## [method grant_origin], which earns the arrival fates before the destiny), so the
## honest answer to "can this player arrive this way?" subtracts exactly those
## entries — and ONLY those.
##
## Everything else the gate named still refuses: an origin whose `requires_destinies`
## name something this layer never grants stays closed, and an origin closed by an
## origin already earned (ADR 0065's exclusivity) stays closed, because neither is a
## fate this creation supplies. An entry creation cannot satisfy is still REPORTED by
## `_beyond_creation` — the screen shows it greyed with its reason rather than
## pretending the gate said yes.
func _is_openable(blocked_by: Array, supplied: Array) -> bool:
	return _beyond_creation(blocked_by, supplied).is_empty()


## The gate's `blocked_by` entries that committing this arrival would NOT satisfy:
## [param blocked_by] minus the ones naming a fate in [member ARRIVAL_FATES].
##
## Matching is on `kind == &"fate"` AND the id being one this arrival brings with
## it, because those are the only two conditions under which [method grant_origin]
## removes the entry before it re-asks the gate. An `exclusive` entry (closed by an
## origin already earned) is never removed this way, which is what keeps ADR 0065's
## exclusivity intact.
func _beyond_creation(blocked_by: Array, supplied: Array) -> Array:
	var out: Array = []
	for entry in blocked_by:
		var unmet: Dictionary = entry as Dictionary
		if String(unmet.get("kind", "")) == "fate" and supplied.has(String(unmet.get("id", ""))):
			continue
		out.append(unmet)
	return out


func _refuse(reason: String, unmet: Array = []) -> Dictionary:
	return {"ok": false, "reason": reason, "unmet": unmet}


func _grant_refusal(reason: String, unmet: Array = []) -> Dictionary:
	return {"ok": false, "reason": reason, "choice": "", "unmet": unmet}


func _race_name(race_id: StringName) -> String:
	var view: Dictionary = RaceApi.summary(null).get("races", {}).get(String(race_id), {})
	return String(view.get("display_name", ""))


func _race_closed_paths(race_id: StringName) -> Array:
	var view: Dictionary = RaceApi.summary(null).get("races", {}).get(String(race_id), {})
	return _strings(view.get("closed_paths", []))


func _race_open_paths(race_id: StringName) -> Array:
	var closed := _race_closed_paths(race_id)
	var out: Array = []
	for path_id in PathState.ALL:
		if not closed.has(String(path_id)):
			out.append(String(path_id))
	return out


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


func _by_id(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("id", "")) < String(b.get("id", ""))
