class_name PortraitResolver
extends RefCounted

## Resolves any actor to a portrait. Total, ordered, and never null (ADR 0131).
##
## ## Three steps, each named, the last one always succeeding
##
## 1. a portrait id stored on the actor — a hero that went through creation;
## 2. the actor's body plan — an NPC, or a hero that never chose a face;
## 3. the placeholder, which always exists.
##
## **Step 3 is what makes resolution total**, and it is why NPCs need no special case: they are
## the common case, not the exception.
##
## ## Why the race arrives as a PARAMETER
##
## `core` depends on `contracts` alone. Asking `RaceApi` for the race would add a
## `core -> modules` edge, which the layering forbids outright. So the caller passes the id it
## already knows and this file stays a pure function of its arguments.
##
## ## Why this file never reads the asset index
##
## Because the generator is optional. The resolver reads authored `.tres` resources; the
## generator writes a PNG and an index row, and a sync step bridges them. Delete the index and
## every actor still resolves — which is the property that lets a rendering tool land later
## without a refactor. A test asserts this file names no index.
##
## `validate()` asks the filesystem ONE question — does a declared layer have a file — because a
## non-empty `layer_paths` is what let four portraits name art that does not exist (DEF-0297). It
## asks about a path AUTHORED IN the `.tres` and never opens an index, so the property above is
## untouched: deleting the index still resolves every actor.

## The `actor.module_data` key a chosen portrait id persists under.
const APPEARANCE_KEY := &"appearance"
## The `module_data` field holding the chosen portrait id.
const PORTRAIT_FIELD := "portrait_id"


## The portrait for `actor`, as primitives a panel can render.
##
## `{portrait_id, race_id, layer_paths, palette_key, form, source, is_placeholder, variant,
## variant_found}` where `source` is one of `chosen` / `race` / `generated` / `placeholder` and
## names WHICH step answered. Without it a panel cannot tell a deliberately chosen face from a
## fallback, and a fallback that looks deliberate is how a content gap hides.
##
## `variant` is an `axis:value` string naming an occasion — `stage:retired`, `beat:elder_wei_freed`
## (ADR 0177). **A variant is an enhancement and never a requirement**: when the requested variant
## has no authored portrait the base face is returned unchanged, because resolution is total
## (ADR 0131) and a missing variant must not leave an actor faceless. `variant_found` says which
## happened, so a caller can tell "asked for the retired portrait and got the standing one" from
## "asked for nothing".
static func resolve(actor: Actor, race_id: StringName = &"", variant: String = "") -> Dictionary:
	if actor == null:
		return _view(null, race_id, "none", variant, false)
	# Step 1: the face this actor already chose, if it is still real content.
	var chosen := StringName(_chosen(actor))
	if chosen != &"":
		var def := PortraitCatalog.instance().portrait_definition(chosen)
		if def != null:
			return _variant_view(def, race_id, "chosen", variant)
	# Step 2: the body plan's own face. This is where every NPC lands.
	if race_id != &"":
		var by_race := PortraitCatalog.instance().for_race(race_id)
		if by_race != null:
			return _variant_view(by_race, race_id, "race", variant)
		# Step 2b: the GENERATED face for that body plan, when one exists. The generator has
		# shipped, so a race with thousands of authored characters no longer falls through to the
		# placeholder — and the lookup still goes through `PortraitIndex`, which is the only
		# file in `core/` that opens the generated index, so the promise this class makes (it
		# never reads an index) still holds.
		var generated := PortraitIndex.instance().character_for_race(race_id)
		var path := PortraitIndex.instance().portrait_path(generated)
		if path != "":
			return {
				"portrait_id": String(generated),
				"race_id": String(race_id),
				"layer_paths": [path] as Array[String],
				"palette_key": String(PortraitIndex.instance().palette_of(generated)),
				"form": String(PortraitIndex.instance().form_of(generated)),
				"source": "generated",
				"is_placeholder": false,
				# A generated row declares no variant: the catalog's tags carry no `axis:value`
				# a variant could match on, and `PortraitIndex` is deliberately not asked to
				# interpret one. So a requested variant is reported as not found rather than
				# silently answered from a tag that means something else.
				"variant": variant,
				"variant_found": false,
			}
	# Step 3: the fallback. Null here means the content tree failed to load, and the view says
	# so rather than pretending an actor has no face.
	var placeholder := PortraitCatalog.instance().placeholder()
	return _view(placeholder, race_id, "placeholder", variant, false)


## `def` as a view, after looking for a portrait that DECLARES `variant` (ADR 0177).
##
## The base def answers unless it declares the variant itself or a sibling does, so every one of
## the three steps keeps its own precedence and a variant never reorders them. The placeholder is
## exempt: it is the face every actor gets before any art exists, and a variant of the fallback
## would be a face nobody authored.
static func _variant_view(
	def: PortraitDef, race_id: StringName, source: String, variant: String
) -> Dictionary:
	if def == null or def.is_placeholder() or variant.is_empty():
		return _view(def, race_id, source, variant, false)
	if def.declares_variant(variant):
		return _view(def, race_id, source, variant, true)
	var found := PortraitCatalog.instance().for_variant(race_id, variant)
	if found == null:
		return _view(def, race_id, source, variant, false)
	return _view(found, race_id, source, variant, true)


## The portrait id `actor` has chosen, or `""`. Read through `module_data` so a save carries it
## with everything else (`Actor.to_dict` copies `module_data` verbatim).
static func chosen_portrait_id(actor: Actor) -> StringName:
	if actor == null:
		return &""
	return StringName(_chosen(actor))


## Record `portrait_id` as this actor's face. Idempotent, and refuses an id no content defines so
## a typo cannot paint an actor into a face nothing can explain.
static func choose(actor: Actor, portrait_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if PortraitCatalog.instance().portrait_definition(portrait_id) == null:
		return {"ok": false, "reason": "unknown_portrait"}
	var appearance: Dictionary = actor.get_module_data(APPEARANCE_KEY)
	appearance[PORTRAIT_FIELD] = String(portrait_id)
	actor.set_module_data(APPEARANCE_KEY, appearance)
	return {"ok": true, "reason": "", "portrait_id": String(portrait_id)}


## Content audit: every authored portrait is well-formed and the placeholder exists. The
## placeholder is not optional — without it resolution has no last step, and "no face" becomes
## a null every panel has to defend against.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	var catalog := PortraitCatalog.instance()
	if not catalog.is_loaded():
		problems.append("portrait: no authored portraits loaded")
		return problems
	if catalog.placeholder() == null:
		problems.append("portrait: the placeholder is missing, so resolution has no last step")
	for portrait_id in catalog.ids():
		var def := catalog.portrait_definition(portrait_id)
		if def == null:
			problems.append("portrait: %s has no definition" % portrait_id)
			continue
		if def.display_name.is_empty():
			problems.append("portrait: %s has no display name" % portrait_id)
		# The placeholder is exempt: it is the face every actor gets BEFORE any art exists, so
		# requiring a layer of it would make the fallback un-authorable and resolution total only
		# in theory. Every other portrait must have something to draw.
		if def.layer_paths.is_empty() and not def.is_placeholder():
			problems.append("portrait: %s has no layer to draw" % portrait_id)
		# Existence, never only a NON-EMPTY list: the four shipped race portraits declare a layer
		# under `res://assets/characters/portraits/`, a directory that does not exist, so a
		# non-empty array is exactly what let four portraits draw nothing while this audit was
		# green (DEF-0297). The message names the path, because "missing art" without it is what
		# lets the same gap survive review a second time.
		#
		# The placeholder is exempt for the SAME reason the empty-list check above exempts it, and
		# the exemption is extended rather than replaced: it is the face every actor gets before
		# any art exists and it declares no layer, so there is no file of it to ask for. Requiring
		# one would make the fallback un-authorable and resolution total only in theory (ADR 0131).
		#
		# A `for` over `layer_paths` and nothing else: no `while`, and neither loop grows the
		# array it walks.
		#
		# NOT wired into `tools check`, deliberately (DEF-0297, same reasoning as ADR 0193 for
		# `art_fidelity`): four portraits have no art and cannot get any from here, so a build
		# gate would be permanently red over a content gap and would stop being read. Report it
		# here; only gate on it once at least one race portrait resolves.
		if not def.is_placeholder():
			for layer_path in def.layer_paths:
				if not FileAccess.file_exists(layer_path):
					problems.append("portrait: %s has no file at %s" % [portrait_id, layer_path])
		# A placeholder that also claims a race is a face that fails for exactly the actors who
		# most need one.
		if def.is_placeholder() and def.race_id != &"":
			problems.append("portrait: the placeholder names a race")
		# TWO portraits declaring the same variant for the same body plan is a content bug the
		# lookup cannot report: `for_variant` takes the first in sorted id order, so the loser is
		# shadowed with no error anywhere. The axis is open by design (ADR 0177), so this compares
		# declared traits rather than testing a fixed list that would go stale on the first new one.
		for other_id in catalog.ids():
			if other_id == portrait_id:
				continue
			var other := catalog.portrait_definition(other_id)
			if other == null or other.race_id != def.race_id:
				continue
			for shadowed in _variants_shared_with(def, other):
				(
					problems
					. append(
						(
							"portrait: %s and %s both declare variant '%s' for race '%s'; only %s is reachable"
							% [portrait_id, other_id, shadowed, def.race_id, portrait_id]
						)
					)
				)
	return problems


## Every trait `left` and `right` both declare, whole. Two portraits sharing `palette:neutral` is
## not a collision; sharing `stage:retired` is, because that is a selectable variant.
##
## A `for` over one authored array bounded by its length, and the inner `for` over the other. No
## `while`, and neither loop grows the array it walks.
static func _variants_shared_with(left: PortraitDef, right: PortraitDef) -> Array[String]:
	var shared: Array[String] = []
	for left_trait in left.visual_traits:
		for right_trait in right.visual_traits:
			if String(left_trait) == String(right_trait):
				shared.append(String(left_trait))
	return shared


# --- Internals -------------------------------------------------------------


## The stored id, tolerating a missing or malformed `appearance` payload. A save written before
## this feature existed has no key at all, and that must read as "chose nothing".
static func _chosen(actor: Actor) -> String:
	var appearance = actor.get_module_data(APPEARANCE_KEY)
	if not (appearance is Dictionary):
		return ""
	return String((appearance as Dictionary).get(PORTRAIT_FIELD, ""))


## One portrait as primitives. `layer_paths` is duplicated so a caller cannot mutate the
## authored resource through the dictionary it was handed, and an absent definition yields empty
## fields rather than nulls.
##
## `variant` and `variant_found` are always present, including on the "generated" and "none" views,
## so a panel never has to guard on their presence to decide whether to report a content gap.
static func _view(
	def: PortraitDef, race_id: StringName, source: String, variant: String, variant_found: bool
) -> Dictionary:
	if def == null:
		return {
			"portrait_id": "",
			"race_id": String(race_id),
			"layer_paths": [] as Array[String],
			"palette_key": "",
			"form": "",
			"source": source,
			"is_placeholder": true,
			"variant": variant,
			"variant_found": false,
		}
	return {
		"portrait_id": String(def.id),
		"race_id": String(race_id),
		"layer_paths": def.layer_paths.duplicate(),
		"palette_key": String(def.palette_key),
		"form": def.trait_value("form"),
		"source": source,
		"is_placeholder": def.is_placeholder(),
		"variant": variant,
		"variant_found": variant_found,
	}
