class_name WorldmapTemplates
extends RefCounted

## Reusable generation definitions: biome, settlement, road, chunk and region
## templates. A template is DATA — a plain Dictionary validated here — so a
## new asset pack or a new hamlet shape registers rows, never code. `chunk`
## templates expand to generator configs; `region` templates name a chunk
## template plus chunk coordinates for merged rendering. Validators refuse the
## first bad field by name: a template that cannot generate is reported at
## registration, not mid-chunk.
##
## One seeded built-in proves the registry with real art (greenwood
## wilderness); everything else registers. Tests reset through `clear`, and
## the next call re-seeds the built-in — a cleared registry is never observed
## half-built.

const KIND_BIOME := "biome"
const KIND_SETTLEMENT := "settlement"
const KIND_ROAD := "road"
const KIND_CHUNK := "chunk"
const KIND_REGION := "region"

static var _tables := {"biome": {}, "settlement": {}, "road": {}, "chunk": {}, "region": {}}
static var _seeded := false


## Forget every registration. Tests only.
static func clear() -> void:
	_tables = {"biome": {}, "settlement": {}, "road": {}, "chunk": {}, "region": {}}
	_seeded = false


## Register a template of `kind`. Refuses unknown kinds, empty names,
## duplicates and invalid bodies — each by name.
static func register(kind: String, name: String, body: Dictionary) -> Dictionary:
	_ensure()
	if not _tables.has(kind):
		return {"ok": false, "reason": "unknown_kind", "kind": kind}
	if name.is_empty():
		return {"ok": false, "reason": "empty_name"}
	if (_tables[kind] as Dictionary).has(name):
		return {"ok": false, "reason": "duplicate_template", "name": name}
	var verdict := validate(kind, body)
	if not bool(verdict.get("ok", false)):
		return verdict
	(_tables[kind] as Dictionary)[name] = (body as Dictionary).duplicate(true)
	return {"ok": true, "reason": "", "name": name}


## The template body, or `{}` when no such template exists.
static func get_template(kind: String, name: String) -> Dictionary:
	_ensure()
	if not _tables.has(kind):
		return {}
	return ((_tables[kind] as Dictionary).get(name, {}) as Dictionary).duplicate(true)


## Every name registered under `kind`, sorted.
static func names(kind: String) -> Array:
	_ensure()
	if not _tables.has(kind):
		return []
	var out := (_tables[kind] as Dictionary).keys()
	out.sort()
	return out


## Whether `body` is a well-formed `kind` template. Every refusal names the
## first bad field; a body that passes here expands without surprises.
static func validate(kind: String, body: Dictionary) -> Dictionary:
	match kind:
		"biome":
			return _validate_biome(body)
		"settlement":
			return _validate_settlement(body)
		"road":
			return _validate_road(body)
		"chunk":
			return _validate_chunk(body)
		"region":
			return _validate_region(body)
	return {"ok": false, "reason": "unknown_kind", "kind": kind}


## Expand a chunk template to a generator config: biome fragment, then the
## template's own keys, then `overrides` — later wins, lists replace
## wholesale. Unknown template answers `{}`, never a guessed config.
static func chunk_config(name: String, overrides: Dictionary = {}) -> Dictionary:
	_ensure()
	var template := get_template(KIND_CHUNK, name)
	if template.is_empty():
		return {}
	var config := {}
	var biome := get_template(KIND_BIOME, String(template.get("biome", "")))
	for key in biome.keys():
		config[key] = biome[key]
	for key in template.keys():
		if String(key) == "biome":
			continue
		config[key] = template[key]
	for key in overrides.keys():
		config[key] = overrides[key]
	return config


static func _validate_biome(body: Dictionary) -> Dictionary:
	if String(body.get("environment", "")).is_empty():
		return {"ok": false, "reason": "empty_environment"}
	for key in ["palette", "scatter", "resources"]:
		if body.has(key) and not (body[key] is Array):
			return {"ok": false, "reason": "not_an_array", "field": key}
	for entry in body.get("scatter", []) as Array:
		if (
			not (entry is Dictionary)
			or String((entry as Dictionary).get("archetype", "")).is_empty()
		):
			return {"ok": false, "reason": "bad_scatter_entry"}
	return {"ok": true, "reason": ""}


static func _validate_settlement(body: Dictionary) -> Dictionary:
	var plots := body.get("plots", []) as Array
	if plots.is_empty():
		return {"ok": false, "reason": "empty_plots"}
	for plot in plots:
		var row := plot as Dictionary
		if row == null or String(row.get("archetype", "")).is_empty():
			return {"ok": false, "reason": "bad_plot"}
	return {"ok": true, "reason": ""}


static func _validate_road(body: Dictionary) -> Dictionary:
	if int(body.get("count", 1)) < 0:
		return {"ok": false, "reason": "negative_count"}
	return {"ok": true, "reason": ""}


static func _validate_chunk(body: Dictionary) -> Dictionary:
	if maxi(2, int(body.get("chunk_size", 0))) != int(body.get("chunk_size", 0)):
		return {"ok": false, "reason": "bad_chunk_size"}
	return {"ok": true, "reason": ""}


static func _validate_region(body: Dictionary) -> Dictionary:
	if String(body.get("chunk_template", "")).is_empty():
		return {"ok": false, "reason": "empty_chunk_template"}
	var coords := body.get("coords", []) as Array
	if coords.is_empty():
		return {"ok": false, "reason": "empty_coords"}
	for coord in coords:
		var pair := coord as Array
		if pair == null or pair.size() != 2:
			return {"ok": false, "reason": "bad_coord"}
	return {"ok": true, "reason": ""}


static func _ensure() -> void:
	if _seeded:
		return
	_seeded = true
	(_tables["biome"] as Dictionary)["greenwood_wilderness"] = {
		"environment": "mortal_greenwood",
		"palette": ["ground_tile.base_ground", "ground_tile.soft_ground"],
		"water": true,
		"scatter": [{"archetype": "flora.shrub", "density": 0.05, "blocking": true}],
		"resources":
		[
			{
				"archetype": "stone_and_ore.ore_vein",
				"density": 0.04,
				"blocking": true,
				"yield": {"ore": 2}
			}
		],
	}
