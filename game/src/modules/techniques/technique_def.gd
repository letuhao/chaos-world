class_name TechniqueDef
extends Resource

## One authored technique (ADR 0053, ADR 0056). A `Resource` that lives in this
## module and nowhere else: `contracts/` holds interfaces and value objects, and
## a technique is content a designer authors as a `.tres`, not a shared type.
##
## Every field below names a type this repo already has. Three states are three
## owners of truth, and this file is the first of them: an `ItemDef` delivers a
## technique and is consumed, a `CodexEntry` records that it is known forever, and
## a `TechniqueSlots` binding decides whether it is equipped right now. A def is
## none of those, and is never deleted by any of them.

# --- Identity (ADR 0056's field table) -----------------------------------------

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var tags: Array[StringName] = []

## The `ItemDef.id` of the MANUAL that delivers this technique, or `&""`.
##
## ## Why a field and not id equality
##
## The delivery seam once resolved `item.id == technique.id`. That is exact and
## unfalsifiable, and it shipped 1363 manuals against 51 definitions with an
## intersection of ZERO (DEF-0203), so the whole technique program was
## unreachable while every test stayed green: each test registered its own
## matching def. Identity by name required the two vocabularies to collide, and
## nothing reviewed that collision — it is a coincidence 51 rows would have to
## stumble into.
##
## So the technique NAMES its own manual and the seam reads that. The direction
## matters: the def is the thing that has to be reachable, and a technique knows
## exactly one book teaches it. The manual does not name the technique, because
## an item is a *carrier* — the same volume could plausibly teach more than one
## thing later, and `items` must not grow a technique vocabulary to say so.
##
## ## The guard is not weakened by this
##
## A manual no def claims still resolves to nothing, so `study` still refuses
## `unknown_technique`. This field adds a second way to be found; it does not
## add a second way to be guessed. There is deliberately NO name-match, tag-match
## or family rule here, and adding one would be worse than the original defect:
## resolving a manual to an *adjacent* technique teaches the player the wrong
## technique silently, which is what the seam refuses by name.
##
## Empty means "no authored manual delivers this yet", which is a content gap
## the content suite names rather than something the seam works around.
@export var delivered_by: StringName = &""

## Grade sets the realm floor through `required_tier()`; rarity budgets options
## and never power (ADR 0055: a grade is a floor, not a scale).
@export var grade: StringName = ItemGrade.MORTAL
@export var rarity: StringName = ItemRarity.COMMON

## A real `ElementDef` id, or `""` for unelemental. Schools group and search and
## never gate anything.
@export var element: StringName = &""
@export var schools: Array[StringName] = []

## False means passive (ADR 0054): no cost block, and the contribution is a
## namespaced set of `StatModifier`s while equipped.
@export var active: bool = true

# --- Path gate (ADR 0059) -----------------------------------------------------

## `PathState.ALL` id, the `SHARED` marker below, or `"<a>+<b>"` for a DUAL
## technique. `SHARED` takes a universal slot and gates on the best path; a DUAL
## technique requires BOTH of its paths at the floor.
@export var path: StringName = PathState.QI

## Minimum realm ORDINAL, keyed by path id, read off the shared 30-realm ladder.
## Every named path must individually reach its floor — never an either/or.
@export var min_path_realm: Dictionary = {}

# --- Attribute and state gates ------------------------------------------------

## The base/attribute gates, reused unchanged from `ItemRequirement`. They read
## base allocation only, so a technique can never satisfy its own requirement
## with the stats it grants.
@export var requirement: ItemRequirement = null

## `QiRealmSeed`'s pair: the channels to open and the `MeridianState` they must
## reach.
@export var required_meridians: Array[StringName] = []
@export var required_channel_state: StringName = MeridianState.OPEN

## `BodyRealmSeed`'s pair: the huyệt to open and the `AcupointDef.tier` they must
## reach.
@export var required_acupoints: Array[StringName] = []
@export var required_acupoint_tier: StringName = &""

# --- Costs and upkeep ---------------------------------------------------------

@export var qi_cost: float = 0.0
@export var stamina_cost: float = 0.0
## Seconds.
@export var cooldown: float = 0.0

## `ItemRequirement`'s exact pair: resource id -> amount per `upkeep_interval`.
@export var upkeep: Dictionary = {}
@export var upkeep_interval: float = 60.0

# --- Magnitude and mastery (ADR 0055) -----------------------------------------

## The number of rungs this technique may reach. The per-rung multipliers are
## ADR 0055 constants, not data, so a def cannot author its own power curve.
@export var mastery_rungs: int = 5

## The coefficient ADR 0055's ladder multiplies. Grade never multiplies the
## effect: grade is a floor, not a scale.
@export var magnitude: float = 1.0

## The share of `magnitude` this technique's qi damage routes through the attacker's
## `element_power_<e>` rather than through `Stat.ATTACK_SPIRITUAL` (ADR 0069). The rest
## is the RAW share, and that raw share IS the damage floor: resistance and the element
## matchup touch the elemental term alone, so a wrong element is a WEAKER hit and never
## a null one.
##
## `0.0` means "use the module's default", NOT "unelemental" -- an unelemental technique
## is `element == &""`, which yields a share of zero without consulting any default.
## The two are different authoring intents and are read as different things.
##
## Clamped to `[0, 1]` on read by the qi mechanism, so a hand-edited `.tres` cannot
## produce a negative raw share.
@export var element_share: float = 0.0

## The meridian this technique aims at, or `""` for no authored aim (ADR 0070). Additive
## to `element_share` and for the same reason: a def lives in its owning module (ADR
## 0056), so the body path's one authored location is an export here rather than a
## change to a `contracts/` type nobody outside this module may extend.
##
## `&""` means "the mechanism decides" and NOT "the strike is ungated": the body
## mechanism reads an authored `&""` as a `random` aim, which is the deterministic
## highest-multiplier read. A `named` aim names a real `body_target.id` here; a meridian
## this body has never unlocked is not struck at all, because there is no channel there
## to subtract from.
##
## The AIM MODE is `ctx.data[&"aim_mode"]`, not this field: one id is a `named` aim and
## its absence is a `random` one, while `broad` is a per-hit choice the author cannot
## make (an area strike is decided by what the attack is hitting, not by its `.tres`).
@export var aim_meridian: StringName = &""

## Which mind EROSION this technique performs (ADR 0071). Additive to the two above and
## for the same reason: a def lives in its owning module (ADR 0056), so the mind path's
## one authored intent is an export here rather than a change to a `contracts/` type
## nobody outside this module may extend.
##
## ## The three kinds, and why the field is a `StringName` and not an enum
##
## `disrupt` is turbulence alone, `obscure` additionally reads the defender's
## `ILLUSION_RESISTANCE`, and `attend` drains the AWARENESS reserve that coherence is
## computed from. They are not balance tiers: `obscure` is not stronger than `disrupt`,
## it is a DIFFERENT defender that answers it, which is why the mechanism branches on
## them rather than scaling them.
##
## A `StringName` because the authoring surface is a `.tres` an author types into, and
## this module must not acquire a compile-time edge to `combat_engine` to name its enum
## — the same reason `element` is a `StringName` naming an `ElementDef` id rather than
## an `ElementDef`.
##
## There is deliberately no `match` turning this into an ordinal. `MindDamage._kind_of`
## already accepts a NAME or an ordinal and answers `disrupt` for anything it does not
## recognise, so the name travels on `ctx.data` unresolved and that ONE function is the
## only place the vocabulary is read. A second copy of the three-way decision here would
## be a second place for a rebalance to miss, and the two would disagree the day a kind
## was added to one and not the other.
##
## ## `&""` is DISRUPT, and that default is load-bearing
##
## The 46 authored `.tres` under `game/data/techniques/` that are not mind techniques
## have no business carrying a mind intent, and a field that defaulted to anything but
## empty would claim one for all of them. So `&""` — the value every unauthored `.tres`
## already has — means "no authored intent", and the mechanism reads it as `disrupt`.
## Every technique that existed before this field resolves exactly as it did before,
## which is the only honest default available: the alternative is making an omission
## mean something stronger than the plain strike, and a mind hit that quietly stopped
## reading `ILLUSION_RESISTANCE` would be a balance change nobody authored.
@export var mind_kind: StringName = &""

## `ItemDef.fixed_modifiers` verbatim: `[{option_id, value}, ...]`, resolved
## through `OptionCatalog.fixed_effect` (ADR 0054). Capped at two options, which
## is what keeps a codex page a comparison rather than a table of numbers.
@export var passive_options: Array[Dictionary] = []


## Realm tier this technique's grade demands, from `ItemGrade`.
func required_tier() -> int:
	return ItemGrade.required_tier(grade)


## Whether this is a passive, i.e. one that contributes modifiers while equipped
## and has no cost block.
func is_passive() -> bool:
	return not active


## The path ids this technique belongs to. One for a path-exclusive technique, one
## for a SHARED technique, and two for a DUAL one — which is what the gate and
## the slot allocator both read, so neither has to re-parse `path`.
func path_ids() -> Array[StringName]:
	if path == TechniquePolicy.SHARED:
		# Built through the typed array: an array literal is untyped `Array`, and
		# returning one where `Array[StringName]` is declared is a runtime type
		# error, not a compile-time one.
		var shared: Array[StringName] = [TechniquePolicy.SHARED]
		return shared
	if path.find(TechniquePolicy.DUAL_SEPARATOR) >= 0:
		var out: Array[StringName] = []
		for part in path.split(TechniquePolicy.DUAL_SEPARATOR):
			if not part.is_empty():
				out.append(StringName(part))
		return out
	# A path-exclusive technique belongs to the one path it names. The test is
	# membership, and the order matters: returning `[path]` for an UNKNOWN path
	# (rather than for a known one) made every legitimate technique claim no slot
	# at all, which surfaced as `no_free_slot` on a fresh actor with seven slots.
	#
	# Built through a typed local, never the `[path]` literal: an array literal is an
	# untyped `Array`, and returning one where `Array[StringName]` is declared throws
	# AT RUNTIME. That is invisible until a caller assigns the result to a typed
	# local, so it read as "learn is free" rather than as a type error.
	if not PathState.ALL.has(path):
		return []
	var only: Array[StringName] = [path]
	return only


## Whether this technique takes a universal slot rather than a path slot. Only a
## SHARED technique does; a path-exclusive or DUAL technique takes its own paths'
## slots (ADR 0053).
func is_shared() -> bool:
	return path == TechniquePolicy.SHARED


## Every normalized effect a passive contributes, resolved through the master
## catalog exactly once. The two-option cap is enforced here rather than trusted,
## so a hand-edited `.tres` cannot turn a codex page into a stat table.
func effects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var catalog := OptionCatalog.instance()
	for entry in passive_options.slice(0, TechniquePolicy.PASSIVE_OPTION_CAP):
		var option_id := StringName(entry.get("option_id", ""))
		if option_id == &"":
			continue
		var effect := catalog.fixed_effect(option_id, float(entry.get("value", 0.0)))
		if not effect.is_empty():
			out.append(effect)
	return out
