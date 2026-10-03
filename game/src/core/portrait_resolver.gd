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
## without a refactor. A test asserts this file names no filesystem call at all.

## The `actor.module_data` key a chosen portrait id persists under.
const APPEARANCE_KEY := &"appearance"
## The `module_data` field holding the chosen portrait id.
const PORTRAIT_FIELD := "portrait_id"


## The portrait for `actor`, as primitives a panel can render.
##
## `{portrait_id, race_id, layer_paths, palette_key, form, source, is_placeholder}` where
## `source` is one of `chosen` / `race` / `placeholder` and names WHICH step answered. Without
## it a panel cannot tell a deliberately chosen face from a fallback, and a fallback that looks
## deliberate is how a content gap hides.
static func resolve(actor: Actor, race_id: StringName = &"") -> Dictionary:
	if actor == null:
		return _view(null, race_id, "none")
	# Step 1: the face this actor already chose, if it is still real content.
	var chosen := StringName(_chosen(actor))
	if chosen != &"":
		var def := PortraitCatalog.instance().portrait_definition(chosen)
		if def != null:
			return _view(def, race_id, "chosen")
	# Step 2: the body plan's own face. This is where every NPC lands.
	if race_id != &"":
		var by_race := PortraitCatalog.instance().for_race(race_id)
		if by_race != null:
			return _view(by_race, race_id, "race")
	# Step 3: the fallback. Null here means the content tree failed to load, and the view says
	# so rather than pretending an actor has no face.
	var placeholder := PortraitCatalog.instance().placeholder()
	return _view(placeholder, race_id, "placeholder")


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
		# A placeholder that also claims a race is a face that fails for exactly the actors who
		# most need one.
		if def.is_placeholder() and def.race_id != &"":
			problems.append("portrait: the placeholder names a race")
	return problems


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
static func _view(def: PortraitDef, race_id: StringName, source: String) -> Dictionary:
	if def == null:
		return {
			"portrait_id": "",
			"race_id": String(race_id),
			"layer_paths": [] as Array[String],
			"palette_key": "",
			"form": "",
			"source": source,
			"is_placeholder": true,
		}
	return {
		"portrait_id": String(def.id),
		"race_id": String(race_id),
		"layer_paths": def.layer_paths.duplicate(),
		"palette_key": String(def.palette_key),
		"form": def.trait("form"),
		"source": source,
		"is_placeholder": def.is_placeholder(),
	}
