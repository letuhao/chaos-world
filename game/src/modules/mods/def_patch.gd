class_name DefPatch
extends RefCounted

## Applies a single def patch to a loaded def Resource (ADR 0184 §6 extension).
##
## A def patch modifies an existing def without replacing it entirely. The
## patch is applied in-place on the def Resource. Operations:
##   set       — replace the field value
##   add       — append to an array field
##   remove    — remove from an array field
##   multiply  — multiply a numeric field
##   add_number — add to a numeric field
##
## A patch that targets a non-existent def is a no-op (the def may not have
## been loaded). A patch that targets a non-existent field is refused with a
## named reason.


## Apply a patch to a def. Returns `{ok, reason, detail}`.
static func apply(def: Resource, patch: Dictionary) -> Dictionary:
	if def == null:
		return {"ok": false, "reason": "null_def", "detail": "def is null"}
	var field := String(patch.get("field", ""))
	if field.is_empty():
		return {"ok": false, "reason": "bad_field", "detail": "patch has no field"}
	var op := String(patch.get("operation", "set"))
	var value = patch.get("value", null)
	match op:
		"set":
			return _apply_set(def, field, value)
		"add":
			return _apply_add(def, field, value)
		"remove":
			return _apply_remove(def, field, value)
		"multiply":
			return _apply_multiply(def, field, value)
		"add_number":
			return _apply_add_number(def, field, value)
	return {"ok": false, "reason": "unknown_op", "detail": "unknown operation '%s'" % op}


static func _apply_set(def: Resource, field: String, value) -> Dictionary:
	if not def.get(field) == null and not _is_valid_property(def, field):
		return {
			"ok": false,
			"reason": "unknown_field",
			"detail": "'%s' is not a property on %s" % [field, def.get_class()]
		}
	def.set(field, value)
	return {"ok": true, "reason": "", "detail": ""}


static func _apply_add(def: Resource, field: String, value) -> Dictionary:
	var current = def.get(field)
	if current == null:
		return {
			"ok": false,
			"reason": "unknown_field",
			"detail": "'%s' is not a property on %s" % [field, def.get_class()]
		}
	if not (current is Array):
		return {"ok": false, "reason": "not_array", "detail": "'%s' is not an array" % field}
	(current as Array).append(value)
	return {"ok": true, "reason": "", "detail": ""}


static func _apply_remove(def: Resource, field: String, value) -> Dictionary:
	var current = def.get(field)
	if current == null:
		return {
			"ok": false,
			"reason": "unknown_field",
			"detail": "'%s' is not a property on %s" % [field, def.get_class()]
		}
	if not (current is Array):
		return {"ok": false, "reason": "not_array", "detail": "'%s' is not an array" % field}
	(current as Array).erase(value)
	return {"ok": true, "reason": "", "detail": ""}


static func _apply_multiply(def: Resource, field: String, value) -> Dictionary:
	var current = def.get(field)
	if current == null:
		return {
			"ok": false,
			"reason": "unknown_field",
			"detail": "'%s' is not a property on %s" % [field, def.get_class()]
		}
	if not (current is float) and not (current is int):
		return {"ok": false, "reason": "not_number", "detail": "'%s' is not a number" % field}
	if not (value is float) and not (value is int):
		return {"ok": false, "reason": "bad_value", "detail": "multiply value must be a number"}
	def.set(field, float(current) * float(value))
	return {"ok": true, "reason": "", "detail": ""}


static func _apply_add_number(def: Resource, field: String, value) -> Dictionary:
	var current = def.get(field)
	if current == null:
		return {
			"ok": false,
			"reason": "unknown_field",
			"detail": "'%s' is not a property on %s" % [field, def.get_class()]
		}
	if not (current is float) and not (current is int):
		return {"ok": false, "reason": "not_number", "detail": "'%s' is not a number" % field}
	if not (value is float) and not (value is int):
		return {"ok": false, "reason": "bad_value", "detail": "add_number value must be a number"}
	def.set(field, float(current) + float(value))
	return {"ok": true, "reason": "", "detail": ""}


static func _is_valid_property(def: Resource, field: String) -> bool:
	for property in def.get_property_list():
		if String(property.get("name", "")) == field:
			return true
	return false
