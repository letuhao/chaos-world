class_name CatalogOverlay
extends RefCounted

## Merges one content family's overlay stack into one id-keyed catalog
## (ADR 0184 §merge). Base first, mods in load order behind it; later roots
## win, but an id may only be replaced when the later root DECLARED it in
## its `overrides` — an undeclared same-id collision is a named, loud error,
## never a silent overwrite (ADR 0066's duplicated-constant trap).
##
## Static, pure: same stack, same result. Nothing here caches, clocks, or
## reaches outside `core`.

## One stack row: `{dir, owner, declared_overrides, id_field?}` — `dir` is the
## absolute directory to scan for this family, `owner` the mod id ("base" for
## the res://data root), `declared_overrides` the ids this root may replace,
## and `id_field` the def property holding this family's id when it is not
## "id" (e.g. WorldLocationDef's "location_id"). A missing `dir` degrades
## to an empty contribution, as catalogs today treat an absent directory as
## an empty one.


## Merge `stack` for defs of `script_class` (e.g. "ItemDef"), reading each
## def's id from `id_field` (default "id"; a row may override it). On success:
## `{ok: true, reason: "", detail: "", merged, paths, owners}` where `merged`
## is an Array of `{id, path, owner}` in overlay order (an overridden id keeps
## its EARLIER position while its def is REPLACED), `paths` maps id -> winning
## path, and `owners` maps id -> winning root's owner.
## On a collision nobody declared: `{ok: false, reason: "undeclared_override",
## detail}` naming the id, the owner and BOTH paths.
static func merge(stack: Array, script_class: String, id_field: String = "id") -> Dictionary:
	var merged: Array[Dictionary] = []
	var positions := {}  # id -> index into `merged`; snapshot of size, so the
	# override pass never re-tests a structure it is itself growing.
	var paths := {}  # id -> winning path
	var owners := {}  # id -> winning owner
	for root in stack:
		var declared := _declared_set(root)
		var dir := String(root.get("dir", ""))
		var owner := String(root.get("owner", ""))
		var row_id_field := String(root.get("id_field", id_field))
		var files := ContentScan.files_under(dir)
		for path in files:
			if not path.ends_with(".tres"):
				continue
			if not FileAccess.get_file_as_string(path).contains('script_class="%s"' % script_class):
				continue
			# A failed load can return a non-Resource (raw file text) when the
			# global class cache is incomplete; only a Resource has `get`.
			var def = load(path)
			if not (def is Resource):
				continue
			# A def whose id property is absent (e.g. WorldLocationDef read with
			# the default id_field) has no id to merge; skip before String().
			var raw_id = def.get(row_id_field)
			if raw_id == null:
				continue
			var id := String(raw_id)
			if id.is_empty():
				continue
			if positions.has(id):
				if declared.has(id):
					var index := int(positions[id])
					merged[index] = {"id": id, "path": path, "owner": owner}
					paths[id] = path
					owners[id] = owner
				else:
					return {
						"ok": false,
						"reason": "undeclared_override",
						"detail":
						(
							"undeclared_override id=%s dir=%s owner=%s: later def %s collides with earlier def %s"
							% [id, dir, owner, path, String(paths[id])]
						),
						"merged": [],
						"paths": {},
						"owners": {},
					}
			else:
				positions[id] = merged.size()
				merged.append({"id": id, "path": path, "owner": owner})
				paths[id] = path
				owners[id] = owner
	return {
		"ok": true, "reason": "", "detail": "", "merged": merged, "paths": paths, "owners": owners
	}


## Normalise the declared-override row into a lookup set. Rows arrive as a
## PackedStringArray from one caller and a plain Array from another; comparing
## with `in` across the two shapes is the drift this helper exists to stop.
static func _declared_set(root) -> Dictionary:
	var out := {}
	for entry in root.get("declared_overrides", []):
		out[String(entry)] = true
	return out
