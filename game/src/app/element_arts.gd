class_name ElementArts
extends RefCounted

## The root-refining arts (ADR 0924, BL-0926): one passive art per element,
## manual-delivered, and the app-side owner of their two affinity loops.
##
## ## Why this file lives in the app
##
## A source's requirement is "this actor knows this art" — a read of the TECHNIQUES
## facade — while the grant is written by the ELEMENTS facade. No module may name
## both (the registry declares no techniques -> elements edge), so the composition
## root owns the pair, exactly as it owns every other cross-module seam — the
## learner this file wraps is installed by `item_workbench_body.gd`.
##
## ## The two loops
##
## - The OPENING: learning the art applies a one-time grant (`once`), so a root
##   opens when the art is learned and never again.
## - The REFINE: a repeatable +1 source that runs to the per-element cap — slower
##   than any treasure, and free, because the art itself was the price.
##
## Both register through `ElementsApi.register_affinity_source`; the screen's Attune
## action picks them up like any other source, with no screen-side knowledge of them.

const _TECHNIQUES := preload("res://src/modules/techniques/api.gd")
const _ELEMENTS := preload("res://src/modules/elements/api.gd")

const ART_SUFFIX := "_root_refining"


static func art_id(element: StringName) -> StringName:
	return StringName("passive_" + String(element) + ART_SUFFIX)


static func manual_id(element: StringName) -> StringName:
	return StringName("manual_" + String(element) + ART_SUFFIX)


static func grant_id(art: StringName) -> StringName:
	return StringName("art_grant:" + String(art))


static func refine_id(art: StringName) -> StringName:
	return StringName("art_refine:" + String(art))


## Register the two sources per element. Idempotent: a re-registration overwrites
## the same id with an equal source, so the app may call this on every boot.
static func install() -> void:
	for entry in ElementDefaults.all():
		var def := entry as ElementDef
		var art := art_id(def.id)
		var tier := maxi(1, def.tier)
		_ELEMENTS.register_affinity_source(
			_source(
				grant_id(art),
				def.id,
				float(ElementAttunement.ART_GRANT_BY_TIER.get(tier, 2.0)),
				tier,
				"Root-Refining Art",
				true,
				art
			)
		)
		_ELEMENTS.register_affinity_source(
			_source(
				refine_id(art),
				def.id,
				ElementAttunement.ART_REFINE_STEP,
				tier,
				"Root-Refining Art",
				false,
				art
			)
		)


## Drop the sources `install()` registered. A MATCHED PAIR, and the reason is measured.
##
## `ElementAttunement._registered` is a `static var`, and every row in it is an
## `AffinitySource` carrying TWO LAMBDAS (its `check` and its `consume`). A process that
## registers on boot and never clears therefore leaves callables alive past teardown:
## Godot reports them as leaked ObjectDB instances with resources still in use, and the
## order it then frees them in is what produced the access violation this pair fixes -
## adding the registrations to an otherwise clean boot was 5 crashes in 5 runs, and
## removing them was 0 in 5.
##
## The registry is DEFINITIONS, not per-body state, so clearing it at exit costs nothing:
## `install()` is idempotent and re-registers the same rows on the next boot.
static func uninstall() -> void:
	_ELEMENTS.clear_registered_sources()


## The learner the app installs: learn the technique, then apply the art's opening
## grant when the technique is one.
##
## An art's grant on an element the climb has not reached refuses by name
## (`element_locked`) and is discarded: the art is learned and the root waits for
## the climb — the same order every other door keeps.
static func learn_with_root_grant(
	actor: Actor, technique_id: StringName, rung: int = 0
) -> Dictionary:
	var outcome := TechniqueDelivery.bind_learner(actor, technique_id, rung)
	if bool(outcome.get("ok", false)):
		grant_on_learn(actor, technique_id)
	return outcome


## Apply the art's one-time grant, if `technique_id` names an installed art. An
## unknown id refuses `no_source` inside the facade and is harmless here.
static func grant_on_learn(actor: Actor, technique_id: StringName) -> Dictionary:
	return _ELEMENTS.attune_source(actor, grant_id(technique_id))


static func _source(
	id: StringName,
	element: StringName,
	amount: float,
	tier: int,
	label: String,
	once: bool,
	art: StringName
) -> AffinitySource:
	var learned := func(who: Actor) -> bool: return _TECHNIQUES.codex(who).knows(art)
	var keep := func(_who: Actor) -> bool: return true
	return AffinitySource.make(id, element, amount, tier, label, once, learned, keep)
